import 'package:encrypt/encrypt.dart';

import 'crypto_service.dart';
import 'secure_storage_service.dart';

typedef KeyResolver = Key Function(String? vaultId);

/// Which AES key an item uses: the master key for personal items
/// (`vaultId == null`), the vault key for shared ones. The resolver is
/// installed by ItemService once vault keys are loaded.
class Keys {
  static KeyResolver resolver = masterOnly;

  static Key masterOnly(String? vaultId) {
    if (vaultId != null) {
      throw StateError('Vault key for $vaultId is not available');
    }
    final k = SecureStorageService.key;
    if (k == null) throw StateError('Encryption key is not set');
    return CryptoService.keyFromMaster(k);
  }

  static Key resolve(String? vaultId) => resolver(vaultId);
}
