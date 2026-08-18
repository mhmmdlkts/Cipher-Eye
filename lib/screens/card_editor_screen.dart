import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../models/item_payload.dart';
import '../models/item_type.dart';
import '../providers/items_provider.dart';
import '../providers/key_provider.dart';
import '../services/card_number_formatter.dart';
import '../services/haptics.dart';
import '../services/item_service.dart';
import '../widgets/app_text_field.dart';
import '../widgets/source_picker.dart';

class CardEditorScreen extends ConsumerStatefulWidget {
  const CardEditorScreen({super.key, this.existing});
  final Item? existing;

  @override
  ConsumerState<CardEditorScreen> createState() => _CardEditorScreenState();
}

class _CardEditorScreenState extends ConsumerState<CardEditorScreen> {
  final _title = TextEditingController();
  final _number = TextEditingController();
  final _holder = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();
  final _pin = TextEditingController();
  final _iban = TextEditingController();
  final _bank = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;
  String? _vaultId;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _vaultId = e?.vaultId;
    if (e != null) {
      _title.text = e.title ?? '';
      try {
        final c = CardData.decode(e.decrypted());
        _number.text = c.number ?? '';
        _holder.text = c.holder ?? '';
        _expiry.text = c.expiry ?? '';
        _cvv.text = c.cvv ?? '';
        _pin.text = c.pin ?? '';
        _iban.text = c.iban ?? '';
        _bank.text = c.bank ?? '';
        _note.text = c.note ?? '';
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    for (final c in [
      _title, _number, _holder, _expiry, _cvv, _pin, _iban, _bank, _note
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || !ref.read(hasKeyProvider)) return;
    setState(() => _saving = true);
    final data = CardData(
      number: _number.text.trim(),
      holder: _holder.text.trim(),
      expiry: _expiry.text.trim(),
      cvv: _cvv.text.trim(),
      pin: _pin.text.trim(),
      iban: _iban.text.trim(),
      bank: _bank.text.trim(),
      note: _note.text.trim(),
    );
    final notifier = ref.read(itemsProvider.notifier);
    final existing = widget.existing;
    if (existing != null) {
      existing.setPayload(title: _title.text.trim(), plainJson: data.encode());
      await notifier.save(existing);
      if (_vaultId != existing.vaultId) {
        await notifier.move(existing, _vaultId);
      }
    } else {
      await notifier.add(Item.payload(
        col: ItemService.repoFor(_vaultId).col,
        vaultId: _vaultId,
        type: ItemType.card,
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
              widget.existing == null ? 'Neue Karte' : 'Karte bearbeiten')),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SourcePicker(
              value: _vaultId,
              enabled: !_saving,
              onChanged: (v) => setState(() => _vaultId = v)),
          AppTextField(
              controller: _title,
              label: 'Bezeichnung',
              hint: 'z. B. Visa Sparkasse',
              prefixIcon: Icons.credit_card,
              onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          AppTextField(
              controller: _number,
              label: 'Kartennummer',
              hint: '1234 5678 9012 3456',
              prefixIcon: Icons.numbers,
              keyboardType: TextInputType.number,
              inputFormatters: [CardNumberFormatter()]),
          const SizedBox(height: 12),
          AppTextField(
              controller: _holder,
              label: 'Karteninhaber',
              hint: 'Name wie auf der Karte',
              prefixIcon: Icons.person_outline),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: AppTextField(
                    controller: _expiry,
                    label: 'Gültig bis',
                    hint: 'MM/JJ',
                    prefixIcon: Icons.event,
                    keyboardType: TextInputType.datetime)),
            const SizedBox(width: 12),
            Expanded(
                child: AppTextField(
                    controller: _cvv,
                    label: 'CVV',
                    hint: '123',
                    prefixIcon: Icons.lock_outline,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
          ]),
          const SizedBox(height: 12),
          AppTextField(
              controller: _pin,
              label: 'PIN',
              hint: 'optional',
              prefixIcon: Icons.pin_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
          const SizedBox(height: 12),
          AppTextField(
              controller: _iban,
              label: 'IBAN',
              hint: 'optional',
              prefixIcon: Icons.account_balance_outlined),
          const SizedBox(height: 12),
          AppTextField(
              controller: _bank,
              label: 'Bank',
              hint: 'optional',
              prefixIcon: Icons.account_balance),
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
