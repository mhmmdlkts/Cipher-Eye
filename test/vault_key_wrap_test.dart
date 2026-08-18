import 'package:cipher_eye/services/crypto_service.dart';
import 'package:cipher_eye/services/vault_key_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wrap/unwrap round-trip with the master key', () {
    final store = VaultKeyStore(
        masterKey: CryptoService.keyFromMaster('ABCDEFGHIJKLMNOPQRSTUVWXYZ012345'));
    final vk = CryptoService.randomKey();
    final doc = store.wrap(vk);
    expect(doc['v'], 2);
    expect(doc['value'], isNot(contains(vk.base64)));
    expect(store.unwrap(doc).base64, vk.base64);
  });

  test('wrong master key fails to unwrap', () {
    final a = VaultKeyStore(
        masterKey: CryptoService.keyFromMaster('ABCDEFGHIJKLMNOPQRSTUVWXYZ012345'));
    final b = VaultKeyStore(
        masterKey: CryptoService.keyFromMaster('ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ'));
    final doc = a.wrap(CryptoService.randomKey());
    expect(() => b.unwrap(doc), throwsA(anything));
  });

  test('in-memory map', () {
    final store = VaultKeyStore(masterKey: CryptoService.randomKey());
    final k = CryptoService.randomKey();
    store.put('v', k);
    expect(store.get('v')!.base64, k.base64);
    store.remove('v');
    expect(store.get('v'), isNull);
  });
}
