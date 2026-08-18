import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../models/item_payload.dart';
import '../models/item_type.dart';
import '../providers/items_provider.dart';
import '../providers/key_provider.dart';
import '../services/firestore_paths_service.dart';
import '../services/haptics.dart';
import '../widgets/app_text_field.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, this.existing});
  final Item? existing;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _title = TextEditingController();
  final _text = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _title.text = e.title ?? '';
      try {
        _text.text = NoteData.decode(e.decrypted()).text ?? '';
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || !ref.read(hasKeyProvider)) return;
    setState(() => _saving = true);
    final data = NoteData(text: _text.text.trim());
    final notifier = ref.read(itemsProvider.notifier);
    final existing = widget.existing;
    if (existing != null) {
      existing.setPayload(title: _title.text.trim(), plainJson: data.encode());
      await notifier.save(existing);
    } else {
      await notifier.add(Item.payload(
        col: FirestorePathsService.getItemsCol(),
        type: ItemType.note,
        title: _title.text.trim(),
        plainJson: data.encode(),
      ));
    }
    if (!mounted) return;
    Haptics.success();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(
              widget.existing == null ? 'Neue Notiz' : 'Notiz bearbeiten')),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppTextField(
              controller: _title,
              label: 'Titel',
              hint: 'z. B. WLAN Zuhause',
              prefixIcon: Icons.sticky_note_2_outlined,
              onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          AppTextField(
              controller: _text,
              label: 'Notiz',
              hint: 'Recovery-Codes, PUK, WLAN-Passwort …',
              prefixIcon: Icons.notes,
              maxLines: 10),
          const SizedBox(height: 24),
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
