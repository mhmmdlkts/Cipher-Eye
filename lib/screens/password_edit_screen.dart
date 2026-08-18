import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../providers/items_provider.dart';
import '../providers/key_provider.dart';
import '../services/haptics.dart';
import '../widgets/app_text_field.dart';
import '../widgets/source_picker.dart';

/// Edits a password's website, username and location — never the password
/// itself (that goes through "Passwort ändern", which keeps a version).
class PasswordEditScreen extends ConsumerStatefulWidget {
  const PasswordEditScreen(this.password, {super.key});
  final Item password;

  @override
  ConsumerState<PasswordEditScreen> createState() => _PasswordEditScreenState();
}

class _PasswordEditScreenState extends ConsumerState<PasswordEditScreen> {
  late final _website = TextEditingController(text: widget.password.website ?? '');
  late final _username = TextEditingController(text: widget.password.username ?? '');
  late String? _vaultId = widget.password.vaultId;
  final _form = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void dispose() {
    _website.dispose();
    _username.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _website.text.trim() != (widget.password.website ?? '') ||
      _username.text.trim() != (widget.password.username ?? '') ||
      _vaultId != widget.password.vaultId;

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (!ref.read(hasKeyProvider)) return;
    setState(() => _saving = true);
    try {
      final updated = await ref.read(itemsProvider.notifier).updatePasswordMeta(
            widget.password,
            website: _website.text.trim(),
            username: _username.text.trim(),
            toVaultId: _vaultId,
          );
      if (!mounted) return;
      Haptics.success();
      Navigator.pop(context, updated);
    } catch (e) {
      Haptics.warning();
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Eintrag bearbeiten')),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SourcePicker(
                value: _vaultId,
                enabled: !_saving,
                onChanged: (v) => setState(() => _vaultId = v)),
            AppTextField(
              controller: _website,
              label: 'Website / Dienst',
              hint: 'z. B. amazon.de',
              prefixIcon: Icons.language,
              enabled: !_saving,
              onChanged: (_) => setState(() {}),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Bitte eine Website eingeben' : null,
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _username,
              label: 'Benutzername',
              hint: 'E-Mail oder Benutzername',
              prefixIcon: Icons.person_outline,
              enabled: !_saving,
              onChanged: (_) => setState(() {}),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Bitte einen Benutzernamen eingeben' : null,
            ),
            const SizedBox(height: 8),
            Text(
              'Das Passwort selbst änderst du über „Passwort ändern“ – so bleibt '
              'die alte Version nachschlagbar.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: !_dirty || _saving ? null : _save,
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _saving
                        ? const SizedBox(
                            height: 20, width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Speichern')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
