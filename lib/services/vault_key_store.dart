import 'package:encrypt/encrypt.dart';

import 'crypto_service.dart';

/// Holds unwrapped vault keys for the session and wraps/unwraps them with the
/// master key for storage in users/{uid}/vaultKeys.
class VaultKeyStore {
  VaultKeyStore({required this.masterKey});

  final Key masterKey;
  final Map<String, Key> _keys = {};

  Map<String, dynamic> wrap(Key vaultKey) {
    final e = CryptoService.encrypt(vaultKey.base64, masterKey);
    return {'value': e.value, 'iv': e.iv, 'v': CryptoService.kVersion};
  }

  Key unwrap(Map<String, dynamic> doc) => Key.fromBase64(CryptoService.decrypt(
        value: doc['value'] as String,
        iv: doc['iv'] as String?,
        v: (doc['v'] as num?)?.toInt(),
        key: masterKey,
      ));

  void put(String vaultId, Key key) => _keys[vaultId] = key;
  Key? get(String vaultId) => _keys[vaultId];
  void remove(String vaultId) => _keys.remove(vaultId);
  void clear() => _keys.clear();
  Iterable<String> get vaultIds => _keys.keys;
}
