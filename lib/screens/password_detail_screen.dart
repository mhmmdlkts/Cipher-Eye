import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/history.dart';
import '../models/password.dart';
import '../providers/history_provider.dart';
import '../providers/key_provider.dart';
import '../providers/place_provider.dart';
import '../services/clipboard_service.dart';
import '../services/history_service.dart';
import '../services/password_service.dart';

class PasswordDetailScreen extends ConsumerStatefulWidget {
  const PasswordDetailScreen(this.password, {super.key});

  final Password password;

  @override
  ConsumerState<PasswordDetailScreen> createState() =>
      _PasswordDetailScreenState();
}

class _PasswordDetailScreenState extends ConsumerState<PasswordDetailScreen> {
  bool _revealed = false;

  Password get pass => widget.password;

  void _warnNoKey() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(
          'Kein Encryption-Key gesetzt — bitte in den Einstellungen eintragen.'),
    ));
  }

  Future<void> _copy() async {
    if (!ref.read(hasKeyProvider)) {
      _warnNoKey();
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    await ClipboardService.copySensitive(pass.decrypted());
    messenger.showSnackBar(const SnackBar(
      content: Text('Kopiert – wird in 30 s aus der Zwischenablage gelöscht'),
      duration: Duration(seconds: 2),
    ));
    // Log this copy (with location) + count it, then refresh the history.
    PasswordService.incrementUsage(pass.id!, copy: true);
    HistoryService.saveCopyHistory(pass.id!).whenComplete(() {
      if (mounted) ref.invalidate(passwordHistoryProvider(pass.id!));
    });
  }

  void _toggleReveal() {
    if (!_revealed && !ref.read(hasKeyProvider)) {
      _warnNoKey();
      return;
    }
    final revealing = !_revealed;
    setState(() => _revealed = !_revealed);
    if (revealing) {
      PasswordService.incrementUsage(pass.id!, copy: false);
      HistoryService.saveViewHistory(pass.id!).whenComplete(() {
        if (mounted) ref.invalidate(passwordHistoryProvider(pass.id!));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final historyAsync = ref.watch(passwordHistoryProvider(pass.id!));
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(title: Text(pass.website ?? 'Passwort')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _headerCard(scheme),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('Verlauf', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 8),
              Icon(Icons.place_outlined,
                  size: 16, color: scheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 10),
          historyAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Verlauf konnte nicht geladen werden.'),
            ),
            data: (events) {
              final relevant = events
                  .where((h) =>
                      h.action == 'copy' ||
                      h.action == 'create' ||
                      h.action == 'view')
                  .toList();
              if (relevant.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Noch kein Verlauf')),
                );
              }
              return Column(children: relevant.map(_historyTile).toList());
            },
          ),
        ],
      ),
    );
  }

  Widget _headerCard(ColorScheme scheme) {
    final initial = (pass.website?.isNotEmpty ?? false)
        ? pass.website![0].toUpperCase()
        : '?';
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: scheme.primary,
                  child: Text(initial,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pass.website ?? '',
                          style: Theme.of(context).textTheme.titleLarge),
                      if ((pass.username ?? '').isNotEmpty)
                        Text(pass.username!,
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _revealed ? pass.decrypted() : List.filled(16, '•').join(),
                      style: const TextStyle(fontSize: 16, letterSpacing: 1.2),
                    ),
                  ),
                  IconButton(
                    tooltip: _revealed ? 'Verbergen' : 'Anzeigen',
                    icon: Icon(
                        _revealed ? Icons.visibility : Icons.visibility_off),
                    onPressed: _toggleReveal,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _copy,
                icon: const Icon(Icons.content_copy),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Passwort kopieren'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyTile(History h) {
    final scheme = Theme.of(context).colorScheme;
    final dt = h.timestamp?.toDate();
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primary.withValues(alpha: 0.15),
          child: Icon(_iconFor(h.action), color: scheme.primary, size: 20),
        ),
        title: Text(dt != null ? _formatTs(dt) : 'Unbekannt',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (h.location != null) _placeRow(h.location!),
            if (h.ip != null) _infoRow(Icons.lan_outlined, h.ip!),
            if (h.deviceInfo != null)
              _infoRow(Icons.devices_outlined, h.deviceInfo!),
          ],
        ),
        isThreeLine: h.location != null && (h.ip != null || h.deviceInfo != null),
      ),
    );
  }

  Widget _placeRow(String coords) {
    final placeAsync = ref.watch(placeProvider(coords));
    final text = placeAsync.maybeWhen(data: (s) => s, orElse: () => coords);
    return _infoRow(Icons.place_outlined, text);
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon,
              size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  IconData _iconFor(String? action) {
    switch (action) {
      case 'copy':
        return Icons.content_copy;
      case 'view':
        return Icons.visibility;
      case 'create':
        return Icons.add;
      case 'delete':
        return Icons.delete_outline;
      case 'key':
        return Icons.vpn_key;
      default:
        return Icons.history;
    }
  }

  String _formatTs(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year}, ${two(dt.hour)}:${two(dt.minute)}';
  }
}
