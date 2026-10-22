import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/mesh_message.dart';
import 'mesh_service.dart';

/// Pure P2P Offline Mesh Call Service.
/// Streams recorded voice chunks continuously over Google Nearby Connections (Bluetooth & Wi-Fi Direct).
/// Operates 100% offline without any Wi-Fi router, cellular network, or WebRTC IP/UDP setup.
/// Features continuous mic streaming + ping-pong dual audio players for fluent, gapless voice delivery.
class MeshCallService extends ChangeNotifier {
  final MeshService meshService;
  late StreamSubscription<MeshMessage> _signalingSub;

  final AudioRecorder _audioRecorder = AudioRecorder();
  // Dual alternating audio players (Ping-Pong buffer) to eliminate inter-chunk latency
  final AudioPlayer _playerA = AudioPlayer();
  final AudioPlayer _playerB = AudioPlayer();
  final AudioPlayer _ringtonePlayer = AudioPlayer();

  int _activePlayerIdx = 0; // 0 for playerA, 1 for playerB

  String? _currentCallEndpointId;
  String? _currentCallUserId;
  String? _currentCallPeerName;
  bool _isIncoming = false;
  bool _isActive = false;

  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isLocalSpeaking = false;
  bool _isRemoteSpeaking = false;

  int _callDurationSeconds = 0;
  Timer? _durationTimer;
  Timer? _remoteSpeakingResetTimer;
  Timer? _localSpeakingResetTimer;
  Timer? _bufferDrainTimer;

  // Stream-based continuous recording
  StreamSubscription<Uint8List>? _recordStreamSub;
  final BytesBuilder _pcmBuffer = BytesBuilder(copy: false);
  static const int _targetPcmChunkBytes = 16000; // 500ms of 16kHz 16-bit mono PCM

  // Fallback timer if stream recording is unavailable on specific device
  Timer? _fallbackRecordingTimer;
  String? _activeFallbackChunkPath;
  bool _useStreamRecording = true;

  // Jitter buffer queue of incoming audio chunk payloads to play seamlessly
  final List<Uint8List> _playbackQueue = [];
  bool _isPlayingQueue = false;
  int _sequenceNumber = 0;

  String? _tempPathA;
  String? _tempPathB;

  String? get currentCallEndpointId => _currentCallEndpointId;
  String? get currentCallUserId => _currentCallUserId;
  String? get currentCallPeerName => _currentCallPeerName;
  bool get isIncoming => _isIncoming;
  bool get isActive => _isActive;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isLocalSpeaking => _isLocalSpeaking;
  bool get isRemoteSpeaking => _isRemoteSpeaking;
  int get callDurationSeconds => _callDurationSeconds;

  String get formattedDuration {
    final minutes = (_callDurationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_callDurationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  MeshCallService(this.meshService) {
    _signalingSub = meshService.signalingStream.listen(_handleSignaling);
    _initAudioPlayers();
  }

  void _initAudioPlayers() {
    _playerA.onPlayerComplete.listen((_) => _onPlayerFinished(0));
    _playerB.onPlayerComplete.listen((_) => _onPlayerFinished(1));
  }

  void _onPlayerFinished(int playerIdx) {
    if (!_isActive) return;
    if (_playbackQueue.isNotEmpty) {
      _playNextInQueue();
    } else {
      _isPlayingQueue = false;
    }
  }

  @override
  void dispose() {
    _signalingSub.cancel();
    _endCallLocally();
    _audioRecorder.dispose();
    _playerA.dispose();
    _playerB.dispose();
    _ringtonePlayer.dispose();
    super.dispose();
  }

  // ─── Signaling & Audio Packet Dispatch ────────────────────────────────────

  void _handleSignaling(MeshMessage msg) async {
    final senderUserId = msg.senderId;
    final senderEndpointId = meshService.userIdToEndpoint[senderUserId];
    if (senderEndpointId == null) return;

    switch (msg.type) {
      case 'call_offer':
        if (_isActive || _isIncoming) {
          // Send busy signal if already on a call
          _sendPacket(senderEndpointId, {
            'type': 'call_busy',
            'senderId': meshService.userId,
            'receiverId': senderUserId,
          });
          return;
        }

        _isIncoming = true;
        _isActive = false;
        _currentCallEndpointId = senderEndpointId;
        _currentCallUserId = senderUserId;
        _currentCallPeerName = meshService.connectedPeers[senderEndpointId] ?? msg.senderName;
        _playbackQueue.clear();
        notifyListeners();

        _playRingtone();
        break;

      case 'call_answer':
        if (_currentCallUserId == senderUserId) {
          _stopRingtone();
          _isActive = true;
          _isIncoming = false;
          _startCallSession();
          notifyListeners();
        }
        break;

      case 'voice_chunk':
        if (_currentCallUserId == senderUserId && _isActive) {
          try {
            final data = jsonDecode(msg.payload);
            final base64Audio = data['audio'] as String?;
            if (base64Audio != null && base64Audio.isNotEmpty) {
              final bytes = base64Decode(base64Audio);
              _enqueueIncomingAudio(bytes);
            }
          } catch (e) {
            debugPrint('[MeshCallService] Error decoding voice chunk: $e');
          }
        }
        break;

      case 'call_busy':
        if (_currentCallUserId == senderUserId) {
          debugPrint('[MeshCallService] Remote peer is busy');
          _endCallLocally();
        }
        break;

      case 'call_end':
        if (_currentCallUserId == senderUserId) {
          _endCallLocally();
        }
        break;
    }
  }

  // ─── Fluent Jitter-Buffered Audio Playback Engine ─────────────────────────

  void _enqueueIncomingAudio(Uint8List audioBytes) {
    if (audioBytes.length < 50) return; // Discard degenerate fragments

    _playbackQueue.add(audioBytes);
    _isRemoteSpeaking = true;
    _remoteSpeakingResetTimer?.cancel();
    _remoteSpeakingResetTimer = Timer(const Duration(milliseconds: 1500), () {
      _isRemoteSpeaking = false;
      notifyListeners();
    });
    notifyListeners();

    if (!_isPlayingQueue) {
      // Jitter buffer: if starting cold, wait for 1-2 chunks or 100ms so network jitter is smoothed out
      if (_playbackQueue.length >= 2) {
        _playNextInQueue();
      } else {
        _bufferDrainTimer?.cancel();
        _bufferDrainTimer = Timer(const Duration(milliseconds: 80), () {
          if (!_isPlayingQueue && _playbackQueue.isNotEmpty) {
            _playNextInQueue();
          }
        });
      }
    }
  }

  Future<void> _playNextInQueue() async {
    if (_playbackQueue.isEmpty || !_isActive) {
      _isPlayingQueue = false;
      return;
    }

    _isPlayingQueue = true;

    // Fluent enhancement: if multiple chunks accumulated in jitter buffer,
    // merge them together into a contiguous audio segment to avoid inter-chunk gaps
    final List<Uint8List> batchToPlay = [];
    while (_playbackQueue.isNotEmpty && batchToPlay.length < 3) {
      batchToPlay.add(_playbackQueue.removeAt(0));
    }

    final mergedAudioBytes = _combineAudioChunks(batchToPlay);

    try {
      if (_tempPathA == null || _tempPathB == null) {
        final tempDir = await getTemporaryDirectory();
        _tempPathA = '${tempDir.path}/peer_stream_a.wav';
        _tempPathB = '${tempDir.path}/peer_stream_b.wav';
      }

      // Alternate between playerA and playerB for seamless handover
      final targetPlayer = (_activePlayerIdx == 0) ? _playerA : _playerB;
      final targetFilePath = (_activePlayerIdx == 0) ? _tempPathA! : _tempPathB!;
      _activePlayerIdx = (_activePlayerIdx == 0) ? 1 : 0;

      final file = File(targetFilePath);
      await file.writeAsBytes(mergedAudioBytes, flush: false);

      await targetPlayer.setVolume(_isSpeakerOn ? 1.0 : 0.6);
      await targetPlayer.play(DeviceFileSource(file.path));
    } catch (e) {
      debugPrint('[MeshCallService] Playback error: $e');
      _isPlayingQueue = false;
      if (_playbackQueue.isNotEmpty) {
        _playNextInQueue();
      }
    }
  }

  Uint8List _combineAudioChunks(List<Uint8List> chunks) {
    if (chunks.isEmpty) return Uint8List(0);
    if (chunks.length == 1) return chunks.first;

    // Check if chunks are WAV format (starting with 'RIFF')
    bool allWav = true;
    for (final c in chunks) {
      if (c.length < 44 || c[0] != 0x52 || c[1] != 0x49 || c[2] != 0x46 || c[3] != 0x46) {
        allWav = false;
        break;
      }
    }

    if (allWav) {
      final pcmBuilder = BytesBuilder(copy: false);
      for (final chunk in chunks) {
        pcmBuilder.add(chunk.sublist(44));
      }
      return _createWav(pcmBuilder.toBytes(), sampleRate: 16000, channels: 1);
    }

    // Fallback: Return first chunk if cannot combine
    return chunks.first;
  }

  // ─── Call Actions ─────────────────────────────────────────────────────────

  Future<void> startCall(String endpointId) async {
    final targetUserId = meshService.endpointToUserId[endpointId];
    if (targetUserId == null) return;

    _isIncoming = false;
    _isActive = false;
    _currentCallEndpointId = endpointId;
    _currentCallUserId = targetUserId;
    _currentCallPeerName = meshService.connectedPeers[endpointId] ?? 'Nearby Peer';
    _playbackQueue.clear();
    _callDurationSeconds = 0;
    notifyListeners();

    _playDialTone();

    // Send call offer packet
    _sendPacket(endpointId, {
      'type': 'call_offer',
      'senderId': meshService.userId,
      'senderName': meshService.userName,
      'receiverId': targetUserId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<void> acceptCall() async {
    if (_currentCallEndpointId == null || _currentCallUserId == null) return;

    _stopRingtone();
    _isIncoming = false;
    _isActive = true;
    notifyListeners();

    // Send call answer packet
    _sendPacket(_currentCallEndpointId!, {
      'type': 'call_answer',
      'senderId': meshService.userId,
      'senderName': meshService.userName,
      'receiverId': _currentCallUserId!,
      'timestamp': DateTime.now().toIso8601String(),
    });

    _startCallSession();
  }

  Future<void> endCall() async {
    if (_currentCallEndpointId != null && _currentCallUserId != null) {
      _sendPacket(_currentCallEndpointId!, {
        'type': 'call_end',
        'senderId': meshService.userId,
        'receiverId': _currentCallUserId!,
      });
    }
    _endCallLocally();
  }

  void _startCallSession() {
    _stopRingtone();
    _callDurationSeconds = 0;
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _callDurationSeconds++;
      notifyListeners();
    });

    // Start rolling continuous audio recording stream for real-time duplex voice
    _startContinuousAudioLoop();
  }

  void _endCallLocally() {
    _stopRingtone();
    _durationTimer?.cancel();
    _durationTimer = null;
    _remoteSpeakingResetTimer?.cancel();
    _remoteSpeakingResetTimer = null;
    _localSpeakingResetTimer?.cancel();
    _localSpeakingResetTimer = null;
    _bufferDrainTimer?.cancel();
    _bufferDrainTimer = null;

    _stopContinuousAudio();

    _playerA.stop();
    _playerB.stop();
    _playbackQueue.clear();
    _isPlayingQueue = false;

    _currentCallEndpointId = null;
    _currentCallUserId = null;
    _currentCallPeerName = null;
    _isIncoming = false;
    _isActive = false;
    _isLocalSpeaking = false;
    _isRemoteSpeaking = false;
    _callDurationSeconds = 0;

    notifyListeners();
  }

  // ─── Pure P2P Continuous Audio Streaming Engine ───────────────────────────

  void _startContinuousAudioLoop() async {
    if (!_isActive || _isMuted) return;

    final hasPerm = await _audioRecorder.hasPermission();
    if (!hasPerm) {
      debugPrint('[MeshCallService] Mic permission not granted');
      return;
    }

    _pcmBuffer.clear();
    await _recordStreamSub?.cancel();
    _recordStreamSub = null;

    try {
      if (await _audioRecorder.isRecording()) {
        await _audioRecorder.stop();
      }

      // 1. Continuous stream recording: Microphone never stops, eliminating audio dropouts!
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        bitRate: 128000,
        sampleRate: 16000,
        numChannels: 1,
      );

      final stream = await _audioRecorder.startStream(config);
      _useStreamRecording = true;

      _recordStreamSub = stream.listen(
        (data) {
          if (!_isActive || _isMuted) return;
          _pcmBuffer.add(data);

          // Once ~500ms of audio PCM is gathered, package as WAV and send
          if (_pcmBuffer.length >= _targetPcmChunkBytes) {
            _dispatchPcmChunk();
          }
        },
        onError: (err) {
          debugPrint('[MeshCallService] Audio stream error: $err, falling back to cyclic recording');
          _startFallbackRecordingLoop();
        },
      );
      debugPrint('[MeshCallService] Started continuous PCM mic stream (16kHz mono)');
    } catch (e) {
      debugPrint('[MeshCallService] Stream recording start error: $e, using fallback loop');
      _startFallbackRecordingLoop();
    }
  }

  void _dispatchPcmChunk() {
    if (_pcmBuffer.isEmpty) return;

    final rawBytes = _pcmBuffer.takeBytes();
    if (rawBytes.length < 500) return; // Ignore microscopic blips

    final wavBytes = _createWav(rawBytes, sampleRate: 16000, channels: 1);
    final base64Audio = base64Encode(wavBytes);

    _isLocalSpeaking = true;
    notifyListeners();
    _localSpeakingResetTimer?.cancel();
    _localSpeakingResetTimer = Timer(const Duration(milliseconds: 600), () {
      _isLocalSpeaking = false;
      notifyListeners();
    });

    if (_currentCallEndpointId != null && _isActive) {
      _sendPacket(_currentCallEndpointId!, {
        'type': 'voice_chunk',
        'seq': _sequenceNumber++,
        'senderId': meshService.userId,
        'receiverId': _currentCallUserId,
        'audio': base64Audio,
      });
    }
  }

  void _stopContinuousAudio() async {
    await _recordStreamSub?.cancel();
    _recordStreamSub = null;
    _fallbackRecordingTimer?.cancel();
    _fallbackRecordingTimer = null;
    _pcmBuffer.clear();

    try {
      if (await _audioRecorder.isRecording()) {
        await _audioRecorder.stop();
      }
    } catch (_) {}
  }

  // ─── Fallback Cyclic Recorder (for devices where startStream is unavailable)

  void _startFallbackRecordingLoop() async {
    _useStreamRecording = false;
    _fallbackRecordingTimer?.cancel();
    _fallbackRecordingTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      if (!_isActive || _isMuted) return;
      await _cycleFallbackRecordingChunk();
    });
    _startFallbackRecordingChunk();
  }

  Future<void> _startFallbackRecordingChunk() async {
    try {
      if (await _audioRecorder.isRecording()) {
        await _audioRecorder.stop();
      }
      final tempDir = await getTemporaryDirectory();
      _activeFallbackChunkPath = '${tempDir.path}/call_chunk_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 48000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _activeFallbackChunkPath!,
      );
    } catch (e) {
      debugPrint('[MeshCallService] Fallback chunk start error: $e');
    }
  }

  Future<void> _cycleFallbackRecordingChunk() async {
    final path = _activeFallbackChunkPath;
    try {
      if (await _audioRecorder.isRecording()) {
        await _audioRecorder.stop();
      }
      if (path != null && _isActive && _currentCallEndpointId != null) {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.length > 200) {
            _isLocalSpeaking = true;
            notifyListeners();
            Timer(const Duration(milliseconds: 700), () {
              _isLocalSpeaking = false;
              notifyListeners();
            });

            _sendPacket(_currentCallEndpointId!, {
              'type': 'voice_chunk',
              'seq': _sequenceNumber++,
              'senderId': meshService.userId,
              'receiverId': _currentCallUserId,
              'audio': base64Encode(bytes),
            });
          }
          try { await file.delete(); } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[MeshCallService] Fallback cycle error: $e');
    }

    if (_isActive && !_isMuted && !_useStreamRecording) {
      await _startFallbackRecordingChunk();
    }
  }

  // ─── Push-to-Talk (Walkie-Talkie Mode) ─────────────────────────────────────

  Future<void> startPushToTalk() async {
    if (!_isActive) return;
    _isLocalSpeaking = true;
    notifyListeners();
    if (!_useStreamRecording) {
      _fallbackRecordingTimer?.cancel();
      await _startFallbackRecordingChunk();
    }
  }

  Future<void> stopPushToTalk() async {
    if (!_isActive) return;
    if (_useStreamRecording) {
      _dispatchPcmChunk();
    } else {
      await _cycleFallbackRecordingChunk();
      if (!_isMuted) {
        _startFallbackRecordingLoop();
      }
    }
    _isLocalSpeaking = false;
    notifyListeners();
  }

  // ─── Audio Controls ───────────────────────────────────────────────────────

  void toggleMute() {
    _isMuted = !_isMuted;
    if (_isMuted) {
      _stopContinuousAudio();
      _isLocalSpeaking = false;
    } else {
      _startContinuousAudioLoop();
    }
    notifyListeners();
  }

  void toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    _playerA.setVolume(_isSpeakerOn ? 1.0 : 0.6);
    _playerB.setVolume(_isSpeakerOn ? 1.0 : 0.6);
    notifyListeners();
  }

  // ─── Tones & Ringtones ───────────────────────────────────────────────────

  void _playRingtone() async {
    try {
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.setVolume(1.0);
      await _ringtonePlayer.play(AssetSource('sounds/ringtone.mp3'));
    } catch (_) {}
  }

  void _playDialTone() async {
    try {
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.setVolume(0.5);
      await _ringtonePlayer.play(AssetSource('sounds/ringtone.mp3'));
    } catch (_) {}
  }

  void _stopRingtone() {
    try {
      _ringtonePlayer.stop();
    } catch (_) {}
  }

  // ─── Internal Packet Sender & Audio Encoding Helpers ─────────────────────

  void _sendPacket(String endpointId, Map<String, dynamic> packet) {
    final type = packet['type'] as String? ?? 'call_msg';
    final payloadStr = jsonEncode(packet);

    meshService.sendCallPacket(endpointId, {
      'type': type,
      'id': const Uuid().v4(),
      'senderId': meshService.userId,
      'senderName': meshService.userName,
      'receiverId': _currentCallUserId ?? '',
      'payload': payloadStr,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  static Uint8List _createWav(Uint8List pcmBytes, {int sampleRate = 16000, int channels = 1, int bitsPerSample = 16}) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final dataSize = pcmBytes.length;
    final chunkSize = 36 + dataSize;

    final header = ByteData(44);
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, chunkSize, Endian.little);
    header.setUint8(8, 0x57);  // W
    header.setUint8(9, 0x41);  // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little); // PCM sub-chunk size
    header.setUint16(20, 1, Endian.little);  // PCM format
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    final wav = Uint8List(44 + dataSize);
    wav.setRange(0, 44, header.buffer.asUint8List());
    wav.setRange(44, 44 + dataSize, pcmBytes);
    return wav;
  }
}
