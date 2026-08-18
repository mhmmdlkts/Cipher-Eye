import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/key_provider.dart';
import '../providers/vaults_provider.dart';
import '../services/haptics.dart';
import '../services/item_service.dart';
import '../widgets/app_text_field.dart';
import 'vault_detail_screen.dart';
import 'vault_join_screen.dart';

/// All vaults the user belongs to; create a new one or join via invite code.
class VaultsScreen extends ConsumerWidget {
  const VaultsScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    if (!ref.read(hasKeyProvider)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Kein Encryption-Key gesetzt — Tresore brauchen ihn zum Sichern des Tresor-Keys.')));
      return;
    }
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Neuer Tresor'),
        content: AppTextField(
          controller: controller,
          label: 'Name',
          hint: 'z. B. Oma',
          prefixIcon: Icons.group_outlined,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Erstellen')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    await ref.read(vaultsProvider.notifier).create(name.trim());
    Haptics.success();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vaults = ref.watch(vaultsProvider);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Tresore'),
        actions: [
          IconButton(
            tooltip: 'Beitreten',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const VaultJoinScreen())),
          ),
        ],
      ),
      body: vaults.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.group_outlined,
                        size: 64, color: scheme.primary.withValues(alpha: 0.5)),
                    const SizedBox(height: 16),
                    Text('Noch keine Tresore',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      'Erstelle einen Tresor und lade andere per Code ein – '
                      'oder tritt mit einem Einladungscode bei.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const VaultJoinScreen())),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Mit Code beitreten'),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              itemCount: vaults.length,
              separatorBuilder: (_, __) => const Divider(height: 0),
              itemBuilder: (_, i) {
                final v = vaults[i];
                final locked = ItemService.isLocked(v.id);
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.primary.withValues(alpha: 0.12),
                    child: Icon(
                        locked ? Icons.lock_outline : Icons.group_outlined,
                        color: scheme.primary),
                  ),
                  title: Text(v.name),
                  subtitle: Text([
                    '${v.memberCount} Mitglied${v.memberCount == 1 ? '' : 'er'}',
                    if (uid != null && v.isOwner(uid)) 'Du bist Owner',
                    if (locked) 'gesperrt',
                  ].join(' · ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => VaultDetailScreen(v.id))),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: scheme.primary,
        tooltip: 'Neuer Tresor',
        onPressed: () => _create(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
}
