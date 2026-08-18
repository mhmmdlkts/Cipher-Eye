import 'dart:async';

import 'package:cipher_eye/models/item.dart';
import 'package:cipher_eye/models/password.dart';
import 'package:cipher_eye/services/firestore_paths_service.dart';
import 'package:cipher_eye/services/password_generator.dart';
import 'package:cipher_eye/services/person_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/passwords_provider.dart';
import '../services/clipboard_service.dart';
import '../services/haptics.dart';
import '../widgets/app_text_field.dart';

class AddNewPasswordScreen extends ConsumerStatefulWidget {
  const AddNewPasswordScreen({super.key, this.draft, this.editVersion});

  /// When set, this draft is being finished/edited instead of created anew.
  final Password? draft;

  /// When set, an existing real password is being edited; saving stores a new
  /// version of the same purpose (the old one is kept but no longer latest).
  final Password? editVersion;

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
  bool _saved = false;
  Password? _draft;
  Timer? _clearTimer;
  int _clearSeconds = 0;

  /// Editing an existing real password → save creates a new version.
  bool get _isEditVersion => widget.editVersion != null;

  @override
  void initState() {
    super.initState();
    final edit = widget.editVersion;
    final existing = widget.draft;
    if (edit != null) {
      // Edit an existing password: prefill, but don't create/persist a draft.
      _websiteController.text = edit.website ?? '';
      _usernameController.text = edit.username ?? '';
      try {
        _passwordController.text = edit.decrypted();
      } catch (_) {}
    } else if (existing != null) {
      _draft = existing;
      _websiteController.text = existing.website ?? '';
      _usernameController.text = existing.username ?? '';
      try {
        _passwordController.text = existing.decrypted();
      } catch (_) {}
    } else {
      _usernameController.text = usernames.isNotEmpty ? usernames.first : '';
      _generate(rebuild: false);
      final draft = Item.draft(
        col: FirestorePathsService.getPasswordCol(),
        username: _usernameController.text,
        plainText: _passwordController.text,
      );
      _draft = draft;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(passwordsProvider.notifier).addDraft(draft);
      });
    }
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    // Leaving an unfinished draft without saving → keep the work as a draft.
    final draft = _draft;
    if (!_saved && !_isEditVersion && draft != null) {
      try {
        draft.applyEdits(
          website: _websiteController.text,
          username: _usernameController.text,
          plainText: _passwordController.text,
        );
        draft.push();
      } catch (_) {}
    }
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
    _startClearCountdown();
    if (rebuild) setState(() {});
  }

  /// Counts down the seconds until the clipboard auto-wipes (kept in sync with
  /// [ClipboardService.clearAfter]); updates the on-screen hint live.
  void _startClearCountdown() {
    _clearTimer?.cancel();
    _clearSeconds = ClipboardService.clearAfter.inSeconds;
    _clearTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _clearSeconds--;
        if (_clearSeconds <= 0) {
          _copied = false;
          t.cancel();
        }
      });
    });
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

  Future<void> _deleteDraft() async {
    final draft = _draft;
    if (draft == null) return;
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Entwurf löschen'),
        content: const Text('Diesen Entwurf wirklich verwerfen?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    Haptics.warning();
    // Prevent dispose() from re-persisting the draft we just deleted.
    _saved = true;
    await ref.read(passwordsProvider.notifier).delete(draft);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(_isEditVersion
            ? 'Passwort bearbeiten'
            : widget.draft != null
                ? 'Entwurf bearbeiten'
                : 'Neues Passwort'),
        actions: [
          if (widget.draft != null)
            IconButton(
              tooltip: 'Entwurf löschen',
              icon: const Icon(Icons.delete_outline),
              onPressed: isLoading ? null : _deleteDraft,
            ),
        ],
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
                  if (!_isEditVersion) ...[
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      children:
                          List<Widget>.generate(usernames.length, (int index) {
                        return InputChip(
                          onPressed: isLoading
                              ? null
                              : () {
                                  setState(() {
                                    _usernameController.text = usernames[index];
                                  });
                                },
                          label: Text(usernames[index]),
                        );
                      }),
                    ),
                    const SizedBox(height: 16),
                  ],
                  AppTextField(
                    controller: _usernameController,
                    label: 'Benutzername',
                    hint: 'Benutzername eingeben',
                    prefixIcon: Icons.person_outline,
                    enabled: !isLoading && !_isEditVersion,
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
                    enabled: !isLoading && !_isEditVersion,
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
                      if (_copied) {
                        _clearTimer?.cancel();
                        setState(() => _copied = false);
                      }
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
                              'In die Zwischenablage kopiert '
                              '(wird in $_clearSeconds s geleert)',
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
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Sonderzeichen einschließen',
                            style: TextStyle(fontSize: 16)),
                      ),
                      Switch(
                        value: includeSpecialChars,
                        onChanged: isLoading
                            ? null
                            : (val) {
                                includeSpecialChars = val;
                                _generate();
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Passwortlänge',
                          style: TextStyle(fontSize: 16)),
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
                      if (_isEditVersion) {
                        // Editing a real password → store a new version of the
                        // same purpose; the old one is kept but no longer latest.
                        final newVersion = Item.password(
                          col: FirestorePathsService.getPasswordCol(),
                          website: _websiteController.text,
                          username: _usernameController.text,
                          plainText: _passwordController.text,
                        );
                        await ref
                            .read(passwordsProvider.notifier)
                            .update(newVersion);
                      } else {
                        final draft = _draft!;
                        draft.applyEdits(
                          website: _websiteController.text,
                          username: _usernameController.text,
                          plainText: _passwordController.text,
                          finalize: true,
                        );
                        await ref
                            .read(passwordsProvider.notifier)
                            .saveDraft(draft, finalize: true);
                      }
                      _saved = true;
                      Haptics.success();
                      messenger.showSnackBar(const SnackBar(
                        content: Text('Gespeichert'),
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
