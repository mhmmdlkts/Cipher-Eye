import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/secure_storage_service.dart';

/// Reactive state for the user's encryption key. The key itself still lives in
/// [SecureStorageService] (secure storage); this notifier mirrors it so the UI
/// (no-key banner, settings) updates the moment it changes.
class KeyNotifier extends Notifier<String?> {
  @override
  String? build() => SecureStorageService.key;

  Future<void> setKey(String key) async {
    await SecureStorageService.putKey(key);
    state = key;
  }

  Future<void> removeKey() async {
    await SecureStorageService.removeKey();
    state = null;
  }
}

final keyProvider = NotifierProvider<KeyNotifier, String?>(KeyNotifier.new);

/// Convenience: is an encryption key currently set?
final hasKeyProvider = Provider<bool>((ref) => ref.watch(keyProvider) != null);
