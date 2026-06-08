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
  List<Password> build() => PasswordService.newPasswords;

  void refresh() => state = PasswordService.newPasswords;

  Future<void> add(Password password) async {
    await PasswordService.addNewPassword(password);
    refresh();
  }

  Future<void> delete(Password password) async {
    await PasswordService.deletePassword(password);
    refresh();
  }

  /// Hide every revealed password (called when the list re-appears / on lock).
  void maskAll() {
    PasswordService.maskAll();
    refresh();
  }
}

final passwordsProvider =
    NotifierProvider<PasswordsNotifier, List<Password>>(PasswordsNotifier.new);
