import 'package:cipher_eye/services/firestore_paths_service.dart';
import 'package:cipher_eye/services/history_service.dart';
import 'package:cipher_eye/services/secure_storage_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart';

import '../models/password.dart';

class PasswordService {
  static final List<Password> passwords = [];
  static List<Password> get newPasswords => passwords.where((pass) {return pass.isLatest;}).toList();

  /// Re-masks every entry. Called when the password list (re)appears and on
  /// lock, so a revealed password is never shown again without a deliberate tap.
  static void maskAll() {
    for (final p in passwords) {
      p.isVisible = false;
    }
  }

  /// Current crypto/security version. Entries below this need migration.
  /// v1 (legacy): AES-SIC with a fixed all-zeros IV (insecure, keystream reuse).
  /// v2: AES-GCM with a per-entry random IV (authenticated).
  static const int kCryptoVersion = 2;

  /// Standard nonce length for AES-GCM (96 bit).
  static const int _gcmIvLength = 12;

  /// Builds the AES key from secure storage on demand. Never cached, so a key
  /// change in settings takes effect immediately and a missing key fails loudly
  /// instead of crashing at class-load time.
  static Key _requireKey() {
    final k = SecureStorageService.key;
    if (k == null) {
      throw StateError('Encryption key is not set');
    }
    return Key.fromUtf8(k);
  }

  static Future<void> init() async {
    QuerySnapshot querySnapshot = await FirestorePathsService.getPasswordCol()
        .orderBy('purposeId').orderBy('timestamp', descending: true).get();

    passwords.clear();
    String? lastPurposeId;
    querySnapshot.docs.forEach((doc) {
      Password password = Password.fromSnapshot(doc);
      if (lastPurposeId == null || lastPurposeId != password.purposeId) {
        password.isLatest = true;
        lastPurposeId = password.purposeId;
      }
      passwords.add(password);
    });
    passwords.sort();
  }

  static Future addNewPassword(Password password) async {
    passwords.where((element) => element.purposeId == password.purposeId).forEach((element) {element.isLatest = false;});
    password.isLatest = true;
    passwords.add(password);
    HistoryService.saveCreateHistory(password.id!);
    password.push();
  }

  /// Encrypts [value] with the current scheme (AES-GCM, random IV).
  /// Returns the ciphertext and the IV (both base64); both belong in the doc.
  static ({String value, String iv}) encode(String value) {
    final iv = IV.fromSecureRandom(_gcmIvLength);
    final encrypter = Encrypter(AES(_requireKey(), mode: AESMode.gcm));
    final encrypted = encrypter.encrypt(value, iv: iv);
    return (value: encrypted.base64, iv: iv.base64);
  }

  /// Decrypts a stored value, handling both the new (v2, GCM) and the
  /// legacy (v1, AES-SIC with a fixed zero IV) format. The per-entry [v]
  /// field decides which path is used — never a profile-level flag.
  static String decode({required String value, String? iv, int? v}) {
    if ((v ?? 1) >= kCryptoVersion && iv != null) {
      final encrypter = Encrypter(AES(_requireKey(), mode: AESMode.gcm));
      return encrypter.decrypt(Encrypted.fromBase64(value), iv: IV.fromBase64(iv));
    }
    return _decodeLegacy(value);
  }

  /// Byte-compatible with the original implementation: AES default mode (SIC)
  /// + PKCS7 padding + all-zeros IV. Only used to read pre-migration data.
  static String _decodeLegacy(String value) {
    final encrypter = Encrypter(AES(_requireKey()));
    return encrypter.decrypt(Encrypted.fromBase64(value), iv: IV.allZerosOfLength(16));
  }

  static Future deletePassword(Password password) async {
    HistoryService.saveDeleteHistory(password.id!);
    passwords.removeWhere((element) => element.purposeId == password.purposeId);
    await FirestorePathsService.getPasswordDoc(passwordId: password.id!).delete();
  }

}