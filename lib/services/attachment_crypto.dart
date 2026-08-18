import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';

/// Authenticated encryption for attachment blobs:
/// `iv (12 B) || AES-256-GCM(ciphertext || tag)`.
class AttachmentCrypto {
  static const int ivLength = 12;

  static Uint8List encrypt(Uint8List plain, Key key) {
    final iv = IV.fromSecureRandom(ivLength);
    final ct = Encrypter(AES(key, mode: AESMode.gcm)).encryptBytes(plain, iv: iv);
    final out = Uint8List(ivLength + ct.bytes.length);
    out.setRange(0, ivLength, iv.bytes);
    out.setRange(ivLength, out.length, ct.bytes);
    return out;
  }

  /// Throws when the blob was tampered with or the key is wrong.
  static Uint8List decrypt(Uint8List blob, Key key) {
    if (blob.length <= ivLength) throw const FormatException('Blob too short');
    final iv = IV(Uint8List.sublistView(blob, 0, ivLength));
    final ct = Encrypted(Uint8List.sublistView(blob, ivLength));
    return Uint8List.fromList(
        Encrypter(AES(key, mode: AESMode.gcm)).decryptBytes(ct, iv: iv));
  }
}
