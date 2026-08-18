import 'package:cipher_eye/services/crypto_service.dart';
import 'package:cipher_eye/services/keys.dart';
import 'package:encrypt/encrypt.dart';

/// Master-key crypto for personal items: builds the AES key from secure
/// storage on demand and delegates to [CryptoService].
class PasswordService {
  /// Current crypto/security version (see [CryptoService]). Entries below
  /// this need migration.
  static const int kCryptoVersion = CryptoService.kVersion;

  /// Builds the AES key from secure storage on demand. Never cached, so a key
  /// change in settings takes effect immediately and a missing key fails loudly
  /// instead of crashing at class-load time.
  static Key _requireKey() => Keys.masterOnly(null);

  /// Encrypts [value] with the master key (AES-GCM, random IV).
  static ({String value, String iv}) encode(String value) =>
      CryptoService.encrypt(value, _requireKey());

  /// Decrypts a stored value with the master key; the per-entry [v] decides
  /// between the current (GCM) and the legacy (v1) format.
  static String decode({required String value, String? iv, int? v}) =>
      CryptoService.decrypt(value: value, iv: iv, v: v, key: _requireKey());

}