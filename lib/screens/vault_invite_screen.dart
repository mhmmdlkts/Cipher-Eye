import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/vault.dart';
import '../services/haptics.dart';
import '../services/invite_code.dart';
import '../services/item_service.dart';

/// Shows a fresh single-use invite (QR + text) for a vault.
class VaultInviteScreen extends StatefulWidget {
  const VaultInviteScreen(this.vault, {super.key});
  final Vault vault;

  @override
  State<VaultInviteScreen> createState() => _VaultInviteScreenState();
}

class _VaultInviteScreenState extends State<VaultInviteScreen> {
  InviteCode? _code;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _code = null;
      _error = null;
    });
    try {
      final c = await ItemService.vaultService.createInvite(widget.vault);
      if (mounted) setState(() => _code = c);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Einladung konnte nicht erstellt werden.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final code = _code;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(title: Text('Einladen: ${widget.vault.name}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_error != null)
            Text(_error!, style: TextStyle(color: scheme.error))
          else if (code == null)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16)),
                child: QrImageView(data: code.encode(), size: 240),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(code.encode(),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: code.encode()));
                      Haptics.selection();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Code kopiert')));
                      }
                    },
                    icon: const Icon(Icons.content_copy),
                    label: const Text('Code kopieren'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _generate,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Neu'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Gültig 7 Tage, einmal verwendbar. Der Code enthält den '
            'Tresor-Schlüssel – nur persönlich weitergeben (z. B. QR direkt '
            'vom Bildschirm scannen lassen).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
