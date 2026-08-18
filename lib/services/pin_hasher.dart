import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Salted PBKDF2-HMAC-SHA256 for the app PIN. The PIN is only ever stored as
/// (salt, hash); the plaintext never touches storage.
class PinHasher {
  static const int iterations = 10000;
  static const int _saltLength = 16;

  static String newSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(_saltLength, (_) => rnd.nextInt(256));
    return base64Encode(bytes);
  }

  static String hash(String pin, String saltB64) {
    final salt = base64Decode(saltB64);
    final hmac = Hmac(sha256, utf8.encode(pin));
    // PBKDF2 with a single block (32 bytes = SHA-256 output) is enough here.
    var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    final out = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < out.length; j++) {
        out[j] ^= u[j];
      }
    }
    return base64Encode(out);
  }

  static bool verify(String pin, String saltB64, String expectedHash) {
    final actual = hash(pin, saltB64);
    if (actual.length != expectedHash.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual.codeUnitAt(i) ^ expectedHash.codeUnitAt(i);
    }
    return diff == 0;
  }
}
