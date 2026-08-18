import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../models/item_payload.dart';
import '../models/item_type.dart';
import '../providers/items_provider.dart';
import '../providers/key_provider.dart';
import '../models/attachment.dart';
import '../services/clipboard_service.dart';
import '../services/export_service.dart';
import '../services/haptics.dart';
import '../services/history_service.dart';
import '../services/item_service.dart';
import '../widgets/attachment_viewer.dart';
import '../widgets/copy_row.dart';
import 'card_editor_screen.dart';
import 'document_editor_screen.dart';
import 'file_editor_screen.dart';
import 'note_editor_screen.dart';

/// Detail view for non-password items (cards, notes, documents, files).
/// Every sensitive field is a [CopyRow]: tap copies, long-press / eye reveals.
class ItemDetailScreen extends ConsumerStatefulWidget {
  const ItemDetailScreen(this.item, {super.key});
  final Item item;

  @override
  ConsumerState<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<ItemDetailScreen> {
  final Set<String> _revealed = {};
  late Item _item = widget.item;
  Item get item => _item;

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
    final Widget editor = switch (item.type) {
      ItemType.card => CardEditorScreen(existing: item),
      ItemType.note => NoteEditorScreen(existing: item),
      ItemType.document => DocumentEditorScreen(existing: item),
      ItemType.file => FileEditorScreen(existing: item),
      ItemType.password => NoteEditorScreen(existing: item),
    };
    final updated = await Navigator.push<Item>(
        context, MaterialPageRoute(builder: (_) => editor));
    if (!mounted) return;
    setState(() {
      // A move re-creates the item; keep showing the live one.
      if (updated != null) _item = updated;
    });
  }

  bool _exporting = false;

  Future<void> _export() async {
    final images = ExportService.imagePages(item);
    final others = item.pages.where((a) => a.kind != AttachmentKind.image).toList();
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Teilen / Exportieren',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            if (images.isNotEmpty) ...[
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('PDF'),
                subtitle: Text('${images.length} Seite${images.length == 1 ? '' : 'n'} in einer Datei, verkleinert'),
                onTap: () => Navigator.pop(ctx, 'pdf'),
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('JPEG'),
                subtitle: Text(images.length == 1
                    ? 'Eine Bilddatei, verkleinert'
                    : '${images.length} Bilddateien, verkleinert'),
                onTap: () => Navigator.pop(ctx, 'jpeg'),
              ),
            ],
            for (final a in others)
              ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(a.label.isEmpty ? 'Datei' : a.label),
                subtitle: Text('Original · ${ExportService.humanSize(a.bytes)}'),
                onTap: () => Navigator.pop(ctx, 'raw:${a.id}'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      List<ExportFile> files;
      if (choice == 'pdf') {
        files = [await ExportService.pdfFor(item)];
      } else if (choice == 'jpeg') {
        files = await ExportService.jpegsFor(item);
      } else {
        final att = item.attachments.firstWhere((a) => a.id == choice.substring(4));
        files = [await ExportService.rawFor(item, att)];
      }
      HistoryService.saveExportHistory(item.id!, vaultId: item.vaultId);
      Haptics.selection();
      await ExportService.shareFiles(files, subject: item.title);
    } catch (e) {
      Haptics.warning();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export fehlgeschlagen: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
          if (item.hasAttachments)
            IconButton(
                tooltip: 'Teilen / Exportieren',
                icon: _exporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.ios_share),
                onPressed: _exporting ? null : _export),
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
          if (item.vaultId != null)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Icon(Icons.group_outlined, color: scheme.primary),
              title: Text(
                  'Geteilt in „${ItemService.vaultById(item.vaultId)?.name ?? 'Tresor'}“'),
              subtitle: Text(
                  '${ItemService.vaultById(item.vaultId)?.memberCount ?? 0} Mitglieder'),
            ),
          const SizedBox(height: 20),
          if (plain != null && item.hasAttachments) ...[
            AttachmentViewer(item),
            const SizedBox(height: 20),
          ],
          if (plain == null)
            const Text(
                'Kein Encryption-Key gesetzt — Inhalte können nicht angezeigt werden.')
          else if (item.type == ItemType.card)
            ..._cardBody(CardData.decode(plain))
          else if (item.type == ItemType.note)
            ..._noteBody(NoteData.decode(plain))
          else if (item.type == ItemType.document)
            ..._documentBody(DocumentData.decode(plain))
          else if (item.type == ItemType.file)
            ..._fileBody(FileData.decode(plain)),
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

  List<Widget> _documentBody(DocumentData d) => [
        _plain('Art', d.docType.label),
        _secret('number', 'Nummer', d.number),
        _plain('Ausgestellt', d.issued),
        _plain('Gültig bis', d.expires),
        _plain('Notiz', d.note),
      ];

  List<Widget> _fileBody(FileData f) => [
        _plain('Notiz', f.note),
      ];
}
