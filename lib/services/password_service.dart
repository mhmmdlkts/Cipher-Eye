import 'package:cipher_eye/services/crypto_service.dart';
import 'package:cipher_eye/services/firestore_paths_service.dart';
import 'package:cipher_eye/services/history_service.dart';
import 'package:cipher_eye/services/secure_storage_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart';

import '../models/password.dart';

class PasswordService {
  static final List<Password> passwords = [];
  static List<Password> get newPasswords =>
      passwords.where((p) => p.isLatest && !p.isDraft).toList();
  static List<Password> get drafts =>
      passwords.where((p) => p.isDraft).toList();

  /// All stored versions of a purpose (newest first), excluding drafts. The
  /// first entry is the current (latest) password; the rest are historical
  /// versions kept after edits so the old password can still be looked up.
  static List<Password> versionsOf(String purposeId) {
    final list = passwords
        .where((p) => p.purposeId == purposeId && !p.isDraft)
        .toList();
    list.sort((a, b) => (b.timestamp?.millisecondsSinceEpoch ?? 0)
        .compareTo(a.timestamp?.millisecondsSinceEpoch ?? 0));
    return list;
  }

  /// Re-masks every entry. Called when the password list (re)appears and on
  /// lock, so a revealed password is never shown again without a deliberate tap.
  static void maskAll() {
    for (final p in passwords) {
      p.isVisible = false;
    }
  }

  /// Increments the per-password usage counter in Firestore (copyCount or
  /// viewCount) so the most-used passwords can later be surfaced first.
  static Future<void> incrementUsage(String passwordId,
      {required bool copy}) async {
    final field = copy ? 'copyCount' : 'viewCount';
    await FirestorePathsService.getPasswordDoc(passwordId: passwordId)
        .update({field: FieldValue.increment(1)});
  }

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

  static Future<void> init() async {
    QuerySnapshot querySnapshot = await FirestorePathsService.getPasswordCol()
        .orderBy('purposeId').orderBy('timestamp', descending: true).get();

    passwords.clear();
    String? lastPurposeId;
    for (var doc in querySnapshot.docs) {
      Password password = Password.fromSnapshot(doc);
      if (lastPurposeId == null || lastPurposeId != password.purposeId) {
        password.isLatest = true;
        lastPurposeId = password.purposeId;
      }
      passwords.add(password);
    }
    passwords.sort();
  }

  static Future addNewPassword(Password password) async {
    passwords.where((element) => element.purposeId == password.purposeId).forEach((element) {element.isLatest = false;});
    password.isLatest = true;
    passwords.add(password);
    HistoryService.saveCreateHistory(password.id!);
    password.push();
  }

  /// Edits a password by storing a NEW version under the same purpose: the
  /// previous version is kept (marked non-latest) so the old password remains
  /// viewable, and the list shows the new one as if it had been overwritten.
  static Future updatePassword(Password password) async {
    passwords
        .where((element) => element.purposeId == password.purposeId)
        .forEach((element) {
      element.isLatest = false;
    });
    password.isLatest = true;
    passwords.add(password);
    HistoryService.saveUpdateHistory(password.id!);
    await password.push();
  }

  /// Encrypts [value] with the master key (AES-GCM, random IV).
  static ({String value, String iv}) encode(String value) =>
      CryptoService.encrypt(value, _requireKey());

  /// Decrypts a stored value with the master key; the per-entry [v] decides
  /// between the current (GCM) and the legacy (v1) format.
  static String decode({required String value, String? iv, int? v}) =>
      CryptoService.decrypt(value: value, iv: iv, v: v, key: _requireKey());

  static Future deletePassword(Password password) async {
    HistoryService.saveDeleteHistory(password.id!);
    // Drafts can share a purposeId (empty website + same username), so delete a
    // draft strictly by its own id.
    if (password.isDraft) {
      passwords.removeWhere((element) => element.id == password.id);
      await FirestorePathsService.getPasswordDoc(passwordId: password.id!)
          .delete();
      return;
    }
    // A real password: remove every stored version of its purpose, both from
    // memory and from Firestore, so no orphaned old-version docs are left.
    final versions = passwords
        .where((element) =>
            element.purposeId == password.purposeId && !element.isDraft)
        .toList();
    passwords.removeWhere((element) =>
        element.purposeId == password.purposeId && !element.isDraft);
    for (final v in versions) {
      await FirestorePathsService.getPasswordDoc(passwordId: v.id!).delete();
    }
  }

}