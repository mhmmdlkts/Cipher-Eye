import 'package:encrypt/encrypt.dart';

/// AES-256-GCM with an explicit key. Used with the master key for personal
/// items and with per-vault keys for shared items.
class CryptoService {
  /// v1 (legacy): AES-SIC, fixed zero IV. v2: AES-GCM, random IV.
  static const int kVersion = 2;
  static const int _gcmIvLength = 12;

  static Key keyFromMaster(String master) => Key.fromUtf8(master);

  static Key randomKey() => Key.fromSecureRandom(32);

  static ({String value, String iv}) encrypt(String plain, Key key) {
    final iv = IV.fromSecureRandom(_gcmIvLength);
    final encrypted =
        Encrypter(AES(key, mode: AESMode.gcm)).encrypt(plain, iv: iv);
    return (value: encrypted.base64, iv: iv.base64);
  }

  static String decrypt(
      {required String value, String? iv, int? v, required Key key}) {
    if ((v ?? 1) >= kVersion && iv != null) {
      return Encrypter(AES(key, mode: AESMode.gcm))
          .decrypt(Encrypted.fromBase64(value), iv: IV.fromBase64(iv));
    }
    // Byte-compatible with the original implementation (SIC + PKCS7 + zero IV).
    return Encrypter(AES(key))
        .decrypt(Encrypted.fromBase64(value), iv: IV.allZerosOfLength(16));
  }
}
