import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../services/item_service.dart';

/// Reactive view over all loaded items. [ItemService] stays the data layer;
/// this notifier exposes the list the UI shows so add/save/delete update the
/// screen automatically.
class ItemsNotifier extends Notifier<List<Item>> {
  @override
  List<Item> build() => _combined();

  /// Drafts first (newest), then everything else sorted by how often it is
  /// used (copy + view counts, highest first; timestamp as tiebreak).
  List<Item> _combined() {
    int ts(Item i) => i.timestamp?.millisecondsSinceEpoch ?? 0;
    int usage(Item i) => i.copyCount + i.viewCount;
    final drafts = ItemService.drafts..sort((a, b) => ts(b).compareTo(ts(a)));
    final entries = ItemService.latest
      ..sort((a, b) {
        final byUsage = usage(b).compareTo(usage(a));
        return byUsage != 0 ? byUsage : ts(b).compareTo(ts(a));
      });
    return [...drafts, ...entries];
  }

  void refresh() => state = _combined();

  /// Hide every revealed value (called when the list re-appears / on lock).
  void maskAll() {
    ItemService.maskAll();
    refresh();
  }

  Future<void> add(Item item) async {
    await ItemService.repoFor(item.vaultId).add(item);
    refresh();
  }

  /// Password edit → stored as a new version of the same purpose.
  Future<void> updateVersion(Item item) async {
    await ItemService.repoFor(item.vaultId).updateVersion(item);
    refresh();
  }

  /// In-place save (drafts, cards, notes, …).
  Future<void> save(Item item) async {
    await ItemService.repoFor(item.vaultId).save(item);
    refresh();
  }

  Future<void> delete(Item item) async {
    await ItemService.repoFor(item.vaultId).delete(item);
    refresh();
  }

  /// Re-encrypts and moves an item to another source (null = personal).
  Future<Item> move(Item item, String? toVaultId) async {
    final moved = await ItemService.move(item, toVaultId);
    refresh();
    return moved;
  }

  Future<void> addDraft(Item draft) => save(draft);
  Future<void> saveDraft(Item draft, {bool finalize = false}) => save(draft);
}

final itemsProvider =
    NotifierProvider<ItemsNotifier, List<Item>>(ItemsNotifier.new);
