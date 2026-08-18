import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/history.dart';
import '../models/item.dart';
import 'add_new_password_screen.dart';
import 'log_detail_screen.dart';
import '../providers/history_provider.dart';
import '../providers/key_provider.dart';
import '../providers/items_provider.dart';
import '../providers/place_provider.dart';
import '../services/clipboard_service.dart';
import '../services/haptics.dart';
import '../services/history_service.dart';
import '../services/item_service.dart';
import '../widgets/copy_row.dart';

class PasswordDetailScreen extends ConsumerStatefulWidget {
  const PasswordDetailScreen(this.password, {super.key});

  final Item password;

  @override
  ConsumerState<PasswordDetailScreen> createState() =>
      _PasswordDetailScreenState();
}

class _PasswordDetailScreenState extends ConsumerState<PasswordDetailScreen> {
  bool _revealed = false;
  final Set<String> _revealedVersions = {};

  Item get pass => widget.password;

  Future<void> _edit() async {
    if (!ref.read(hasKeyProvider)) {
      _warnNoKey();
      return;
    }
    final navigator = Navigator.of(context);
    await navigator.push(MaterialPageRoute(
      builder: (_) => AddNewPasswordScreen(editVersion: pass),
    ));
    // pass is now an older version; return to the (refreshed) list.
    if (mounted) navigator.pop();
  }

  Future<void> _confirmDelete() async {
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Passwort löschen'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Dieses Passwort inkl. aller früheren Versionen wirklich löschen?'),
            const SizedBox(height: 10),
            Text(pass.website ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
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
    await ref.read(itemsProvider.notifier).delete(pass);
    navigator.pop();
  }

  void _warnNoKey() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(
          'Kein Encryption-Key gesetzt — bitte in den Einstellungen eintragen.'),
    ));
  }

  Future<void> _copyUsername() async {
    final name = pass.username ?? '';
    if (name.isEmpty) return;
    Haptics.selection();
    await ClipboardService.copySensitive(name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Benutzername kopiert'),
      duration: Duration(seconds: 2),
    ));
  }

  Future<void> _copy() async {
    if (!ref.read(hasKeyProvider)) {
      _warnNoKey();
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Haptics.selection();
    await ClipboardService.copySensitive(pass.decrypted());
    messenger.showSnackBar(const SnackBar(
      content: Text('Passwort kopiert – wird in 30 s aus der Zwischenablage gelöscht'),
      duration: Duration(seconds: 2),
    ));
    // Log this copy (with location) + count it, then refresh the history.
    ItemService.incrementUsage(pass.id!, copy: true);
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
    Haptics.selection();
    setState(() => _revealed = !_revealed);
    if (revealing) {
      ItemService.incrementUsage(pass.id!, copy: false);
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
      appBar: AppBar(
        title: Text(pass.website ?? 'Passwort'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: PopupMenuButton<String>(
              tooltip: 'Mehr',
              icon: const Icon(Icons.more_vert),
              position: PopupMenuPosition.under,
              offset: const Offset(0, 8),
              elevation: 3,
              color: scheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              onSelected: (v) {
                if (v == 'edit') _edit();
                if (v == 'delete') _confirmDelete();
              },
              itemBuilder: (_) => [
                _menuItem('edit', Icons.edit_outlined, 'Bearbeiten',
                    scheme.onSurface),
                const PopupMenuDivider(height: 4),
                _menuItem('delete', Icons.delete_outline, 'Löschen',
                    scheme.error),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _headerCard(scheme),
          const SizedBox(height: 24),
          _previousVersions(scheme),
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
                      h.action == 'view' ||
                      h.action == 'update')
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
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if ((pass.username ?? '').isNotEmpty) ...[
              CopyRow(
                label: 'Benutzername',
                value: pass.username!,
                onTap: _copyUsername,
              ),
              const SizedBox(height: 10),
            ],
            CopyRow(
              label: 'Passwort',
              value: _revealed ? pass.decrypted() : List.filled(16, '•').join(),
              mono: true,
              onTap: _copy,
              onLongPress: _toggleReveal,
              trailing: IconButton(
                tooltip: _revealed ? 'Verbergen' : 'Anzeigen',
                icon:
                    Icon(_revealed ? Icons.visibility : Icons.visibility_off),
                onPressed: _toggleReveal,
              ),
            ),
            const SizedBox(height: 8),
            Text('Antippen zum Kopieren',
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
      String value, IconData icon, String label, Color color) {
    return PopupMenuItem<String>(
      value: value,
      height: 48,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 14),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _previousVersions(ColorScheme scheme) {
    final older = ItemService.versionsOf(pass.purposeId ?? '')
        .where((p) => p.id != pass.id)
        .toList();
    if (older.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Frühere Versionen',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 8),
            Icon(Icons.history, size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
        const SizedBox(height: 10),
        ...older.map((p) => _versionTile(p, scheme)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _versionTile(Item p, ColorScheme scheme) {
    final shown = _revealedVersions.contains(p.id);
    final dt = p.timestamp?.toDate();
    String value;
    if (shown) {
      try {
        value = p.decrypted();
      } catch (_) {
        value = '— Key fehlt —';
      }
    } else {
      value = List.filled(12, '•').join();
    }
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Icon(Icons.lock_clock_outlined, color: scheme.primary),
        title: Text(value, style: const TextStyle(letterSpacing: 1.2)),
        subtitle: Text(dt != null ? _formatTs(dt) : 'Unbekannt'),
        trailing: IconButton(
          tooltip: shown ? 'Verbergen' : 'Anzeigen',
          icon: Icon(shown ? Icons.visibility : Icons.visibility_off, size: 20),
          onPressed: () {
            if (!shown && !ref.read(hasKeyProvider)) {
              _warnNoKey();
              return;
            }
            Haptics.selection();
            setState(() {
              if (shown) {
                _revealedVersions.remove(p.id);
              } else {
                _revealedVersions.add(p.id!);
              }
            });
          },
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
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => LogDetailScreen(h))),
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
      case 'update':
        return Icons.autorenew;
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
