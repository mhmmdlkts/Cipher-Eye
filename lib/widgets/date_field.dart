import 'package:flutter/material.dart';

import 'app_text_field.dart';

/// Read-only field that opens a calendar picker; value is "TT.MM.JJJJ".
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.controller,
    required this.label,
    this.prefixIcon = Icons.event,
    this.enabled = true,
    this.firstYear = 1900,
    this.lastYear = 2100,
  });

  final TextEditingController controller;
  final String label;
  final IconData prefixIcon;
  final bool enabled;
  final int firstYear, lastYear;

  static String format(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  static DateTime? parse(String s) {
    final m = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$').firstMatch(s.trim());
    if (m == null) return null;
    return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
  }

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final initial = parse(controller.text) ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(firstYear),
      lastDate: DateTime(lastYear, 12, 31),
      locale: const Locale('de'),
    );
    if (d != null) controller.text = format(d);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? () => _pick(context) : null,
      child: AbsorbPointer(
        child: AppTextField(
          controller: controller,
          label: label,
          hint: 'TT.MM.JJJJ',
          prefixIcon: prefixIcon,
          enabled: enabled,
          suffix: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Löschen',
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: enabled ? () => controller.clear() : null),
        ),
      ),
    );
  }
}

/// Month/year picker for card expiry; value is "MM/JJ".
class MonthYearField extends StatelessWidget {
  const MonthYearField({
    super.key,
    required this.controller,
    this.label = 'Gültig bis',
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    var month = now.month;
    var year = now.year;
    final m = RegExp(r'^(\d{2})/(\d{2})$').firstMatch(controller.text.trim());
    if (m != null) {
      month = int.parse(m.group(1)!);
      year = 2000 + int.parse(m.group(2)!);
    }
    final years = List.generate(21, (i) => now.year - 5 + i);
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(label),
          content: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: month,
                  decoration: const InputDecoration(labelText: 'Monat'),
                  items: [
                    for (var i = 1; i <= 12; i++)
                      DropdownMenuItem(value: i, child: Text(i.toString().padLeft(2, '0'))),
                  ],
                  onChanged: (v) => setState(() => month = v ?? month),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: years.contains(year) ? year : now.year,
                  decoration: const InputDecoration(labelText: 'Jahr'),
                  items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
                  onChanged: (v) => setState(() => year = v ?? year),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, (month, year)), child: const Text('OK')),
          ],
        ),
      ),
    );
    if (result != null) {
      controller.text =
          '${result.$1.toString().padLeft(2, '0')}/${(result.$2 % 100).toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? () => _pick(context) : null,
      child: AbsorbPointer(
        child: AppTextField(
          controller: controller,
          label: label,
          hint: 'MM/JJ',
          prefixIcon: Icons.event,
          enabled: enabled,
          suffix: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Löschen',
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: enabled ? () => controller.clear() : null),
        ),
      ),
    );
  }
}
