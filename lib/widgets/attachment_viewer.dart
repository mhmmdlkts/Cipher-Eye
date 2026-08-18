import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../models/attachment.dart';
import '../models/item.dart';
import '../services/attachment_service.dart';

/// Swipeable pages of an item: images with pinch-zoom, PDFs rendered inline,
/// other files as a placeholder. Bytes are fetched (and decrypted) lazily.
class AttachmentViewer extends StatefulWidget {
  const AttachmentViewer(this.item, {super.key, this.height = 360});
  final Item item;
  final double height;

  @override
  State<AttachmentViewer> createState() => _AttachmentViewerState();
}

class _AttachmentViewerState extends State<AttachmentViewer> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.item.pages;
    if (pages.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: widget.height,
            color: Colors.black,
            child: PageView.builder(
              controller: _controller,
              itemCount: pages.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => _Page(item: widget.item, att: pages[i]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (pages.length > 1)
              for (var i = 0; i < pages.length; i++)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _index
                        ? scheme.primary
                        : scheme.onSurfaceVariant.withValues(alpha: 0.3),
                  ),
                ),
            const SizedBox(width: 10),
            Text(
              pages[_index].label.isEmpty
                  ? 'Seite ${_index + 1} von ${pages.length}'
                  : '${pages[_index].label} · ${_index + 1}/${pages.length}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}

class _Page extends StatefulWidget {
  const _Page({required this.item, required this.att});
  final Item item;
  final Attachment att;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> with AutomaticKeepAliveClientMixin {
  late final Future<Uint8List> _bytes =
      AttachmentService.instance.download(widget.item, widget.att);
  PdfControllerPinch? _pdf;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _pdf?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (ctx, snap) {
        if (snap.hasError) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image_outlined, color: Colors.white54, size: 40),
                SizedBox(height: 8),
                Text('Konnte nicht geladen werden',
                    style: TextStyle(color: Colors.white70)),
              ],
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        final bytes = snap.data!;
        switch (widget.att.kind) {
          case AttachmentKind.image:
            return InteractiveViewer(
              minScale: 1,
              maxScale: 6,
              child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
            );
          case AttachmentKind.pdf:
            _pdf ??= PdfControllerPinch(document: PdfDocument.openData(bytes));
            return PdfViewPinch(controller: _pdf!);
          case AttachmentKind.file:
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.insert_drive_file_outlined,
                      color: Colors.white70, size: 48),
                  const SizedBox(height: 8),
                  Text(widget.att.label,
                      style: const TextStyle(color: Colors.white)),
                  Text('${(bytes.length / 1024).round()} KB',
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            );
        }
      },
    );
  }
}
