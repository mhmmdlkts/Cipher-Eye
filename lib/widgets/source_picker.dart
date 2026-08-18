import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/vaults_provider.dart';
import '../services/item_service.dart';

/// "Speicherort": personal or one of the (unlocked) vaults. Value = vaultId
/// or null for personal. Renders nothing while the user has no vaults.
/// Every change is confirmed with a dialog that spells out who will be able
/// to see the entry afterwards.
class SourcePicker extends ConsumerWidget {
  const SourcePicker(
      {super.key,
      required this.value,
      required this.onChanged,
      this.enabled = true});
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vaults = ref
        .watch(vaultsProvider)
        .where((v) => !ItemService.isLocked(v.id))
        .toList();
    if (vaults.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String?>(
        key: ValueKey(value),
        initialValue: vaults.any((v) => v.id == value) ? value : null,
        decoration: InputDecoration(
          labelText: 'Speicherort',
          prefixIcon: const Icon(Icons.folder_outlined),
          filled: true,
          fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        items: [
          const DropdownMenuItem<String?>(
              value: null, child: Text('Persönlich')),
          for (final v in vaults)
            DropdownMenuItem<String?>(
                value: v.id, child: Text('Tresor „${v.name}“')),
        ],
        onChanged: !enabled
            ? null
            : (v) async {
                if (v == value) return;
                final ok = await confirmSourceChange(context, from: value, to: v);
                if (ok) onChanged(v);
              },
      ),
    );
  }
}

/// Explains who can see the entry after the change and asks for confirmation.
Future<bool> confirmSourceChange(BuildContext context,
    {required String? from, required String? to}) async {
  final me = FirebaseAuth.instance.currentUser?.uid ?? '';
  final target = ItemService.vaultById(to);
  final source = ItemService.vaultById(from);
  final scheme = Theme.of(context).colorScheme;

  String names(List<String> ids, {required String Function(String) nameOf}) =>
      ids.map((id) => id == me ? '${nameOf(id)} (du)' : nameOf(id)).join(', ');

  final String title;
  final List<Widget> body;
  if (target != null) {
    title = 'In Tresor „${target.name}“ verschieben?';
    body = [
      Text('Danach können alle ${target.memberCount} Mitglieder diesen Eintrag '
          'sehen, kopieren und ändern:'),
      const SizedBox(height: 8),
      Text(names(target.memberIds, nameOf: target.nameOf),
          style: const TextStyle(fontWeight: FontWeight.w600)),
      if (source != null) ...[
        const SizedBox(height: 12),
        Text('Die Mitglieder von „${source.name}“ verlieren den Zugriff.'),
      ],
      const SizedBox(height: 12),
      Text('Der Eintrag wird mit dem Schlüssel des Tresors neu verschlüsselt.',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
    ];
  } else {
    title = 'Zu „Persönlich“ verschieben?';
    body = [
      Text(source == null
          ? 'Nur du kannst diesen Eintrag sehen.'
          : 'Danach kannst nur noch du diesen Eintrag sehen. Die anderen '
              'Mitglieder von „${source.name}“ verlieren den Zugriff.'),
    ];
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(children: [
        Icon(Icons.group_outlined, color: scheme.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(title)),
      ]),
      content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen')),
        ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verschieben')),
      ],
    ),
  );
  return ok == true;
}
