import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/attachment.dart';
import '../models/item.dart';
import '../models/item_payload.dart';
import '../models/item_type.dart';
import '../providers/items_provider.dart';
import '../providers/key_provider.dart';
import '../services/attachment_service.dart';
import '../services/document_capture.dart';
import '../services/haptics.dart';
import '../services/item_service.dart';
import '../widgets/app_text_field.dart';
import '../widgets/source_picker.dart';

/// Create/edit a generic encrypted file entry (PDF, anything ≤ 20 MB).
class FileEditorScreen extends ConsumerStatefulWidget {
  const FileEditorScreen({super.key, this.existing});
  final Item? existing;

  @override
  ConsumerState<FileEditorScreen> createState() => _FileEditorScreenState();
}

class _FileEditorScreenState extends ConsumerState<FileEditorScreen> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  String? _vaultId;
  PickedFile? _picked;
  bool _saving = false;

  Attachment? get _current => widget.existing?.attachments.firstOrNull;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _vaultId = e.vaultId;
      _title.text = e.title ?? '';
      try {
        _note.text = FileData.decode(e.decrypted()).note ?? '';
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final f = await DocumentCapture.pickFile();
      if (f == null || !mounted) return;
      setState(() {
        _picked = f;
        if (_title.text.trim().isEmpty) _title.text = f.name;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || !ref.read(hasKeyProvider)) return;
    if (widget.existing == null && _picked == null) return;
    setState(() => _saving = true);
    final notifier = ref.read(itemsProvider.notifier);
    final data = FileData(note: _note.text.trim());
    try {
      Item item;
      final existing = widget.existing;
      if (existing != null) {
        existing.setPayload(title: _title.text.trim(), plainJson: data.encode());
        item = await notifier.saveAndPlace(existing, _vaultId);
      } else {
        item = Item.payload(
          col: ItemService.repoFor(_vaultId).col,
          vaultId: _vaultId,
          type: ItemType.file,
          title: _title.text.trim(),
          plainJson: data.encode(),
        );
        await notifier.add(item);
      }
      final picked = _picked;
      if (picked != null) {
        final svc = AttachmentService.instance;
        for (final old in List.of(item.attachments)) {
          await svc.delete(item, old);
        }
        final kind = picked.mime == 'application/pdf'
            ? AttachmentKind.pdf
            : picked.mime.startsWith('image/')
                ? AttachmentKind.image
                : AttachmentKind.file;
        final att = await svc.upload(item,
            plain: picked.bytes,
            kind: kind,
            label: picked.name,
            mime: picked.mime,
            order: 0);
        item.attachments = [att];
        await notifier.save(item);
      }
      if (!mounted) return;
      Haptics.success();
      Navigator.pop(context, item);
    } catch (e) {
      Haptics.warning();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(0)} KB'
      : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shownName = _picked?.name ?? _current?.label;
    final shownSize = _picked?.bytes.length ?? _current?.bytes;
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.existing == null ? 'Neue Datei' : 'Datei bearbeiten')),
      backgroundColor: scheme.surface,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SourcePicker(
              value: _vaultId,
              enabled: !_saving,
              onChanged: (v) => setState(() => _vaultId = v)),
          Card(
            elevation: 0,
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              leading: Icon(Icons.insert_drive_file_outlined, color: scheme.primary),
              title: Text(shownName ?? 'Keine Datei gewählt'),
              subtitle: Text(shownSize != null ? _size(shownSize) : 'PDF oder beliebige Datei, max. 20 MB'),
              trailing: TextButton(
                  onPressed: _saving ? null : _pick,
                  child: Text(shownName == null ? 'Wählen' : 'Ersetzen')),
            ),
          ),
          const SizedBox(height: 12),
          AppTextField(
              controller: _title,
              label: 'Titel',
              hint: 'z. B. Mietvertrag',
              prefixIcon: Icons.title,
              onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          AppTextField(
              controller: _note,
              label: 'Notiz',
              hint: 'optional',
              prefixIcon: Icons.notes,
              maxLines: 3),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _title.text.trim().isEmpty ||
                      _saving ||
                      (widget.existing == null && _picked == null)
                  ? null
                  : _save,
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Speichern')),
            ),
          ),
        ],
      ),
    );
  }
}
