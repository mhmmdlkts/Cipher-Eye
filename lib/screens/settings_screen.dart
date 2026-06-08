import 'package:cipher_eye/services/history_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../providers/key_provider.dart';
import '../widgets/app_text_field.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _keyController = TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool isLoading = false;
  bool isVisible = false;

  /// Requires device auth before a sensitive key action. If the device has no
  /// lock at all, allows it (can't enforce what doesn't exist).
  Future<bool> _reauth(String reason) async {
    try {
      if (!await _localAuth.isDeviceSupported()) return true;
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
        sensitiveTransaction: true,
      );
    } catch (_) {
      return false;
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
    if (!mounted) return;
    _keyController.clear();
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final key = ref.watch(keyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Encryption-Key')),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
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
                  await ref.read(keyProvider.notifier).removeKey();
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
