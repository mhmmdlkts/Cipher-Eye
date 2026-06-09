import 'package:cipher_eye/models/password.dart';
import 'package:cipher_eye/services/password_generator.dart';
import 'package:cipher_eye/services/person_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/passwords_provider.dart';
import '../services/clipboard_service.dart';
import '../widgets/app_text_field.dart';

class AddNewPasswordScreen extends ConsumerStatefulWidget {
  const AddNewPasswordScreen({super.key});

  @override
  ConsumerState<AddNewPasswordScreen> createState() =>
      _AddNewPasswordScreenState();
}

class _AddNewPasswordScreenState extends ConsumerState<AddNewPasswordScreen> {

  final TextEditingController _websiteController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  List<String> get usernames => PersonService.person.usernames;

  bool isLoading = false;
  bool includeSpecialChars = true;
  int passwordLength = 24;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _usernameController.text = usernames.isNotEmpty ? usernames.first : '';
    _generate(rebuild: false);
  }

  @override
  void dispose() {
    _websiteController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Generates a fresh password, fills the field, and copies it to the
  /// clipboard right away.
  void _generate({bool rebuild = true}) {
    final pw = PasswordGenerator.generatePassword(
      length: passwordLength,
      incSpecialChars: includeSpecialChars,
    );
    _passwordController.text = pw;
    ClipboardService.copySensitive(pw);
    _copied = true;
    if (rebuild) setState(() {});
  }

  void _setLength(int length) {
    passwordLength = length.clamp(8, 32);
    _generate();
  }

  Future<void> _editLength() async {
    final controller = TextEditingController(text: '$passwordLength');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Passwortlänge (8–32)'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen')),
          TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, int.tryParse(controller.text)),
              child: const Text('OK')),
        ],
      ),
    );
    if (result != null) _setLength(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Neues Passwort'),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: List<Widget>.generate(usernames.length, (int index) {
                      return InputChip(
                        onPressed: isLoading?null:() {
                          setState(() {
                            _usernameController.text = usernames[index];
                          });
                        },
                        label: Text(usernames[index]),
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _usernameController,
                    label: 'Benutzername',
                    hint: 'Benutzername eingeben',
                    prefixIcon: Icons.person_outline,
                    enabled: !isLoading,
                    validator: (value) => (value == null || value.isEmpty)
                        ? 'Bitte einen Benutzernamen eingeben'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _websiteController,
                    label: 'Website',
                    hint: 'Website eingeben',
                    prefixIcon: Icons.language,
                    enabled: !isLoading,
                    validator: (value) => (value == null || value.isEmpty)
                        ? 'Bitte eine Website eingeben'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _passwordController,
                    label: 'Passwort',
                    hint: 'Passwort eingeben',
                    prefixIcon: Icons.lock_outline,
                    enabled: !isLoading,
                    onChanged: (_) {
                      if (_copied) setState(() => _copied = false);
                    },
                    validator: (value) => (value == null || value.isEmpty)
                        ? 'Bitte ein Passwort eingeben'
                        : null,
                  ),
                  if (_copied)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle,
                              size: 14, color: Colors.green),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'In die Zwischenablage kopiert (wird in 30 s geleert)',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Sonderzeichen einschließen'),
                    value: includeSpecialChars,
                    onChanged: isLoading ? null : (val) {
                      includeSpecialChars = val;
                      _generate();
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Passwortlänge'),
                      const Spacer(),
                      IconButton.filledTonal(
                        onPressed: isLoading || passwordLength <= 8
                            ? null
                            : () => _setLength(passwordLength - 1),
                        icon: const Icon(Icons.remove),
                      ),
                      InkWell(
                        onTap: isLoading ? null : _editLength,
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 48,
                          height: 40,
                          child: Center(
                            child: Text('$passwordLength',
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: isLoading || passwordLength >= 32
                            ? null
                            : () => _setLength(passwordLength + 1),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: isLoading ? null : () => _generate(),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Neu generieren'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    if (!_formKey.currentState!.validate()) {
                      return;
                    }
                    setState(() => isLoading = true);
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(context);
                    try {
                      final password = Password.create(
                        website: _websiteController.text,
                        username: _usernameController.text,
                        plaintText: _passwordController.text,
                      );
                      await ref.read(passwordsProvider.notifier).add(password);
                      await ClipboardService.copySensitive(
                          _passwordController.text);
                      messenger.showSnackBar(const SnackBar(
                        content: Text(
                            'Gespeichert & kopiert (Zwischenablage wird in 30 s geleert)'),
                        duration: Duration(seconds: 2),
                      ));
                      navigator.pop();
                    } catch (e) {
                      if (mounted) {
                        setState(() => isLoading = false);
                      }
                      messenger.showSnackBar(const SnackBar(
                        content: Text(
                            'Speichern fehlgeschlagen. Ist dein Encryption-Key gesetzt?'),
                        backgroundColor: Colors.red,
                      ));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Speichern', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      )
    );
  }
}
