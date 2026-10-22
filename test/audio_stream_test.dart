import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

Uint8List createWav(Uint8List pcmBytes, {int sampleRate = 16000, int channels = 1, int bitsPerSample = 16}) {
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
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);  // PCM
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

Uint8List combineWavChunks(List<Uint8List> chunks, {int sampleRate = 16000}) {
  if (chunks.isEmpty) return Uint8List(0);
  if (chunks.length == 1) return chunks.first;

  final pcmBuilder = BytesBuilder(copy: false);
  for (final chunk in chunks) {
    if (chunk.length > 44 &&
        chunk[0] == 0x52 &&
        chunk[1] == 0x49 &&
        chunk[2] == 0x46 &&
        chunk[3] == 0x46) {
      // Valid WAV, strip 44-byte header
      pcmBuilder.add(chunk.sublist(44));
    } else {
      pcmBuilder.add(chunk);
    }
  }

  final mergedPcm = pcmBuilder.toBytes();
  return createWav(mergedPcm, sampleRate: sampleRate);
}

void main() {
  test('RecordConfig compiles and createWav works', () {
    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      bitRate: 128000,
    );
    expect(config.encoder, AudioEncoder.pcm16bits);

    final fakePcm = Uint8List(3200); // 100ms of 16kHz 16bit mono PCM
    final wav = createWav(fakePcm, sampleRate: 16000);
    expect(wav.length, 44 + 3200);
    expect(wav[0], 0x52); // 'R'
    expect(wav[1], 0x49); // 'I'
    expect(wav[2], 0x46); // 'F'
    expect(wav[3], 0x46); // 'F'
  });

  test('combineWavChunks correctly merges multiple WAV chunks into one seamless WAV', () {
    final chunk1 = createWav(Uint8List.fromList([1, 2, 3, 4]));
    final chunk2 = createWav(Uint8List.fromList([5, 6, 7, 8]));
    final combined = combineWavChunks([chunk1, chunk2]);

    expect(combined.length, 44 + 8);
    // Audio payload starts at byte 44
    expect(combined.sublist(44), [1, 2, 3, 4, 5, 6, 7, 8]);
  });
}
