import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vault.dart';
import '../providers/vaults_provider.dart';
import '../services/haptics.dart';
import '../services/item_service.dart';
import '../widgets/text_prompt_dialog.dart';
import 'vault_invite_screen.dart';

/// Members, invite, and owner/member actions for one vault.
class VaultDetailScreen extends ConsumerWidget {
  const VaultDetailScreen(this.vaultId, {super.key});
  final String vaultId;

  Future<bool> _confirm(BuildContext context, String title, String body,
      {String action = 'OK'}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, Vault v) async {
    final name = await showTextPrompt(context,
        title: 'Tresor umbenennen',
        label: 'Name',
        initial: v.name,
        confirm: 'Speichern');
    if (name == null || name.trim().isEmpty) return;
    await ref.read(vaultsProvider.notifier).rename(v, name.trim());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    final vault = ref
        .watch(vaultsProvider)
        .where((v) => v.id == vaultId)
        .firstOrNull;
    if (vault == null) {
      // Deleted / left meanwhile.
      return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('Tresor nicht mehr verfügbar')));
    }
    final isOwner = vault.isOwner(me);
    final locked = ItemService.isLocked(vault.id);
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(vault.name),
        actions: [
          if (isOwner)
            IconButton(
                tooltip: 'Umbenennen',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _rename(context, ref, vault)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: scheme.primary,
                    child: Icon(
                        locked ? Icons.lock_outline : Icons.group_outlined,
                        color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(vault.name,
                            style: Theme.of(context).textTheme.titleLarge),
                        Text(
                            '${vault.memberCount} Mitglied${vault.memberCount == 1 ? '' : 'er'}'
                            '${locked ? ' · gesperrt (Encryption-Key prüfen)' : ''}',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: locked
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => VaultInviteScreen(vault))),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Einladen'),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Mitglieder', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final uid in vault.memberIds)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: scheme.primary.withValues(alpha: 0.12),
                child: Text(vault.nameOf(uid).isEmpty
                    ? '?'
                    : vault.nameOf(uid)[0].toUpperCase()),
              ),
              title: Text(uid == me ? '${vault.nameOf(uid)} (du)' : vault.nameOf(uid)),
              subtitle: Text(uid == vault.ownerId ? 'Owner' : 'Mitglied'),
              trailing: isOwner && uid != me
                  ? IconButton(
                      tooltip: 'Entfernen',
                      icon: Icon(Icons.person_remove_outlined,
                          color: scheme.error),
                      onPressed: () async {
                        if (!await _confirm(
                            context,
                            'Mitglied entfernen',
                            '${vault.nameOf(uid)} verliert sofort den Zugriff auf diesen Tresor.',
                            action: 'Entfernen')) {
                          return;
                        }
                        Haptics.warning();
                        await ref
                            .read(vaultsProvider.notifier)
                            .removeMember(vault, uid);
                      },
                    )
                  : null,
            ),
          const SizedBox(height: 32),
          if (isOwner)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
              onPressed: () async {
                if (!await _confirm(
                    context,
                    'Tresor löschen',
                    'Alle Einträge im Tresor werden für alle Mitglieder unwiderruflich gelöscht.',
                    action: 'Löschen')) {
                  return;
                }
                if (!context.mounted) return;
                final navigator = Navigator.of(context);
                Haptics.warning();
                await ref.read(vaultsProvider.notifier).delete(vault);
                navigator.pop();
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Tresor löschen'),
            )
          else
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
              onPressed: () async {
                if (!await _confirm(context, 'Tresor verlassen',
                    'Du verlierst den Zugriff auf alle Einträge in „${vault.name}“.',
                    action: 'Verlassen')) {
                  return;
                }
                if (!context.mounted) return;
                final navigator = Navigator.of(context);
                Haptics.warning();
                await ref.read(vaultsProvider.notifier).leave(vault);
                navigator.pop();
              },
              icon: const Icon(Icons.logout),
              label: const Text('Tresor verlassen'),
            ),
        ],
      ),
    );
  }
}
