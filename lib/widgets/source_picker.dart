import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/vaults_provider.dart';
import '../services/item_service.dart';

/// "Speicherort": personal or one of the (unlocked) vaults. Value = vaultId
/// or null for personal. Renders nothing while the user has no vaults.
class SourcePicker extends ConsumerWidget {
  const SourcePicker(
      {super.key, required this.value, required this.onChanged, this.enabled = true});
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
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}
