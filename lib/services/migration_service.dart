import 'package:cipher_eye/services/firestore_paths_service.dart';
import 'package:cipher_eye/services/password_service.dart';
import 'package:cipher_eye/services/person_service.dart';
import 'package:cipher_eye/services/secure_storage_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Orchestrates the one-time, resumable migration of stored passwords from the
/// legacy crypto scheme (v1: AES-SIC, fixed zero IV) to the current one
/// (v2: AES-GCM, per-entry random IV). Safe to interrupt — only entries that
/// are still below [PasswordService.kCryptoVersion] are touched, and the
/// profile flag is only bumped once every entry has been migrated.
class MigrationService {
  /// Number of stored entries still on a legacy crypto version.
  static int get pendingCount =>
      PasswordService.passwords.where((p) => p.needsMigration).length;

  /// True when there is anything to bring up to the current version — either
  /// legacy entries, or a profile flag that hasn't caught up yet.
  static bool get isNeeded =>
      pendingCount > 0 ||
      PersonService.person.securityVersion < PasswordService.kCryptoVersion;

  /// Migration can only run when the encryption key is available locally;
  /// without it the legacy blobs cannot be decrypted (the key is never synced).
  static bool get canRun => SecureStorageService.key != null;

  /// Re-encrypts every legacy entry to v2, reporting progress as (done, total),
  /// then marks the profile as fully migrated once nothing is left below the
  /// current version. Idempotent: already-migrated entries are skipped.
  static Future<void> migrateAll(
      {void Function(int done, int total)? onProgress}) async {
    final pending =
        PasswordService.passwords.where((p) => p.needsMigration).toList();
    final total = pending.length;
    int done = 0;
    onProgress?.call(done, total);

    for (final password in pending) {
      await password.migrateCrypto();
      done++;
      onProgress?.call(done, total);
    }

    await _bumpProfileVersion();
  }

  /// Best-effort: marks the profile as fully migrated once every entry is v2.
  /// A failure here (e.g. a stricter-than-expected rule on the user doc) must
  /// not fail the whole migration — the password data is already safely
  /// re-encrypted. It is simply retried on the next launch.
  static Future<void> _bumpProfileVersion() async {
    if (!PasswordService.passwords.every((p) => !p.needsMigration) ||
        PersonService.person.securityVersion >= PasswordService.kCryptoVersion) {
      return;
    }
    try {
      // set(merge) rather than update(): creates the profile doc if it does
      // not exist yet (e.g. a freshly registered account) instead of failing.
      await FirestorePathsService.getUserDoc().set(
          {'securityVersion': PasswordService.kCryptoVersion},
          SetOptions(merge: true));
      // Only reflect it locally after the write actually succeeds.
      PersonService.person.securityVersion = PasswordService.kCryptoVersion;
    } catch (e) {
      // Profile flag couldn't be written; passwords are fine. Retried next launch.
    }
  }
}
