import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cryptography/cryptography.dart';
import 'package:hive/hive.dart';
import '../models/mesh_message.dart';
import 'local_storage_service.dart';
import 'supabase_service.dart';

/// Communication mode for NIVARAN emergency networking
enum MeshCommunicationMode {
  online,           // Internet/cellular active + cloud sync available
  directOffline,    // Directly connected to nearby peers offline (0 intermediate hops)
  relayOfflineMesh, // Multi-hop mesh relay active (1+ intermediate hops)
  waitingForRelay,  // No peers currently in range; messages queued locally for store-and-forward
}

/// Mesh service using direct phone-to-phone wireless connections (Bluetooth Low Energy + Wi-Fi Direct / P2P).
/// Does NOT require any Wi-Fi router, cellular network, or internet connection.
/// Supports:
/// - Direct peer-to-peer messaging
/// - Multi-hop relay (A -> B -> C -> D)
/// - Store-and-forward (queued offline, auto-forwarded when peers are found)
/// - Deduplication via unique message IDs & processed cache
/// - Delivery status tracking (sending, waiting_for_relay, relayed, delivered)
/// - Transparent internet fallback when online
class MeshService extends ChangeNotifier {
  static const Strategy strategy = Strategy.P2P_CLUSTER;
  static const String _serviceId = 'com.safeher.mesh';

  /// Stable UUID for this device/session
  final String userId = const Uuid().v4();

  /// Human-readable device display name
  String userName;

  /// Broadcast name over BLE & Wi-Fi Direct: includes 8-char short ID to ensure unique tie-breaking
  String get _broadcastName => '${userId.substring(0, 8)}|$userName';

  /// All peers discovered: endpointId -> displayName
  final Map<String, String> nearbyEndpoints = {};

  /// Fully connected peers: endpointId -> displayName
  final Map<String, String> connectedPeers = {};

  /// Maps endpointId -> peer's userId (UUID)
  final Map<String, String> endpointToUserId = {};

  /// Reverse: peer userId -> endpointId
  final Map<String, String> userIdToEndpoint = {};

  /// Endpoints currently in process of connecting (prevent duplicate request calls)
  final Set<String> _connectingEndpoints = {};

  /// Stream for call signaling messages
  final _signalingController = StreamController<MeshMessage>.broadcast();
  Stream<MeshMessage> get signalingStream => _signalingController.stream;

  /// Stream for new chat / emergency messages
  final _chatMessageController = StreamController<MeshMessage>.broadcast();
  Stream<MeshMessage> get chatMessageStream => _chatMessageController.stream;

  /// Supabase Realtime Channel (used ONLY as online fallback when internet is available)
  RealtimeChannel? _broadcastChannel;
  RealtimeChannel? _adminChannel;

  Timer? _maintenanceTimer;
  Timer? _ttlTimer;

  bool _isInternetAvailable = false;
  bool get isInternetAvailable => _isInternetAvailable;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  int _totalRelayedCount = 0;
  int get totalRelayedCount => _totalRelayedCount;

  bool isAdmin = false;

  void toggleAdmin() {
    isAdmin = !isAdmin;
    notifyListeners();
  }

  // ─── Communication Mode Resolver ──────────────────────────────────────────
  MeshCommunicationMode get currentMode {
    if (_isInternetAvailable) {
      return MeshCommunicationMode.online;
    }
    if (connectedPeers.isNotEmpty) {
      bool hasMultiHopTraffic = _totalRelayedCount > 0;
      try {
        if (!hasMultiHopTraffic && Hive.isBoxOpen(LocalStorageService.chatBoxName)) {
          hasMultiHopTraffic = LocalStorageService.getEmergencyChatMessages().any((m) => m.hopCount > 0);
        }
      } catch (_) {}
      if (hasMultiHopTraffic || connectedPeers.length > 1) {
        return MeshCommunicationMode.relayOfflineMesh;
      }
      return MeshCommunicationMode.directOffline;
    }
    return MeshCommunicationMode.waitingForRelay;
  }

  String get currentModeLabel {
    switch (currentMode) {
      case MeshCommunicationMode.online:
        return 'Online';
      case MeshCommunicationMode.directOffline:
        return 'Direct Offline';
      case MeshCommunicationMode.relayOfflineMesh:
        return 'Relay/Offline Mesh';
      case MeshCommunicationMode.waitingForRelay:
        return 'Waiting for Relay';
    }
  }

  // ─── Mesh Security (AES-256-GCM) ─────────────────────────────────────────
  static final _cipher = AesGcm.with256bits();
  static final _key = SecretKey([
    17, 42, 99, 104, 25, 67, 88, 12, 190, 201, 44, 73, 91, 15, 233, 81,
    33, 77, 102, 18, 54, 95, 111, 23, 145, 167, 89, 21, 62, 78, 199, 240
  ]);

  String? userEmail;

  MeshService({this.userName = 'Nivaran User'});

  void updateUserName(String name) {
    if (name.isNotEmpty && userName != name) {
      userName = name;
      notifyListeners();
    }
  }

  void updateUserEmail(String email) {
    if (email.isNotEmpty && userEmail != email) {
      userEmail = email;
      notifyListeners();
    }
  }

  // ─── Lifecycle & Initialization ──────────────────────────────────────────

  Future<void> init() async {
    await _safeStop();
    _isScanning = true;
    notifyListeners();

    await startAdvertising();
    await startDiscovery();

    // Start background maintenance & keep-alive timer
    _startMaintenanceTimer();

    // Check initial internet status asynchronously (no blocking)
    _checkInternetConnectivity();

    // Setup Supabase online fallback channel
    _setupCloudFallbackChannel();
  }

  Future<bool> checkAndRequestPermissions() async {
    try {
      final statuses = await [
        Permission.location,
        Permission.locationWhenInUse,
        Permission.bluetooth,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.nearbyWifiDevices,
      ].request();

      final locGranted = (statuses[Permission.location]?.isGranted ?? false) ||
          (statuses[Permission.locationWhenInUse]?.isGranted ?? false);
      final btGranted = (statuses[Permission.bluetoothScan]?.isGranted ?? false) ||
          (statuses[Permission.bluetoothConnect]?.isGranted ?? false) ||
          (statuses[Permission.bluetooth]?.isGranted ?? false);

      return locGranted && btGranted;
    } catch (e) {
      debugPrint('[Mesh] Permission request error: $e');
      return false;
    }
  }

  Future<void> stopAll() async {
    _maintenanceTimer?.cancel();
    _maintenanceTimer = null;
    _ttlTimer?.cancel();
    _ttlTimer = null;

    await _safeStop();
    await _broadcastChannel?.unsubscribe();
    _broadcastChannel = null;
    await _adminChannel?.unsubscribe();
    _adminChannel = null;

    connectedPeers.clear();
    nearbyEndpoints.clear();
    endpointToUserId.clear();
    userIdToEndpoint.clear();
    _connectingEndpoints.clear();
    _isScanning = false;
    notifyListeners();
  }

  // ─── Messaging Public API ─────────────────────────────────────────────────

  /// Send an emergency message or chat to all reachable NIVARAN devices across the mesh.
  /// Works completely offline:
  /// - If peers are connected now: sends directly to all connected peers.
  /// - If no peers are reachable: queues in store-and-forward storage (status: 'waiting_for_relay').
  /// - When another peer comes in range, automatically syncs and forwards.
  /// - If internet is active, also pushes to Supabase Cloud as fallback for remote responders.
  Future<void> broadcastMessage(MeshMessage msg) async {
    // 1. Cache message ID locally to prevent re-processing our own message
    await LocalStorageService.markProcessed(msg.id);

    // 2. Initialize trace path
    msg.pathTrace = [userId];
    msg.hopCount = 0;

    // 3. Direct or Store-and-Forward dispatch
    if (connectedPeers.isEmpty) {
      msg.deliveryStatus = 'waiting_for_relay';
      await LocalStorageService.addMessage(msg);
      await LocalStorageService.queuePendingRelay(msg);
      debugPrint('[Mesh] Stored offline message ${msg.id} waiting for nearby relay');
      notifyListeners();
    } else {
      msg.deliveryStatus = 'sending';
      await LocalStorageService.addMessage(msg);
      notifyListeners();

      final secureMsg = await _encryptMessage(msg);
      for (final id in connectedPeers.keys) {
        await _sendBytes(id, secureMsg);
      }

      // Mark as relayed to at least one peer
      await LocalStorageService.updateDeliveryStatus(msg.id, 'relayed');
      notifyListeners();
    }

    // 4. Online fallback (if internet is available)
    if (_isInternetAvailable) {
      _syncToCloudFallback(msg);
    }
  }

  /// Send a direct message to a specific peer UUID or endpoint
  Future<void> sendDirectMessage(String peerTargetId, MeshMessage msg) async {
    await LocalStorageService.markProcessed(msg.id);
    msg.pathTrace = [userId];
    msg.hopCount = 0;

    // Robust resolution: peerTargetId might be a user UUID or a Nearby endpointId
    String? endpointId = userIdToEndpoint[peerTargetId];
    if (endpointId == null && connectedPeers.containsKey(peerTargetId)) {
      endpointId = peerTargetId;
    }

    final actualPeerUserId = (endpointId != null ? endpointToUserId[endpointId] : null) ?? peerTargetId;

    final outgoingMsg = MeshMessage(
      id: msg.id,
      senderId: msg.senderId,
      senderName: msg.senderName,
      senderEmail: msg.senderEmail ?? userEmail,
      receiverId: actualPeerUserId,
      payload: msg.payload,
      timestamp: msg.timestamp,
      type: msg.type,
      deliveryStatus: (endpointId != null && connectedPeers.containsKey(endpointId)) ? 'sending' : 'waiting_for_relay',
      hopCount: 0,
      pathTrace: [userId],
      isEncrypted: msg.isEncrypted,
      ackRequired: true,
      latitude: msg.latitude,
      longitude: msg.longitude,
      priority: msg.priority,
    );

    if (endpointId != null && connectedPeers.containsKey(endpointId)) {
      await LocalStorageService.addMessage(outgoingMsg);
      notifyListeners();

      final secureMsg = await _encryptMessage(outgoingMsg);
      await _sendBytes(endpointId, secureMsg);

      await LocalStorageService.updateDeliveryStatus(outgoingMsg.id, 'relayed');
      notifyListeners();
    } else {
      // Offline store-and-forward
      await LocalStorageService.addMessage(outgoingMsg);
      await LocalStorageService.queuePendingRelay(outgoingMsg);
      notifyListeners();
      debugPrint('[Mesh] Direct peer $peerTargetId not reachable; queued for relay');
    }

    if (_isInternetAvailable) {
      _syncToCloudFallback(outgoingMsg);
    }
  }

  /// Send payload directly to a specific endpoint (used by signaling)
  Future<void> sendToEndpoint(String endpointId, MeshMessage msg) async {
    await _sendBytes(endpointId, msg);
  }

  /// Send direct call control or audio stream chunks (pure P2P mesh voice)
  Future<void> sendCallPacket(String endpointId, Map<String, dynamic> data) async {
    try {
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
      await Nearby().sendBytesPayload(endpointId, bytes);
    } catch (e) {
      debugPrint('[Mesh] Error sending call packet to $endpointId: $e');
    }
  }

  /// Manually force a sync of all pending store-and-forward messages
  Future<void> syncPendingMessagesNow() async {
    final pending = LocalStorageService.getPendingRelays();
    if (pending.isEmpty || connectedPeers.isEmpty) return;

    for (final endpointId in connectedPeers.keys) {
      final peerUid = endpointToUserId[endpointId];
      if (peerUid != null) {
        await _syncPendingRelaysToPeer(endpointId, peerUid);
      }
    }
  }

  // ─── Advertising & Discovery (No router needed: BLE + Wi-Fi Direct) ───────

  Future<void> startAdvertising() async {
    try {
      await Nearby().startAdvertising(
        _broadcastName,
        strategy,
        serviceId: _serviceId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
      debugPrint('[Mesh] Advertising started ($_broadcastName)');
    } catch (e) {
      debugPrint('[Mesh] Advertising error: $e');
    }
  }

  Future<void> startDiscovery() async {
    try {
      await Nearby().startDiscovery(
        _broadcastName,
        strategy,
        serviceId: _serviceId,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: (id) {
          nearbyEndpoints.remove(id);
          notifyListeners();
          debugPrint('[Mesh] Endpoint lost: $id');
        },
      );
      debugPrint('[Mesh] Discovery started');
    } catch (e) {
      debugPrint('[Mesh] Discovery error: $e');
    }
  }

  // ─── Connection Handlers ─────────────────────────────────────────────────

  void _onEndpointFound(String id, String name, String serviceId) {
    debugPrint('[Mesh] Found endpoint $id ($name)');
    if (connectedPeers.containsKey(id) || _connectingEndpoints.contains(id)) return;

    // Parse the broadcast name
    final parts = name.split('|');
    final peerShortId = parts[0];
    final peerName = parts.length > 1 ? parts.sublist(1).join('|') : name;

    nearbyEndpoints[id] = peerName;
    notifyListeners();

    // Deterministic tie-breaker: device with higher shortId initiates the connection
    final myShortId = userId.substring(0, 8);
    if (myShortId.compareTo(peerShortId) > 0) {
      debugPrint('[Mesh] Initiating connection to $id ($peerName)');
      _connectingEndpoints.add(id);
      Nearby().requestConnection(
        _broadcastName,
        id,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      ).catchError((e) {
        debugPrint('[Mesh] requestConnection error: $e');
        _connectingEndpoints.remove(id);
        return false;
      });
    } else {
      debugPrint('[Mesh] Waiting for $id ($peerName) to initiate connection');
    }
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    debugPrint('[Mesh] Connection initiated with $endpointId (${info.endpointName})');

    final name = info.endpointName;
    final parts = name.split('|');
    final peerName = parts.length > 1 ? parts.sublist(1).join('|') : name;

    nearbyEndpoints[endpointId] = peerName;
    notifyListeners();

    Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: _onPayloadReceived,
      onPayloadTransferUpdate: (id, update) {},
    ).then((_) {
      _sendHandshake(endpointId);
    }).catchError((e) {
      debugPrint('[Mesh] acceptConnection error: $e');
      _connectingEndpoints.remove(endpointId);
    });
  }

  void _onConnectionResult(String endpointId, Status status) {
    _connectingEndpoints.remove(endpointId);
    final name = nearbyEndpoints[endpointId] ?? endpointId;
    debugPrint('[Mesh] Connection result $endpointId ($name): $status');

    if (status == Status.CONNECTED) {
      connectedPeers[endpointId] = name;
      nearbyEndpoints[endpointId] = name;
      notifyListeners();

      // Send handshake immediately to exchange UUID & name
      _sendHandshake(endpointId);
    } else {
      connectedPeers.remove(endpointId);
      final uid = endpointToUserId.remove(endpointId);
      if (uid != null) userIdToEndpoint.remove(uid);
      notifyListeners();
    }
  }

  void _onDisconnected(String endpointId) async {
    debugPrint('[Mesh] Disconnected $endpointId');
    _connectingEndpoints.remove(endpointId);

    final peerUserId = endpointToUserId.remove(endpointId);
    if (peerUserId != null) userIdToEndpoint.remove(peerUserId);

    connectedPeers.remove(endpointId);
    nearbyEndpoints.remove(endpointId);
    notifyListeners();

    // Restart discovery & advertising to quickly recover lost or transient links
    await Future.delayed(const Duration(seconds: 2));
    if (_isScanning) {
      try {
        await Nearby().stopDiscovery();
        await Nearby().stopAdvertising();
        await startDiscovery();
        await startAdvertising();
      } catch (e) {
        debugPrint('[Mesh] Restart error on disconnect: $e');
      }
    }
  }

  // ─── Payload Reception & Multi-Hop Relay ──────────────────────────────────

  Future<void> _onPayloadReceived(String endpointId, Payload payload) async {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) return;

    try {
      final jsonStr = utf8.decode(payload.bytes!);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final type = json['type'] as String? ?? '';

      // ── 1. Handshake ──
      if (type == 'handshake') {
        final peerUserId = json['userId'] as String;
        final peerName = json['name'] as String? ?? connectedPeers[endpointId] ?? 'Unknown';

        endpointToUserId[endpointId] = peerUserId;
        userIdToEndpoint[peerUserId] = endpointId;
        connectedPeers[endpointId] = peerName;
        nearbyEndpoints[endpointId] = peerName;
        debugPrint('[Mesh] Handshake completed with $peerName (ID: $peerUserId <-> Endpoint: $endpointId)');
        notifyListeners();

        // Send handshake reply back if not already a reply
        if (json['isReply'] != true) {
          _sendHandshake(endpointId, true);
        }

        // Immediately sync all pending store-and-forward messages to this new peer
        await _syncPendingRelaysToPeer(endpointId, peerUserId);
        return;
      }

      // ── 2. Delivery / Hop ACK ──
      if (type == 'ack' || type == 'receipt') {
        final messageId = json['messageId'] as String;
        final ackStatus = json['status'] as String? ?? 'relayed';
        debugPrint('[Mesh] ACK received for $messageId: $ackStatus from $endpointId');

        await LocalStorageService.updateDeliveryStatus(messageId, ackStatus);
        if (ackStatus == 'delivered' || ackStatus == 'delivered_to_admin') {
          await LocalStorageService.removePendingRelay(messageId);
        }
        notifyListeners();

        // Forward ACK backward along the path trace if we were a relay
        _forwardAckBackward(json, endpointId);
        return;
      }

      // ── 3. P2P Mesh Calling & Voice Audio Streaming ──
      if (type == 'call_offer' || type == 'call_answer' || type == 'call_end' || type == 'call_busy' || type == 'voice_chunk' || type == 'ice_candidate') {
        final msg = MeshMessage.fromJson(json);
        _signalingController.add(msg);
        return;
      }

      // ── 4. Admin ACK from Command Center ──
      if (type == 'admin_ack' || type == 'admin_receipt') {
        String origId = json['messageId'] ?? '';
        if (origId.isEmpty && json['payload'] != null) {
          try {
            final inner = jsonDecode(json['payload']);
            origId = inner['message_id'] ?? '';
          } catch (_) {
            origId = json['payload'];
          }
        }
        if (origId.isNotEmpty) {
          await LocalStorageService.updateDeliveryStatus(origId, 'delivered_to_admin');
          await LocalStorageService.removePendingRelay(origId);
          notifyListeners();
        }
        return;
      }

      // ── 5. Chat or SOS Emergency Alert ──
      final msg = MeshMessage.fromJson(json);

      // Deduplication: prevent infinite loops and duplicate processing
      if (LocalStorageService.isProcessed(msg.id)) {
        debugPrint('[Mesh] Duplicate message ${msg.id} ignored from $endpointId');
        _sendAck(endpointId, msg.id, 'relayed');
        return;
      }
      await LocalStorageService.markProcessed(msg.id);

      // Decrypt if encrypted
      MeshMessage processedMsg = msg;
      if (msg.isEncrypted) {
        processedMsg = await _decryptMessage(msg);
      }

      // Store in local history & update delivery status
      processedMsg.deliveryStatus = 'delivered';
      await LocalStorageService.addMessage(processedMsg);
      _chatMessageController.add(processedMsg);
      notifyListeners();

      // Send ACK back to the direct sender node
      await _sendAck(endpointId, msg.id, 'delivered');

      // CRITICAL REQUIREMENT:
      // If A is offline and B is online (in network), B relays A's chat or SOS message to Admin Panel!
      if (_isInternetAvailable) {
        _relayToCloudAdminPanel(processedMsg, endpointId);
      } else {
        // If B is currently offline too, queue in store-and-forward buffer to relay when network returns
        if (processedMsg.senderId != userId) {
          await LocalStorageService.queuePendingRelay(processedMsg);
        }
      }

      // Controlled Flooding Multi-Hop Relay
      await _relayMeshMessage(processedMsg, endpointId);
    } catch (e) {
      debugPrint('[Mesh] Error processing payload from $endpointId: $e');
    }
  }

  // ─── Multi-Hop Relay & Store-and-Forward Engine ──────────────────────────

  Future<void> _relayMeshMessage(MeshMessage msg, String fromEndpointId) async {
    // Max hop limit (TTL) to prevent endless propagation
    if (msg.hopCount >= 7) {
      debugPrint('[Mesh] Max hop count (7) reached for ${msg.id}. Dropping.');
      return;
    }

    final updatedHopCount = msg.hopCount + 1;
    final updatedPath = msg.pathTrace.contains(userId)
        ? msg.pathTrace
        : [...msg.pathTrace, userId];

    final relayMsg = MeshMessage(
      id: msg.id,
      senderId: msg.senderId,
      senderName: msg.senderName,
      senderEmail: msg.senderEmail,
      receiverId: msg.receiverId,
      payload: msg.payload,
      timestamp: msg.timestamp,
      type: msg.type,
      deliveryStatus: 'relayed',
      hopCount: updatedHopCount,
      pathTrace: updatedPath,
      isEncrypted: msg.isEncrypted,
      ackRequired: true,
      latitude: msg.latitude,
      longitude: msg.longitude,
      priority: msg.priority,
    );

    final secureMsg = relayMsg.isEncrypted ? relayMsg : await _encryptMessage(relayMsg);

    bool relayed = false;
    for (final id in connectedPeers.keys) {
      if (id == fromEndpointId) continue;
      final peerUid = endpointToUserId[id];
      // Do not forward back to any node already in the path trace
      if (peerUid != null && updatedPath.contains(peerUid)) continue;

      await _sendBytes(id, secureMsg);
      relayed = true;
      _totalRelayedCount++;
      debugPrint('[Mesh] Forwarded message ${msg.id} to $id (Hops: $updatedHopCount)');
    }

    // Store and forward: If no other peers are reachable right now, queue locally
    if (!relayed && msg.receiverId != userId) {
      await LocalStorageService.queuePendingRelay(relayMsg);
      debugPrint('[Mesh] Message ${msg.id} queued in store-and-forward buffer');
    }
    notifyListeners();
  }

  Future<void> _syncPendingRelaysToPeer(String endpointId, String peerUserId) async {
    final pending = LocalStorageService.getPendingRelays();
    if (pending.isEmpty) return;

    debugPrint('[Mesh] Syncing ${pending.length} store-and-forward messages to $peerUserId');
    for (final msg in pending) {
      // Don't forward to nodes already in path trace
      if (msg.pathTrace.contains(peerUserId)) continue;

      final forwardMsg = MeshMessage(
        id: msg.id,
        senderId: msg.senderId,
        senderName: msg.senderName,
        senderEmail: msg.senderEmail,
        receiverId: msg.receiverId,
        payload: msg.payload,
        timestamp: msg.timestamp,
        type: msg.type,
        deliveryStatus: 'relayed',
        hopCount: msg.hopCount + (msg.senderId == userId ? 0 : 1),
        pathTrace: msg.pathTrace.contains(userId) ? msg.pathTrace : [...msg.pathTrace, userId],
        isEncrypted: msg.isEncrypted,
        ackRequired: true,
        latitude: msg.latitude,
        longitude: msg.longitude,
        priority: msg.priority,
      );

      final secureMsg = msg.isEncrypted ? forwardMsg : await _encryptMessage(forwardMsg);
      await _sendBytes(endpointId, secureMsg);
      _totalRelayedCount++;

      // Mark locally as relayed
      await LocalStorageService.updateDeliveryStatus(msg.id, 'relayed');
    }
    notifyListeners();
  }

  void _forwardAckBackward(Map<String, dynamic> ackJson, String fromEndpointId) {
    // Relay the ACK backward to all other connected peers so original sender receives it
    final messageId = ackJson['messageId'] as String?;
    if (messageId == null) return;

    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(ackJson)));
    for (final id in connectedPeers.keys) {
      if (id != fromEndpointId) {
        Nearby().sendBytesPayload(id, bytes).catchError((_) {});
      }
    }
  }

  // ─── Network Packet Helpers ──────────────────────────────────────────────

  Future<void> _sendHandshake(String endpointId, [bool isReply = false]) async {
    try {
      final handshake = jsonEncode({
        'type': 'handshake',
        'userId': userId,
        'name': userName,
        'email': userEmail ?? '',
        'isReply': isReply,
      });
      final bytes = Uint8List.fromList(utf8.encode(handshake));
      await Nearby().sendBytesPayload(endpointId, bytes);
      debugPrint('[Mesh] Handshake packet sent to $endpointId (isReply: $isReply)');
    } catch (e) {
      debugPrint('[Mesh] Handshake error: $e');
    }
  }

  Future<void> _sendAck(String endpointId, String messageId, String status) async {
    try {
      final ack = jsonEncode({
        'type': 'ack',
        'messageId': messageId,
        'status': status,
        'nodeId': userId,
        'nodeName': userName,
      });
      final bytes = Uint8List.fromList(utf8.encode(ack));
      await Nearby().sendBytesPayload(endpointId, bytes);
    } catch (e) {
      debugPrint('[Mesh] Send ACK error: $e');
    }
  }

  Future<void> _sendBytes(String endpointId, MeshMessage msg) async {
    try {
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(msg.toJson())));
      await Nearby().sendBytesPayload(endpointId, bytes);
      debugPrint('[Mesh] Sent ${msg.type} to $endpointId (${bytes.length} bytes)');
    } catch (e) {
      debugPrint('[Mesh] Error sending bytes to $endpointId: $e');
    }
  }

  // ─── AES-256-GCM Encryption / Decryption ─────────────────────────────────

  Future<MeshMessage> _encryptMessage(MeshMessage msg) async {
    try {
      final nonce = List<int>.generate(12, (i) => (i * 7 + 13) % 256);
      final secretBox = await _cipher.encrypt(
        utf8.encode(msg.payload),
        secretKey: _key,
        nonce: nonce,
      );
      final encryptedPayload = base64Encode(secretBox.concatenation());

      return MeshMessage(
        id: msg.id,
        senderId: msg.senderId,
        senderName: msg.senderName,
        senderEmail: msg.senderEmail,
        receiverId: msg.receiverId,
        payload: encryptedPayload,
        timestamp: msg.timestamp,
        type: msg.type,
        deliveryStatus: msg.deliveryStatus,
        hopCount: msg.hopCount,
        pathTrace: msg.pathTrace,
        isEncrypted: true,
        ackRequired: msg.ackRequired,
        latitude: msg.latitude,
        longitude: msg.longitude,
        priority: msg.priority,
      );
    } catch (e) {
      debugPrint('[Mesh] Encryption error: $e');
      return msg;
    }
  }

  Future<MeshMessage> _decryptMessage(MeshMessage msg) async {
    try {
      final data = base64Decode(msg.payload);
      final secretBox = SecretBox.fromConcatenation(
        data,
        nonceLength: 12,
        macLength: 16,
      );
      final clearText = await _cipher.decrypt(
        secretBox,
        secretKey: _key,
      );

      return MeshMessage(
        id: msg.id,
        senderId: msg.senderId,
        senderName: msg.senderName,
        senderEmail: msg.senderEmail,
        receiverId: msg.receiverId,
        payload: utf8.decode(clearText),
        timestamp: msg.timestamp,
        type: msg.type,
        deliveryStatus: msg.deliveryStatus,
        hopCount: msg.hopCount,
        pathTrace: msg.pathTrace,
        isEncrypted: false,
        ackRequired: msg.ackRequired,
        latitude: msg.latitude,
        longitude: msg.longitude,
        priority: msg.priority,
      );
    } catch (e) {
      debugPrint('[Mesh] Decryption error: $e');
      return msg;
    }
  }

  // ─── Maintenance & Internet Fallback ─────────────────────────────────────

  void _startMaintenanceTimer() {
    _maintenanceTimer?.cancel();
    _maintenanceTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      // 1. Auto-sync store-and-forward queue to connected peers
      final pending = LocalStorageService.getPendingRelays();
      if (pending.isNotEmpty && connectedPeers.isNotEmpty) {
        for (final endpointId in connectedPeers.keys) {
          final peerUid = endpointToUserId[endpointId];
          if (peerUid != null) {
            await _syncPendingRelaysToPeer(endpointId, peerUid);
          }
        }
      }

      // 2. Check internet status for seamless online fallback
      await _checkInternetConnectivity();
    });
  }

  Future<void> _checkInternetConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      final online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      if (_isInternetAvailable != online) {
        _isInternetAvailable = online;
        notifyListeners();
        if (_isInternetAvailable) {
          _syncPendingToCloud();
        }
      }
    } catch (_) {
      if (_isInternetAvailable != false) {
        _isInternetAvailable = false;
        notifyListeners();
      }
    }
  }

  void _setupCloudFallbackChannel() {
    try {
      final supabase = Supabase.instance.client;
      _broadcastChannel?.unsubscribe();
      _adminChannel?.unsubscribe();

      // 1. Mesh Broadcast channel
      _broadcastChannel = supabase.channel('public:mesh_broadcasts').onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'mesh_broadcasts',
        callback: (payload) async {
          final data = payload.newRecord;
          if (data['sender_id'] == userId) return;

          final msg = MeshMessage(
            id: data['id'] ?? const Uuid().v4(),
            senderId: data['sender_id'] ?? 'remote',
            senderName: data['sender_name'] ?? 'Remote Responder',
            senderEmail: data['sender_email'],
            receiverId: 'broadcast',
            payload: data['payload'] ?? '',
            timestamp: DateTime.tryParse(data['created_at'] ?? '') ?? DateTime.now(),
            type: 'chat',
            deliveryStatus: 'delivered',
            priority: data['priority'] ?? 'normal',
          );

          if (!LocalStorageService.isProcessed(msg.id)) {
            await LocalStorageService.markProcessed(msg.id);
            await LocalStorageService.addMessage(msg);
            _chatMessageController.add(msg);
            notifyListeners();
          }
        },
      );
      _broadcastChannel?.subscribe();

      // 2. Admin Broadcasts Live Gateway: when Admin sends reply, relay back to offline mesh peers
      _adminChannel = supabase.channel('public:admin_broadcasts_gateway').onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'admin_broadcasts',
        callback: (payload) async {
          final data = payload.newRecord;
          if (data['is_admin'] != true) return; // Only process replies sent by Admin

          final adminMsgText = data['message'] as String? ?? '';
          final targetEmail = data['user_email'] as String? ?? '';
          final msgId = data['id']?.toString() ?? const Uuid().v4();

          final adminMeshMsg = MeshMessage(
            id: msgId,
            senderId: 'admin_command_center',
            senderName: 'Admin Support',
            senderEmail: 'admin@nivaran.app',
            receiverId: 'broadcast',
            payload: adminMsgText,
            timestamp: DateTime.tryParse(data['created_at'] ?? '') ?? DateTime.now(),
            type: 'chat',
            deliveryStatus: 'delivered',
            priority: 'normal',
          );

          if (!LocalStorageService.isProcessed(msgId)) {
            await LocalStorageService.markProcessed(msgId);
            await LocalStorageService.addMessage(adminMeshMsg);
            _chatMessageController.add(adminMeshMsg);
            notifyListeners();

            // Broadcast admin reply over BLE & Wi-Fi Direct mesh so offline A receives it!
            final secureMsg = await _encryptMessage(adminMeshMsg);
            for (final id in connectedPeers.keys) {
              await _sendBytes(id, secureMsg);
            }
            debugPrint('[Mesh Gateway] Relayed Admin reply back to offline mesh peers ($targetEmail)');
          }
        },
      );
      _adminChannel?.subscribe();
    } catch (e) {
      debugPrint('[Mesh] Cloud fallback setup: $e');
    }
  }

  void _syncToCloudFallback(MeshMessage msg) {
    _relayToCloudAdminPanel(msg);
  }

  /// Relays an offline peer's message to Supabase Admin Panel (admin_broadcasts & mesh_broadcasts)
  void _relayToCloudAdminPanel(MeshMessage msg, [String? directEndpointId]) {
    try {
      final senderEmail = (msg.senderEmail != null && msg.senderEmail!.isNotEmpty)
          ? msg.senderEmail!
          : (msg.senderName.contains('@')
              ? msg.senderName
              : '${msg.senderName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase()}@nivaran.app');

      // 1. Relayed Chat to admin_broadcasts for Admin Dashboard Live Chat
      Supabase.instance.client.from('admin_broadcasts').insert({
        'user_email': senderEmail,
        'message': msg.payload,
        'is_admin': false,
        'created_at': msg.timestamp.toUtc().toIso8601String(),
      }).then((_) {
        debugPrint('[Mesh Relay] Relayed peer ${msg.senderName} message to Admin Panel');
        if (directEndpointId != null) {
          _sendAck(directEndpointId, msg.id, 'delivered_to_admin');
        }
      }).catchError((e) {
        debugPrint('[Mesh Relay] Admin chat sync error: $e');
      });

      // 2. Also sync to mesh_broadcasts table
      Supabase.instance.client.from('mesh_broadcasts').insert({
        'id': msg.id,
        'sender_id': msg.senderId,
        'sender_name': msg.senderName,
        'payload': msg.payload,
        'is_admin': isAdmin,
        'priority': msg.priority,
      }).catchError((e) {
        debugPrint('[Mesh Relay] Mesh broadcast sync error: $e');
      });

      // 3. If SOS alert, log full emergency event
      if (msg.type == 'sos_alert') {
        _logPeerSOSToCloud(msg);
      }
    } catch (e) {
      debugPrint('[Mesh Relay] Cloud relay error: $e');
    }
  }

  void _logPeerSOSToCloud(MeshMessage msg) {
    try {
      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(msg.payload);
      } catch (_) {}

      final peerName = data['user_name'] ?? msg.senderName;
      final peerEmail = (msg.senderEmail != null && msg.senderEmail!.isNotEmpty)
          ? msg.senderEmail!
          : (data['user_email'] ?? '${peerName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase()}@nivaran.app');

      SupabaseService.logSOSEvent(
        userEmail: peerEmail,
        userName: peerName,
        type: 'Emergency Mesh SOS',
        latitude: msg.latitude ?? (data['latitude'] as num?)?.toDouble() ?? 0.0,
        longitude: msg.longitude ?? (data['longitude'] as num?)?.toDouble() ?? 0.0,
        meshPath: msg.pathTrace.isNotEmpty
            ? [...msg.pathTrace, userName, 'Command Center Gateway']
            : [peerName, userName, 'Command Center Gateway'],
        notes: 'Offline relayed SOS alert received via Nivaran P2P Mesh Network',
        blockchainHash: null,
        createdAt: msg.timestamp,
      ).then((res) {
        if (res['success'] == true) {
          debugPrint('[Mesh] Successfully uploaded peer SOS alert to cloud on their behalf');
        }
      });
    } catch (e) {
      debugPrint('[Mesh] Failed to log peer SOS to cloud: $e');
    }
  }

  void _syncPendingToCloud() {
    final pending = LocalStorageService.getPendingRelays();
    for (final msg in pending) {
      _relayToCloudAdminPanel(msg);
      LocalStorageService.removePendingRelay(msg.id);
    }
  }

  Future<void> _safeStop() async {
    try { await Nearby().stopAdvertising(); } catch (_) {}
    try { await Nearby().stopDiscovery(); } catch (_) {}
    try { await Nearby().stopAllEndpoints(); } catch (_) {}
  }
}
