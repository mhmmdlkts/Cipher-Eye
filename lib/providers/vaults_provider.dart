import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../models/vault.dart';
import '../services/invite_code.dart';
import '../services/item_service.dart';
import 'items_provider.dart';

/// The vaults the user is a member of. Every mutation reloads vaults, keys
/// and their items, then refreshes the item list.
class VaultsNotifier extends Notifier<List<Vault>> {
  @override
  List<Vault> build() => List.of(ItemService.vaults);

  Future<void> refresh() async {
    await ItemService.reloadVaults();
    state = List.of(ItemService.vaults);
    ref.read(itemsProvider.notifier).refresh();
  }

  Future<Vault> create(String name) async {
    final v = await ItemService.vaultService.create(name);
    await refresh();
    return v;
  }

  Future<Vault> join(InviteCode code) async {
    final v = await ItemService.vaultService.join(code);
    await refresh();
    return v;
  }

  Future<void> leave(Vault v) async {
    await ItemService.vaultService.leave(v);
    await refresh();
  }

  Future<void> removeMember(Vault v, String uid) async {
    await ItemService.vaultService.removeMember(v, uid);
    await refresh();
  }

  Future<void> rename(Vault v, String name) async {
    await ItemService.vaultService.rename(v, name);
    await refresh();
  }

  Future<void> delete(Vault v) async {
    await ItemService.vaultService.delete(v);
    await refresh();
  }
}

final vaultsProvider =
    NotifierProvider<VaultsNotifier, List<Vault>>(VaultsNotifier.new);

/// Home list filter: null = all, [kPersonalSource] = personal only, else a
/// vaultId.
final sourceFilterProvider = StateProvider<String?>((_) => null);
const String kPersonalSource = 'personal';

final filteredItemsProvider = Provider<List<Item>>((ref) {
  final all = ref.watch(itemsProvider);
  final f = ref.watch(sourceFilterProvider);
  if (f == null) return all;
  if (f == kPersonalSource) return all.where((i) => i.vaultId == null).toList();
  return all.where((i) => i.vaultId == f).toList();
});
