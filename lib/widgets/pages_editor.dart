import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/attachment.dart';
import '../models/item.dart';
import '../services/attachment_service.dart';
import '../services/document_capture.dart';
import '../services/haptics.dart';
import '../services/image_pipeline.dart';
import 'page_strip.dart';
import 'text_prompt_dialog.dart';

/// Page management shared by every editor that carries image pages
/// (documents, cards): keeps the working list, drives capture/crop/rotate,
/// and commits the result (uploads, deletions, order) to an item.
class PagesEditorController extends ChangeNotifier {
  PagesEditorController({List<String> defaultLabels = const ['Vorderseite', 'Rückseite']})
      : _defaultLabels = defaultLabels;

  final List<String> _defaultLabels;
  final List<PageEntry> pages = [];
  final List<Attachment> _removed = [];
  Item? _source;

  /// Progress text while committing, null otherwise.
  String? progress;

  bool get isEmpty => pages.isEmpty;

  /// Loads the pages of an existing item (thumbnails arrive asynchronously).
  Future<void> loadFrom(Item item) async {
    _source = item;
    pages.clear();
    for (final a in item.pages.where((a) => a.kind == AttachmentKind.image)) {
      pages.add(PageEntry(
          attachmentId: a.id, label: a.label, width: a.width, height: a.height));
    }
    notifyListeners();
    for (final p in List.of(pages)) {
      final att = item.attachments.where((a) => a.id == p.attachmentId).firstOrNull;
      if (att == null) continue;
      try {
        p.bytes = await AttachmentService.instance.download(item, att);
      } catch (_) {
        p.loadFailed = true;
      }
      notifyListeners();
    }
  }

  String _nextLabel() {
    final n = pages.length;
    return n < _defaultLabels.length ? _defaultLabels[n] : 'Seite ${n + 1}';
  }

  Future<void> addPage(BuildContext context) async {
    final canScan = await DocumentCapture.scannerAvailable();
    if (!context.mounted) return;
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
    if (choice == null || !context.mounted) return;
    try {
      if (choice == 'scan') {
        for (final p in await DocumentCapture.scan()) {
          pages.add(PageEntry(
              bytes: p.jpeg, label: _nextLabel(), width: p.width, height: p.height)
            ..dirty = true);
        }
      } else {
        final p = await DocumentCapture.pickImage(context, camera: choice == 'camera');
        if (p == null) return;
        pages.add(PageEntry(
            bytes: p.jpeg, label: _nextLabel(), width: p.width, height: p.height)
          ..dirty = true);
      }
      Haptics.selection();
      notifyListeners();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Aufnahme fehlgeschlagen: $e')));
      }
    }
  }

  Future<void> recrop(BuildContext context, int i) async {
    final p = pages[i];
    if (p.bytes == null) return;
    final res = await DocumentCapture.recrop(context, p.bytes!);
    if (res == null) return;
    p.bytes = res.jpeg;
    p.width = res.width;
    p.height = res.height;
    p.dirty = true;
    notifyListeners();
  }

  Future<void> rotate(int i) async {
    final p = pages[i];
    if (p.bytes == null) return;
    p.bytes = await ImagePipeline.rotate(p.bytes!, 1);
    final w = p.width;
    p.width = p.height;
    p.height = w;
    p.dirty = true;
    notifyListeners();
  }

  Future<void> relabel(BuildContext context, int i) async {
    final label = await showTextPrompt(context,
        title: 'Beschriftung', label: 'Beschriftung', initial: pages[i].label);
    if (label == null) return;
    pages[i].label = label.trim();
    notifyListeners();
  }

  void remove(int i) {
    final p = pages.removeAt(i);
    if (p.attachmentId != null) {
      final att = _source?.attachments.where((a) => a.id == p.attachmentId).firstOrNull;
      if (att != null) _removed.add(att);
    }
    notifyListeners();
  }

  void reorder(int oldIndex, int newIndex) {
    pages.insert(newIndex, pages.removeAt(oldIndex));
    notifyListeners();
  }

  /// After a move re-created the item (new attachment ids), remap entries by
  /// position so the commit updates the right attachments.
  void remapAfterMove(Item oldItem, Item newItem) {
    final oldPages = oldItem.pages;
    final newPages = newItem.pages;
    for (final p in pages) {
      final idx = oldPages.indexWhere((a) => a.id == p.attachmentId);
      if (idx >= 0 && idx < newPages.length) p.attachmentId = newPages[idx].id;
    }
    _removed.clear();
    _source = newItem;
  }

  /// Uploads dirty pages, deletes removed/replaced ones and writes the final
  /// ordered list into [item.attachments] (non-image attachments are kept).
  Future<void> commit(Item item) async {
    final svc = AttachmentService.instance;
    final result = <Attachment>[];
    var n = 0;
    for (final p in pages) {
      n++;
      Attachment? att =
          item.attachments.where((a) => a.id == p.attachmentId).firstOrNull;
      if (p.dirty && p.bytes != null) {
        progress = 'Seite $n von ${pages.length} wird hochgeladen …';
        notifyListeners();
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
    _removed.clear();
    final others = item.attachments
        .where((a) => a.kind != AttachmentKind.image)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    for (final o in others) {
      o.order = result.length;
      result.add(o);
    }
    item.attachments = result;
    progress = null;
    notifyListeners();
  }
}

/// The strip widget bound to a [PagesEditorController].
class PagesEditor extends StatelessWidget {
  const PagesEditor({super.key, required this.controller, this.enabled = true});
  final PagesEditorController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (ctx, _) => PageStrip(
        pages: controller.pages,
        enabled: enabled,
        thumbnail: (p) => _thumb(ctx, p),
        onAdd: () => controller.addPage(ctx),
        onRecrop: (i) => controller.recrop(ctx, i),
        onRotate: controller.rotate,
        onRelabel: (i) => controller.relabel(ctx, i),
        onRemove: controller.remove,
        onReorder: controller.reorder,
      ),
    );
  }

  Widget _thumb(BuildContext context, PageEntry p) {
    final Uint8List? b = p.bytes;
    if (b != null) {
      return Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true);
    }
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
          p.loadFailed ? Icons.broken_image_outlined : Icons.hourglass_empty,
          size: 20),
    );
  }
}
