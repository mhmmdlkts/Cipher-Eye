import 'package:cipher_eye/services/crypto_service.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final key = CryptoService.keyFromMaster('ABCDEFGHIJKLMNOPQRSTUVWXYZ012345');

  test('encrypt/decrypt round-trip with fresh IVs', () {
    final a = CryptoService.encrypt('geheim', key);
    final b = CryptoService.encrypt('geheim', key);
    expect(a.iv, isNot(b.iv));
    expect(CryptoService.decrypt(value: a.value, iv: a.iv, v: 2, key: key), 'geheim');
  });

  test('wrong key fails (GCM tag)', () {
    final other = CryptoService.randomKey();
    final e = CryptoService.encrypt('geheim', key);
    expect(() => CryptoService.decrypt(value: e.value, iv: e.iv, v: 2, key: other),
        throwsA(anything));
  });

  test('legacy v1 blobs decrypt', () {
    final legacy = Encrypter(AES(key)).encrypt('alt', iv: IV.allZerosOfLength(16)).base64;
    expect(CryptoService.decrypt(value: legacy, iv: null, v: 1, key: key), 'alt');
  });

  test('randomKey is 32 bytes and unique', () {
    expect(CryptoService.randomKey().bytes.length, 32);
    expect(CryptoService.randomKey().base64, isNot(CryptoService.randomKey().base64));
  });
}
