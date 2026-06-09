import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/password.dart';
import '../services/password_service.dart';

/// Reactive view over the loaded passwords. [PasswordService] stays the
/// data/crypto/migration layer (loading, encryption, v1→v2 migration); this
/// notifier exposes the latest-per-purpose list to the UI so add/delete update
/// the screen automatically — no manual setState, no static list reads in
/// widgets.
class PasswordsNotifier extends Notifier<List<Password>> {
  @override
  List<Password> build() => _combined();

  /// Drafts first (newest), then the latest real entries.
  List<Password> _combined() {
    final drafts = PasswordService.drafts
      ..sort((a, b) => (b.timestamp?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.timestamp?.millisecondsSinceEpoch ?? 0));
    return [...drafts, ...PasswordService.newPasswords];
  }

  void refresh() => state = _combined();

  Future<void> add(Password password) async {
    await PasswordService.addNewPassword(password);
    refresh();
  }

  Future<void> delete(Password password) async {
    await PasswordService.deletePassword(password);
    refresh();
  }

  /// Persist a brand-new draft (a generated password, no website yet).
  Future<void> addDraft(Password draft) async {
    PasswordService.passwords.add(draft);
    refresh();
    await draft.push();
  }

  /// Persist edits to a draft; [finalize] promotes it to a real entry and marks
  /// it the latest version of its purpose.
  Future<void> saveDraft(Password draft, {bool finalize = false}) async {
    if (finalize) {
      for (final p in PasswordService.passwords
          .where((e) => e.purposeId == draft.purposeId && e.id != draft.id)) {
        p.isLatest = false;
      }
      draft.isLatest = true;
    }
    refresh();
    await draft.push();
  }

  /// Hide every revealed password (called when the list re-appears / on lock).
  void maskAll() {
    PasswordService.maskAll();
    refresh();
  }
}

final passwordsProvider =
    NotifierProvider<PasswordsNotifier, List<Password>>(PasswordsNotifier.new);
