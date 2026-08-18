import 'dart:typed_data';

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
import '../services/image_pipeline.dart';
import '../services/item_service.dart';
import '../widgets/app_text_field.dart';
import '../widgets/page_strip.dart';
import '../widgets/source_picker.dart';

/// Create/edit a document (ID, passport, licence, …): encrypted fields plus
/// an ordered set of encrypted image pages.
class DocumentEditorScreen extends ConsumerStatefulWidget {
  const DocumentEditorScreen({super.key, this.existing, this.docType});
  final Item? existing;

  /// Preselected template for a new document.
  final DocType? docType;

  @override
  ConsumerState<DocumentEditorScreen> createState() =>
      _DocumentEditorScreenState();
}

class _DocumentEditorScreenState extends ConsumerState<DocumentEditorScreen> {
  final _title = TextEditingController();
  final _number = TextEditingController();
  final _issued = TextEditingController();
  final _expires = TextEditingController();
  final _note = TextEditingController();
  DocType _docType = DocType.other;
  String? _vaultId;
  final List<PageEntry> _pages = [];
  final List<Attachment> _removed = [];
  bool _saving = false;
  String? _progress;

  static const _defaultLabels = ['Vorderseite', 'Rückseite'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _vaultId = e.vaultId;
      _title.text = e.title ?? '';
      try {
        final d = DocumentData.decode(e.decrypted());
        _docType = d.docType;
        _number.text = d.number ?? '';
        _issued.text = d.issued ?? '';
        _expires.text = d.expires ?? '';
        _note.text = d.note ?? '';
      } catch (_) {}
      for (final a in e.pages) {
        _pages.add(PageEntry(
            attachmentId: a.id, label: a.label, width: a.width, height: a.height));
      }
      _loadExisting();
    } else {
      _docType = widget.docType ?? DocType.other;
      _title.text = _docType == DocType.other ? '' : _docType.label;
    }
  }

  Future<void> _loadExisting() async {
    final e = widget.existing!;
    for (final p in _pages) {
      final att = e.attachments.where((a) => a.id == p.attachmentId).firstOrNull;
      if (att == null) continue;
      try {
        final bytes = await AttachmentService.instance.download(e, att);
        if (!mounted) return;
        setState(() => p.bytes = bytes);
      } catch (_) {
        if (mounted) setState(() => p.loadFailed = true);
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _number, _issued, _expires, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  String _nextLabel() {
    final n = _pages.length;
    return n < _defaultLabels.length ? _defaultLabels[n] : 'Seite ${n + 1}';
  }

  Future<void> _addPage() async {
    final canScan = await DocumentCapture.scannerAvailable();
    if (!mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canScan)
              ListTile(
                leading: const Icon(Icons.document_scanner_outlined),
                title: const Text('Scannen'),
                subtitle: const Text('Automatischer Zuschnitt, mehrere Seiten'),
                onTap: () => Navigator.pop(ctx, 'scan'),
              ),
            if (DocumentCapture.isMobile)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Foto aufnehmen'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Aus Galerie / Datei'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      if (choice == 'scan') {
        final pages = await DocumentCapture.scan();
        setState(() {
          for (final p in pages) {
            _pages.add(PageEntry(
                bytes: p.jpeg, label: _nextLabel(), width: p.width, height: p.height)
              ..dirty = true);
          }
        });
      } else {
        final p = await DocumentCapture.pickImage(context, camera: choice == 'camera');
        if (p == null || !mounted) return;
        setState(() => _pages.add(PageEntry(
            bytes: p.jpeg, label: _nextLabel(), width: p.width, height: p.height)
          ..dirty = true));
      }
      Haptics.selection();
    } catch (e) {
      _snack('Aufnahme fehlgeschlagen: $e');
    }
  }

  Future<void> _recrop(int i) async {
    final p = _pages[i];
    if (p.bytes == null) return;
    final res = await DocumentCapture.recrop(context, p.bytes!);
    if (res == null || !mounted) return;
    setState(() {
      p.bytes = res.jpeg;
      p.width = res.width;
      p.height = res.height;
      p.dirty = true;
    });
  }

  Future<void> _rotate(int i) async {
    final p = _pages[i];
    if (p.bytes == null) return;
    final rotated = await ImagePipeline.rotate(p.bytes!, 1);
    if (!mounted) return;
    setState(() {
      p.bytes = rotated;
      final w = p.width;
      p.width = p.height;
      p.height = w;
      p.dirty = true;
    });
  }

  Future<void> _relabel(int i) async {
    final controller = TextEditingController(text: _pages[i].label);
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Beschriftung'),
        content: AppTextField(
            controller: controller,
            label: 'Beschriftung',
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('OK')),
        ],
      ),
    );
    controller.dispose();
    if (label == null) return;
    setState(() => _pages[i].label = label.trim());
  }

  void _remove(int i) {
    final p = _pages.removeAt(i);
    if (p.attachmentId != null) {
      final att = widget.existing?.attachments
          .where((a) => a.id == p.attachmentId)
          .firstOrNull;
      if (att != null) _removed.add(att);
    }
    setState(() {});
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || !ref.read(hasKeyProvider)) return;
    setState(() => _saving = true);
    final notifier = ref.read(itemsProvider.notifier);
    final data = DocumentData(
      docType: _docType,
      number: _number.text.trim(),
      issued: _issued.text.trim(),
      expires: _expires.text.trim(),
      note: _note.text.trim(),
    );
    try {
      Item item;
      final existing = widget.existing;
      if (existing != null) {
        existing.setPayload(title: _title.text.trim(), plainJson: data.encode());
        await notifier.save(existing);
        item = existing;
        if (_vaultId != existing.vaultId) {
          item = await notifier.move(existing, _vaultId);
          // Attachment ids were re-created by the move → remap page entries.
          final oldPages = existing.pages;
          final newPages = item.pages;
          for (final p in _pages) {
            final idx = oldPages.indexWhere((a) => a.id == p.attachmentId);
            if (idx >= 0 && idx < newPages.length) {
              p.attachmentId = newPages[idx].id;
            }
          }
          _removed.clear();
        }
      } else {
        item = Item.payload(
          col: ItemService.repoFor(_vaultId).col,
          vaultId: _vaultId,
          type: ItemType.document,
          title: _title.text.trim(),
          plainJson: data.encode(),
        );
        await notifier.add(item);
      }

      // Pages: upload dirty ones, delete removed/replaced ones, keep order.
      final svc = AttachmentService.instance;
      final result = <Attachment>[];
      var n = 0;
      for (final p in _pages) {
        n++;
        Attachment? att = item.attachments
            .where((a) => a.id == p.attachmentId)
            .firstOrNull;
        if (p.dirty && p.bytes != null) {
          setState(() => _progress = 'Seite $n von ${_pages.length} wird hochgeladen …');
          final uploaded = await svc.upload(item,
              plain: p.bytes!,
              kind: AttachmentKind.image,
              label: p.label,
              mime: 'image/jpeg',
              order: result.length,
              width: p.width,
              height: p.height);
          if (att != null) await svc.delete(item, att);
          att = uploaded;
          p.attachmentId = uploaded.id;
          p.dirty = false;
        }
        if (att != null) {
          att.label = p.label;
          att.order = result.length;
          result.add(att);
        }
      }
      for (final r in _removed) {
        await svc.delete(item, r);
      }
      item.attachments = result;
      await notifier.save(item);
      if (!mounted) return;
      Haptics.success();
      Navigator.pop(context);
    } catch (e) {
      Haptics.warning();
      _snack('Speichern fehlgeschlagen: $e');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _progress = null;
        });
      }
    }
  }

  Widget _thumb(PageEntry p) {
    final Uint8List? b = p.bytes;
    if (b != null) return Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true);
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(p.loadFailed ? Icons.broken_image_outlined : Icons.hourglass_empty,
          size: 20),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.existing == null
              ? 'Neues Dokument'
              : 'Dokument bearbeiten')),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SourcePicker(
              value: _vaultId,
              enabled: !_saving,
              onChanged: (v) => setState(() => _vaultId = v)),
          DropdownButtonFormField<DocType>(
            initialValue: _docType,
            decoration: const InputDecoration(
                labelText: 'Art', prefixIcon: Icon(Icons.badge_outlined)),
            items: [
              for (final t in DocType.values)
                DropdownMenuItem(value: t, child: Text(t.label)),
            ],
            onChanged: _saving
                ? null
                : (t) => setState(() {
                      if (t == null) return;
                      final wasDefault =
                          _title.text.trim().isEmpty || _title.text == _docType.label;
                      _docType = t;
                      if (wasDefault && t != DocType.other) _title.text = t.label;
                    }),
          ),
          const SizedBox(height: 12),
          AppTextField(
              controller: _title,
              label: 'Titel',
              hint: 'z. B. Reisepass Oma',
              prefixIcon: Icons.title,
              onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          AppTextField(
              controller: _number,
              label: 'Nummer',
              hint: 'optional',
              prefixIcon: Icons.numbers),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: AppTextField(
                    controller: _issued,
                    label: 'Ausgestellt',
                    hint: 'TT.MM.JJJJ',
                    prefixIcon: Icons.event_available_outlined)),
            const SizedBox(width: 12),
            Expanded(
                child: AppTextField(
                    controller: _expires,
                    label: 'Gültig bis',
                    hint: 'TT.MM.JJJJ',
                    prefixIcon: Icons.event_busy_outlined)),
          ]),
          const SizedBox(height: 12),
          AppTextField(
              controller: _note,
              label: 'Notiz',
              hint: 'optional',
              prefixIcon: Icons.notes,
              maxLines: 3),
          const SizedBox(height: 20),
          PageStrip(
            pages: _pages,
            enabled: !_saving,
            thumbnail: _thumb,
            onAdd: _addPage,
            onRecrop: _recrop,
            onRotate: _rotate,
            onRelabel: _relabel,
            onRemove: _remove,
            onReorder: (o, n) => setState(() {
              _pages.insert(n, _pages.removeAt(o));
            }),
          ),
          const SizedBox(height: 24),
          if (_progress != null) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 6),
            Text(_progress!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _title.text.trim().isEmpty || _saving ? null : _save,
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
