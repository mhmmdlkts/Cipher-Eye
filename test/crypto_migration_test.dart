import 'dart:convert';

import 'package:cipher_eye/services/password_service.dart';
import 'package:cipher_eye/services/secure_storage_service.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const key = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ012345'; // 32 chars => AES-256

  // Reproduces the original (pre-migration) encryption: AES default mode (SIC)
  // + PKCS7 + all-zeros IV.
  String legacyEncode(String plain) {
    final encrypter = Encrypter(AES(Key.fromUtf8(key)));
    return encrypter.encrypt(plain, iv: IV.allZerosOfLength(16)).base64;
  }

  setUp(() {
    // Set the static directly so no secure-storage plugin is needed in tests.
    SecureStorageService.key = key;
  });

  test('legacy (v1) blobs still decrypt via the dual-format decode', () {
    const plain = 'correct horse battery staple!';
    final blob = legacyEncode(plain);
    expect(PasswordService.decode(value: blob, iv: null, v: 1), plain);
  });

  test('v2 encode/decode round-trips', () {
    const plain = 's0me-Sup3r-Secret/P@ss word';
    final enc = PasswordService.encode(plain);
    expect(PasswordService.decode(value: enc.value, iv: enc.iv, v: 2), plain);
  });

  test('v2 uses a fresh random IV (no keystream reuse)', () {
    const plain = 'same plaintext';
    final a = PasswordService.encode(plain);
    final b = PasswordService.encode(plain);
    expect(a.iv, isNot(b.iv));
    expect(a.value, isNot(b.value));
  });

  test('full migration path: legacy blob -> plaintext -> v2 -> plaintext', () {
    const plain = 'P@ssw0rd-to-migrate';
    final legacy = legacyEncode(plain);
    final recovered = PasswordService.decode(value: legacy, iv: null, v: 1);
    final reencrypted = PasswordService.encode(recovered);
    expect(
        PasswordService.decode(
            value: reencrypted.value, iv: reencrypted.iv, v: 2),
        plain);
  });

  test('GCM rejects a tampered ciphertext', () {
    final enc = PasswordService.encode('integrity matters');
    final bytes = base64.decode(enc.value);
    bytes[0] ^= 0xFF; // flip a ciphertext byte -> MAC check must fail
    final tampered = base64.encode(bytes);
    expect(() => PasswordService.decode(value: tampered, iv: enc.iv, v: 2),
        throwsA(anything));
  });
}
