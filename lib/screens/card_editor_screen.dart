import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kreiseck_validator/kreiseck_validator.dart';

import '../models/item.dart';
import '../models/item_payload.dart';
import '../models/item_type.dart';
import '../providers/items_provider.dart';
import '../providers/key_provider.dart';
import '../services/card_number_formatter.dart';
import '../services/haptics.dart';
import '../services/item_service.dart';
import '../services/card_ocr.dart';
import '../widgets/app_text_field.dart';
import '../widgets/date_field.dart';
import '../widgets/pages_editor.dart';
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
  final _pages = PagesEditorController();
  final _form = GlobalKey<FormState>();
  bool _saving = false;

  static String? _validateNumber(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    return CreditCard.isValid(t) ? null : 'Kartennummer ungültig (Prüfziffer)';
  }

  static String? _validateCvv(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    return RegExp(r'^\d{3,4}$').hasMatch(t)
        ? null
        : 'CVV hat 3 oder 4 Ziffern';
  }

  static String? _validateIban(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    return Iban.isValid(t) ? null : 'IBAN ungültig';
  }

  static String? _validateExpiry(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    return RegExp(r'^(0[1-9]|1[0-2])/\d{2}$').hasMatch(t)
        ? null
        : 'Format MM/JJ';
  }

  String? _vaultId;

  @override
  void initState() {
    super.initState();
    _pages.addListener(_onPages);
    final e = widget.existing;
    _vaultId = e?.vaultId;
    if (e != null) {
      _pages.loadFrom(e);
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

  int _knownPages = 0;

  void _onPages() {
    if (!mounted) return;
    setState(() {});
    // A freshly added page → try to read the card data off it.
    if (_pages.pages.length > _knownPages) {
      final newest = _pages.pages.last;
      if (newest.dirty && newest.bytes != null) _prefillFromScan(newest.bytes!);
    }
    _knownPages = _pages.pages.length;
  }

  Future<void> _prefillFromScan(Uint8List jpeg) async {
    if (!CardOcr.available) return;
    final r = await CardOcr.scan(jpeg);
    if (!mounted || r.isEmpty) return;
    var filled = 0;
    void put(TextEditingController c, String? v) {
      if (v != null && c.text.trim().isEmpty) {
        c.text = v;
        filled++;
      }
    }

    put(_number, r.number);
    put(_expiry, r.expiry);
    put(_holder, r.holder);
    put(_iban, r.iban);
    if (filled == 0) return;
    setState(() {});
    Haptics.selection();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Kartendaten erkannt ($filled Feld${filled == 1 ? '' : 'er'} vorausgefüllt – bitte prüfen)'),
        duration: const Duration(seconds: 3)));
  }

  @override
  void dispose() {
    _pages.removeListener(_onPages);
    _pages.dispose();
    for (final c in [
      _title,
      _number,
      _holder,
      _expiry,
      _cvv,
      _pin,
      _iban,
      _bank,
      _note
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || !ref.read(hasKeyProvider)) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final iban = _iban.text.trim();
    final data = CardData(
      number: CreditCard.tryFormat(_number.text.trim()) ?? _number.text.trim(),
      holder: _holder.text.trim(),
      expiry: _expiry.text.trim(),
      cvv: _cvv.text.trim(),
      pin: _pin.text.trim(),
      iban: iban.isEmpty ? '' : (Iban.tryFormat(iban) ?? iban),
      bank: _bank.text.trim(),
      note: _note.text.trim(),
    );
    final notifier = ref.read(itemsProvider.notifier);
    final existing = widget.existing;
    try {
      Item item;
      if (existing != null) {
        existing.setPayload(
            title: _title.text.trim(), plainJson: data.encode());
        item = await notifier.saveAndPlace(existing, _vaultId);
        if (!identical(item, existing)) _pages.remapAfterMove(existing, item);
      } else {
        item = Item.payload(
          col: ItemService.repoFor(_vaultId).col,
          vaultId: _vaultId,
          type: ItemType.card,
          title: _title.text.trim(),
          plainJson: data.encode(),
        );
        await notifier.add(item);
      }
      if (!_pages.isEmpty || item.hasAttachments) {
        await _pages.commit(item);
        await notifier.save(item);
      }
      if (!mounted) return;
      Haptics.success();
      Navigator.pop(context, item);
    } catch (e) {
      Haptics.warning();
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(
              widget.existing == null ? 'Neue Karte' : 'Karte bearbeiten')),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Form(
        key: _form,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
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
                validator: _validateNumber,
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
                  child: MonthYearField(
                      controller: _expiry,
                      enabled: !_saving,
                      validator: _validateExpiry)),
              const SizedBox(width: 12),
              Expanded(
                  child: AppTextField(
                      controller: _cvv,
                      label: 'CVV',
                      hint: '123',
                      prefixIcon: Icons.lock_outline,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      validator: _validateCvv,
                      inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ])),
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
                prefixIcon: Icons.account_balance_outlined,
                validator: _validateIban),
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
      ),
    );
  }
}
