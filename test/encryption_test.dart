import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AES-GCM encryption and decryption round-trip', () async {
    final cipher = AesGcm.with256bits();
    final key = SecretKey([
      17, 42, 99, 104, 25, 67, 88, 12, 190, 201, 44, 73, 91, 15, 233, 81,
      33, 77, 102, 18, 54, 95, 111, 23, 145, 167, 89, 21, 62, 78, 199, 240
    ]);
    final nonce = List<int>.generate(12, (i) => (i * 7 + 13) % 256);

    const originalText = 'Hello B, this is A talking!';
    final secretBox = await cipher.encrypt(
      utf8.encode(originalText),
      secretKey: key,
      nonce: nonce,
    );

    final concatenationBytes = secretBox.concatenation();
    print('concatenationBytes length: ${concatenationBytes.length}');
    final base64Payload = base64Encode(concatenationBytes);

    // Decrypt
    final data = base64Decode(base64Payload);
    try {
      final parsedBox = SecretBox.fromConcatenation(
        data,
        nonceLength: 12,
        macLength: 16,
      );
      final clearText = await cipher.decrypt(
        parsedBox,
        secretKey: key,
      );
      final result = utf8.decode(clearText);
      expect(result, originalText);
      print('Decryption SUCCESS: $result');
    } catch (e) {
      print('Decryption FAILED: $e');
      fail('Decryption failed: $e');
    }
  });
}
