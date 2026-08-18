import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../models/item_payload.dart';
import '../models/item_type.dart';
import '../providers/items_provider.dart';
import '../providers/key_provider.dart';
import '../services/haptics.dart';
import '../services/item_service.dart';
import '../widgets/app_text_field.dart';
import '../widgets/pages_editor.dart';
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
  final _pages = PagesEditorController();
  DocType _docType = DocType.other;
  String? _vaultId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _pages.addListener(_onPages);
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
      _pages.loadFrom(e);
    } else {
      _docType = widget.docType ?? DocType.other;
      _title.text = _docType == DocType.other ? '' : _docType.label;
    }
  }

  void _onPages() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pages.removeListener(_onPages);
    _pages.dispose();
    for (final c in [_title, _number, _issued, _expires, _note]) {
      c.dispose();
    }
    super.dispose();
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
        item = await notifier.saveAndPlace(existing, _vaultId);
        if (!identical(item, existing)) _pages.remapAfterMove(existing, item);
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
      await _pages.commit(item);
      await notifier.save(item);
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
                      final wasDefault = _title.text.trim().isEmpty ||
                          _title.text == _docType.label;
                      _docType = t;
                      if (wasDefault && t != DocType.other) {
                        _title.text = t.label;
                      }
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
          PagesEditor(controller: _pages, enabled: !_saving),
          const SizedBox(height: 24),
          if (_pages.progress != null) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 6),
            Text(_pages.progress!,
                style: Theme.of(context).textTheme.bodySmall),
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
