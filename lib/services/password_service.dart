import 'package:cipher_eye/services/crypto_service.dart';
import 'package:cipher_eye/services/item_service.dart';
import 'package:cipher_eye/services/secure_storage_service.dart';
import 'package:encrypt/encrypt.dart';

import '../models/item.dart';
import '../models/item_type.dart';

class PasswordService {
  static List<Item> get passwords => ItemService.items;
  static List<Item> get newPasswords =>
      ItemService.latest.where((i) => i.type == ItemType.password).toList();
  static List<Item> get drafts => ItemService.drafts;
  static List<Item> versionsOf(String purposeId) =>
      ItemService.versionsOf(purposeId);
  static void maskAll() => ItemService.maskAll();
  static Future<void> incrementUsage(String passwordId,
          {required bool copy}) =>
      ItemService.incrementUsage(passwordId, copy: copy);
  static Future<void> init() => ItemService.init();
  static Future addNewPassword(Item p) => ItemService.personal.add(p);
  static Future updatePassword(Item p) => ItemService.personal.updateVersion(p);
  static Future deletePassword(Item p) => ItemService.personal.delete(p);

  /// Current crypto/security version (see [CryptoService]). Entries below
  /// this need migration.
  static const int kCryptoVersion = CryptoService.kVersion;

  /// Builds the AES key from secure storage on demand. Never cached, so a key
  /// change in settings takes effect immediately and a missing key fails loudly
  /// instead of crashing at class-load time.
  static Key _requireKey() {
    final k = SecureStorageService.key;
    if (k == null) {
      throw StateError('Encryption key is not set');
    }
    return CryptoService.keyFromMaster(k);
  }

  /// Encrypts [value] with the master key (AES-GCM, random IV).
  static ({String value, String iv}) encode(String value) =>
      CryptoService.encrypt(value, _requireKey());

  /// Decrypts a stored value with the master key; the per-entry [v] decides
  /// between the current (GCM) and the legacy (v1) format.
  static String decode({required String value, String? iv, int? v}) =>
      CryptoService.decrypt(value: value, iv: iv, v: v, key: _requireKey());

}