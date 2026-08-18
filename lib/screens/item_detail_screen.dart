import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../models/item_payload.dart';
import '../models/item_type.dart';
import '../providers/items_provider.dart';
import '../providers/key_provider.dart';
import '../services/clipboard_service.dart';
import '../services/haptics.dart';
import '../services/history_service.dart';
import '../services/item_service.dart';
import '../widgets/copy_row.dart';
import 'card_editor_screen.dart';
import 'note_editor_screen.dart';

/// Detail view for non-password items (cards, notes). Every sensitive field
/// is a [CopyRow]: tap copies, long-press / eye reveals.
class ItemDetailScreen extends ConsumerStatefulWidget {
  const ItemDetailScreen(this.item, {super.key});
  final Item item;

  @override
  ConsumerState<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<ItemDetailScreen> {
  final Set<String> _revealed = {};
  Item get item => widget.item;

  Future<void> _copy(String label, String value) async {
    if (!ref.read(hasKeyProvider)) return;
    Haptics.selection();
    await ClipboardService.copySensitive(value);
    HistoryService.saveCopyHistory(item.id!, vaultId: item.vaultId);
    ItemService.incrementUsage(item.id!, copy: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text('$label kopiert – wird in 30 s aus der Zwischenablage gelöscht'),
      duration: const Duration(seconds: 2),
    ));
  }

  void _toggle(String key) {
    Haptics.selection();
    final revealing = !_revealed.contains(key);
    setState(() => revealing ? _revealed.add(key) : _revealed.remove(key));
    if (revealing) {
      HistoryService.saveViewHistory(item.id!, vaultId: item.vaultId);
      ItemService.incrementUsage(item.id!, copy: false);
    }
  }

  Widget _secret(String key, String label, String? value, {bool mono = true}) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    final shown = _revealed.contains(key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CopyRow(
        label: label,
        value: shown
            ? value
            : List.filled(value.length.clamp(4, 16), '•').join(),
        mono: mono,
        onTap: () => _copy(label, value),
        onLongPress: () => _toggle(key),
        trailing: IconButton(
          tooltip: shown ? 'Verbergen' : 'Anzeigen',
          icon: Icon(shown ? Icons.visibility : Icons.visibility_off),
          onPressed: () => _toggle(key),
        ),
      ),
    );
  }

  Widget _plain(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CopyRow(
          label: label, value: value, onTap: () => _copy(label, value)),
    );
  }

  Future<void> _edit() async {
    if (!ref.read(hasKeyProvider)) return;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => item.type == ItemType.card
                ? CardEditorScreen(existing: item)
                : NoteEditorScreen(existing: item)));
    if (mounted) setState(() {});
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${item.type.label} löschen'),
        content: Text('„${item.title ?? ''}“ wirklich löschen?'),
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
    if (ok != true || !mounted) return;
    Haptics.warning();
    await ref.read(itemsProvider.notifier).delete(item);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String? plain;
    try {
      plain = ref.watch(hasKeyProvider) ? item.decrypted() : null;
    } catch (_) {
      plain = null;
    }
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(item.title ?? item.type.label),
        actions: [
          IconButton(
              tooltip: 'Bearbeiten',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit),
          IconButton(
              tooltip: 'Löschen',
              icon: Icon(Icons.delete_outline, color: scheme.error),
              onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: scheme.primary,
                child: Icon(item.type.icon, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(item.title ?? '',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (plain == null)
            const Text(
                'Kein Encryption-Key gesetzt — Inhalte können nicht angezeigt werden.')
          else if (item.type == ItemType.card)
            ..._cardBody(CardData.decode(plain))
          else if (item.type == ItemType.note)
            ..._noteBody(NoteData.decode(plain)),
          const SizedBox(height: 8),
          Text('Antippen zum Kopieren · lange drücken zum Anzeigen',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  List<Widget> _cardBody(CardData c) => [
        _secret('number', 'Kartennummer', c.number),
        _plain('Karteninhaber', c.holder),
        _plain('Gültig bis', c.expiry),
        _secret('cvv', 'CVV', c.cvv),
        _secret('pin', 'PIN', c.pin),
        _plain('IBAN', c.iban),
        _plain('Bank', c.bank),
        _plain('Notiz', c.note),
      ];

  List<Widget> _noteBody(NoteData n) => [
        _secret('text', 'Notiz', n.text, mono: false),
      ];
}
