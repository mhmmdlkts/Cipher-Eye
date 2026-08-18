import 'package:cipher_eye/services/haptics.dart';
import 'package:cipher_eye/services/history_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../popup/pin_entry_popup.dart';
import '../providers/key_provider.dart';
import '../providers/vaults_provider.dart';
import '../services/app_auth_service.dart';
import '../services/secure_storage_service.dart';
import '../widgets/app_text_field.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _keyController = TextEditingController();
  bool isLoading = false;
  bool isVisible = false;

  /// Requires authentication (device auth, PIN as fallback) before a
  /// sensitive action.
  Future<bool> _reauth(String reason) =>
      AppAuthService.authenticate(context, reason: reason);

  Future<void> _setPin() async {
    final hasPin = SecureStorageService.hasPin;
    if (!await _reauth(hasPin
        ? 'Authentifiziere dich, um die PIN zu ändern'
        : 'Authentifiziere dich, um eine PIN festzulegen')) {
      return;
    }
    if (!mounted) return;
    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PinEntryPopup(mode: PinMode.setup),
    );
    if (!mounted) return;
    if (done == true) {
      Haptics.success();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(hasPin ? 'PIN geändert' : 'PIN festgelegt'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  bool get _isValid => _keyController.text.trim().length == 32;

  Future<void> _save() async {
    final key = _keyController.text.trim();
    if (key.length != 32) return;
    setState(() => isLoading = true);
    await ref.read(keyProvider.notifier).setKey(key);
    // Vault keys are wrapped with the master key → unlock/reload them now.
    await ref.read(vaultsProvider.notifier).refresh();
    if (!mounted) return;
    Haptics.success();
    _keyController.clear();
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final key = ref.watch(keyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Encryption-Key',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (key != null)
              _keyPlaceHolder(key)
            else
              AppTextField(
                controller: _keyController,
                label: 'Encryption-Key',
                hint: 'Deinen 32-stelligen Key eingeben',
                prefixIcon: Icons.vpn_key,
                maxLength: 32,
                onChanged: (_) => setState(() {}),
              ),
            const SizedBox(height: 32),
            Text('App-PIN', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              SecureStorageService.hasPin
                  ? 'Eine Ersatz-PIN ist festgelegt. Sie entsperrt die App, wenn '
                      'Face ID / Touch ID nicht verfügbar ist.'
                  : 'Noch keine Ersatz-PIN. Mit ihr lässt sich die App entsperren, '
                      'wenn Face ID / Touch ID nicht reagiert.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _setPin,
              icon: const Icon(Icons.pin_outlined),
              label: Text(
                  SecureStorageService.hasPin ? 'PIN ändern' : 'PIN festlegen'),
            ),
            const Spacer(),
            if (key == null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: !_isValid || isLoading ? null : _save,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: isLoading
                        ? const CircularProgressIndicator()
                        : const Text('Speichern'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _keyPlaceHolder(String key) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Aktueller Encryption-Key:',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                isVisible ? key : List.filled(key.length, '*').join(),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: isVisible ? 'Verbergen' : 'Anzeigen',
              onPressed: () async {
                if (!isVisible &&
                    !await _reauth(
                        'Authentifiziere dich, um den Key anzuzeigen')) {
                  return;
                }
                await HistoryService.saveShowKey();
                if (mounted) setState(() => isVisible = !isVisible);
              },
              icon: Icon(isVisible ? Icons.visibility : Icons.visibility_off),
            ),
            IconButton(
              tooltip: 'Löschen',
              onPressed: () async {
                if (!await _reauth(
                    'Authentifiziere dich, um den Key zu löschen')) {
                  return;
                }
                if (!mounted) return;
                final shouldDelete = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Sicher?'),
                    content:
                        const Text('Den aktuellen Encryption-Key löschen?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Ja')),
                      TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Nein')),
                    ],
                  ),
                );
                if (shouldDelete == true) {
                  Haptics.warning();
                  await ref.read(keyProvider.notifier).removeKey();
                  await ref.read(vaultsProvider.notifier).refresh();
                }
              },
              icon: const Icon(Icons.delete, color: Colors.red),
            ),
          ],
        ),
      ],
    );
  }
}
