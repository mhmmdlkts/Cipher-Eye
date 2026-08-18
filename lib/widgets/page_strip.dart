import 'dart:typed_data';

import 'package:flutter/material.dart';

/// One page in the editor: either an already uploaded attachment (bytes are
/// loaded lazily for the thumbnail) or a fresh capture waiting for upload.
class PageEntry {
  PageEntry({this.attachmentId, this.bytes, required this.label, this.width, this.height});

  /// Set when the page is already stored; null for new pages.
  String? attachmentId;

  /// Fresh (or re-cropped) JPEG bytes; null until loaded for existing pages.
  Uint8List? bytes;
  String label;
  int? width;
  int? height;

  /// True when [bytes] must be uploaded (new page or re-cropped existing one).
  bool dirty = false;
  bool loadFailed = false;
}

/// Reorderable list of pages with per-page actions and an "add" button.
class PageStrip extends StatelessWidget {
  const PageStrip({
    super.key,
    required this.pages,
    required this.onReorder,
    required this.onAdd,
    required this.onRecrop,
    required this.onRotate,
    required this.onRelabel,
    required this.onRemove,
    required this.thumbnail,
    this.enabled = true,
  });

  final List<PageEntry> pages;
  final void Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onAdd;
  final void Function(int index) onRecrop;
  final void Function(int index) onRotate;
  final void Function(int index) onRelabel;
  final void Function(int index) onRemove;
  final Widget Function(PageEntry page) thumbnail;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Seiten (${pages.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: enabled ? onAdd : null,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Seite hinzufügen'),
            ),
          ],
        ),
        if (pages.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'Noch keine Seiten. Scanne oder fotografiere Vorder- und Rückseite – sie werden zu einem Dokument zusammengefasst.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: enabled,
            itemCount: pages.length,
            onReorderItem: onReorder,
            itemBuilder: (ctx, i) {
              final p = pages[i];
              return Card(
                key: ValueKey(p),
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(width: 56, height: 56, child: thumbnail(p)),
                  ),
                  title: Text(p.label.isEmpty ? 'Seite ${i + 1}' : p.label),
                  subtitle: Text(p.dirty
                      ? 'wird hochgeladen'
                      : p.loadFailed
                          ? 'konnte nicht geladen werden'
                          : 'gespeichert'),
                  trailing: PopupMenuButton<String>(
                    enabled: enabled,
                    onSelected: (v) {
                      switch (v) {
                        case 'crop':
                          onRecrop(i);
                        case 'rotate':
                          onRotate(i);
                        case 'label':
                          onRelabel(i);
                        case 'remove':
                          onRemove(i);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'crop', child: Text('Neu zuschneiden')),
                      PopupMenuItem(value: 'rotate', child: Text('Drehen')),
                      PopupMenuItem(value: 'label', child: Text('Beschriftung ändern')),
                      PopupMenuItem(value: 'remove', child: Text('Entfernen')),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
