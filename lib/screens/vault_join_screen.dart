import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../providers/key_provider.dart';
import '../providers/vaults_provider.dart';
import '../services/haptics.dart';
import '../services/invite_code.dart';
import '../services/vault_service.dart';
import '../widgets/app_text_field.dart';

/// Join a vault by pasting an invite code or scanning its QR.
class VaultJoinScreen extends ConsumerStatefulWidget {
  const VaultJoinScreen({super.key});

  @override
  ConsumerState<VaultJoinScreen> createState() => _VaultJoinScreenState();
}

class _VaultJoinScreenState extends ConsumerState<VaultJoinScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  bool _handled = false;

  bool get _canScan =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join(String raw) async {
    if (_busy) return;
    if (!ref.read(hasKeyProvider)) {
      _snack('Kein Encryption-Key gesetzt — bitte zuerst in den Einstellungen eintragen.');
      return;
    }
    final code = InviteCode.parse(raw);
    if (code == null) {
      _snack('Ungültiger Einladungscode');
      _handled = false;
      return;
    }
    setState(() => _busy = true);
    try {
      final vault = await ref.read(vaultsProvider.notifier).join(code);
      if (!mounted) return;
      Haptics.success();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tresor „${vault.name}“ beigetreten')));
    } on InviteError catch (e) {
      Haptics.warning();
      _snack(e.message);
      _handled = false;
    } catch (_) {
      Haptics.warning();
      _snack('Beitritt fehlgeschlagen – bitte erneut versuchen.');
      _handled = false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(title: const Text('Tresor beitreten')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_canScan) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 260,
                child: MobileScanner(
                  onDetect: (capture) {
                    if (_handled) return;
                    final raw = capture.barcodes
                        .map((b) => b.rawValue)
                        .whereType<String>()
                        .firstOrNull;
                    if (raw == null) return;
                    _handled = true;
                    _join(raw);
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('QR-Code der Einladung scannen – oder Code unten einfügen.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 24),
          ],
          AppTextField(
            controller: _code,
            label: 'Einladungscode',
            hint: 'ce1.…',
            prefixIcon: Icons.vpn_key_outlined,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _busy || _code.text.trim().isEmpty
                  ? null
                  : () => _join(_code.text),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.login),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Beitreten'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
