import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/item.dart';
import '../models/item_type.dart';
import 'attachment_service.dart';
import 'history_service.dart';

/// Receives (action, itemId) for create/update/delete so the repository does
/// not depend on where history is written (personal history today, vault
/// history later).
typedef HistoryLogger = void Function(String action, String itemId);

void _defaultHistory(String action, String itemId) =>
    HistoryService.log(action, itemId);

/// All items of one collection (the personal `items` collection today; one
/// per vault later). Owns loading, version bookkeeping and persistence.
class ItemRepository {
  ItemRepository(this.col, {this.vaultId, HistoryLogger? history})
      : _history = history ?? _defaultHistory;

  final CollectionReference col;

  /// null = personal, otherwise the vault this collection belongs to.
  final String? vaultId;
  final HistoryLogger _history;
  final List<Item> items = [];

  /// Loads [col] plus any [extraSources] (legacy collections). Items keep the
  /// document reference they were loaded from, so writes go back to the right
  /// place. When the same id exists in several sources, [col] wins.
  Future<void> load({List<CollectionReference> extraSources = const []}) async {
    final byId = <String, Item>{};
    for (final src in extraSources) {
      for (final d in (await src.get()).docs) {
        byId[d.id] = Item.fromSnapshot(d)..vaultId = vaultId;
      }
    }
    for (final d in (await col.get()).docs) {
      byId[d.id] = Item.fromSnapshot(d)..vaultId = vaultId;
    }
    items
      ..clear()
      ..addAll(byId.values);
    _recomputeLatest();
    items.sort();
  }

  void _recomputeLatest() {
    final newestByPurpose = <String, Item>{};
    for (final it in items) {
      it.isLatest = false;
      if (it.type != ItemType.password || it.isDraft) continue;
      final key = it.purposeId ?? it.id!;
      final cur = newestByPurpose[key];
      if (cur == null || _ts(it) > _ts(cur)) newestByPurpose[key] = it;
    }
    for (final it in newestByPurpose.values) {
      it.isLatest = true;
    }
  }

  static int _ts(Item i) => i.timestamp?.millisecondsSinceEpoch ?? 0;

  /// What the list shows: latest password per purpose + every non-password
  /// that has not been archived by a renewal.
  List<Item> get latest => items
      .where((i) =>
          !i.isDraft &&
          !i.archived &&
          (i.type != ItemType.password || i.isLatest))
      .toList();

  Item? byId(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// Older, archived versions of a renewed item (newest first).
  List<Item> predecessorsOf(Item item) {
    final out = <Item>[];
    var cur = item.predecessorId == null ? null : byId(item.predecessorId!);
    final seen = <String>{item.id!};
    while (cur != null && seen.add(cur.id!)) {
      out.add(cur);
      cur = cur.predecessorId == null ? null : byId(cur.predecessorId!);
    }
    return out;
  }

  List<Item> get drafts => items.where((i) => i.isDraft).toList();

  /// All stored versions of a password purpose, newest first.
  List<Item> versionsOf(String purposeId) {
    final list = items
        .where((i) =>
            i.type == ItemType.password &&
            i.purposeId == purposeId &&
            !i.isDraft)
        .toList()
      ..sort((a, b) => _ts(b).compareTo(_ts(a)));
    return list;
  }

  Future<void> add(Item item) async {
    item.vaultId = vaultId;
    items.add(item);
    _recomputeLatest();
    if (!item.isDraft) _history('create', item.id!);
    await item.push();
  }

  /// Password edit: the new version is stored next to the old one, which is
  /// kept (no longer latest) so the old password can still be looked up.
  Future<void> updateVersion(Item item) async {
    item.vaultId = vaultId;
    items.add(item);
    _recomputeLatest();
    _history('update', item.id!);
    await item.push();
  }

  /// Renames a password purpose (website/username) across all its versions
  /// so the history stays together under the new purposeId.
  Future<void> updatePasswordMeta(Item item,
      {required String website, required String username}) async {
    final versions = item.isDraft ? [item] : versionsOf(item.purposeId ?? '');
    final purposeId = Item.purposeIdCreate(website: website, username: username);
    for (final v in versions) {
      v.title = website;
      v.username = username;
      v.purposeId = purposeId;
      v.updatedAt = Timestamp.now();
      await v.ref!.update({
        'title': website,
        'username': username,
        'purposeId': purposeId,
        'updatedAt': v.updatedAt,
      });
    }
    _recomputeLatest();
    _history('update', item.id!);
  }

  /// In-place save (drafts, non-password types).
  Future<void> save(Item item) async {
    item.vaultId = vaultId;
    if (!items.contains(item)) items.add(item);
    _recomputeLatest();
    await item.push();
  }

  /// Deletes a draft by itself, a password with all its versions, anything
  /// else by itself.
  Future<void> delete(Item item) async {
    _history('delete', item.id!);
    final victims = (item.type == ItemType.password && !item.isDraft)
        ? items
            .where((i) =>
                i.type == ItemType.password &&
                !i.isDraft &&
                i.purposeId == item.purposeId)
            .toList()
        : [item];
    items.removeWhere(victims.contains);
    _recomputeLatest();
    for (final v in victims) {
      if (v.hasAttachments) await AttachmentService.instance.deleteAll(v);
      await v.ref!.delete();
      // Deleting a renewed document brings its archived predecessor back,
      // so nothing silently disappears from the list.
      final prev = v.predecessorId == null ? null : byId(v.predecessorId!);
      if (prev != null && prev.archived && prev.supersededBy == v.id) {
        prev.archived = false;
        prev.supersededBy = null;
        await prev.ref!.update({'archived': false, 'supersededBy': null});
      }
    }
  }

  Future<void> incrementUsage(Item item, {required bool copy}) {
    final field = copy ? 'copyCount' : 'viewCount';
    if (copy) {
      item.copyCount++;
    } else {
      item.viewCount++;
    }
    return item.ref!.update({field: FieldValue.increment(1)});
  }

  void maskAll() {
    for (final i in items) {
      i.isVisible = false;
    }
  }
}
