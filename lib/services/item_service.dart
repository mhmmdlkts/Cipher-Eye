import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/item.dart';
import '../models/item_type.dart';
import '../models/vault.dart';
import 'crypto_service.dart';
import 'firestore_paths_service.dart';
import 'history_service.dart';
import 'item_repository.dart';
import 'items_migration_service.dart';
import 'keys.dart';
import 'person_service.dart';
import 'secure_storage_service.dart';
import 'vault_key_store.dart';
import 'vault_service.dart';

/// Static facade over every item source: the personal repository plus one
/// repository per unlocked vault. Kept static so the existing UI/services
/// keep working.
class ItemService {
  static late ItemRepository personal;
  static final Map<String, ItemRepository> vaultRepos = {};
  static List<Vault> vaults = [];
  static late VaultService vaultService;
  static VaultKeyStore? _keys;

  /// A vault is locked when its key could not be unwrapped (no master key or
  /// the wrong one) — its items are neither loaded nor editable.
  static bool isLocked(String vaultId) => _keys?.get(vaultId) == null;

  static Iterable<ItemRepository> get repos => [personal, ...vaultRepos.values];
  static List<Item> get items => [for (final r in repos) ...r.items];
  static List<Item> get latest => [for (final r in repos) ...r.latest];
  static List<Item> get drafts => [for (final r in repos) ...r.drafts];
  static List<Item> versionsOf(String purposeId, {String? vaultId}) =>
      repoFor(vaultId).versionsOf(purposeId);
  static void maskAll() {
    for (final r in repos) {
      r.maskAll();
    }
  }

  static ItemRepository repoFor(String? vaultId) =>
      vaultId == null ? personal : vaultRepos[vaultId]!;

  static Vault? vaultById(String? id) {
    if (id == null) return null;
    for (final v in vaults) {
      if (v.id == id) return v;
    }
    return null;
  }

  static Future<void> init() async {
    personal = ItemRepository(FirestorePathsService.getItemsCol());
    var migrated =
        PersonService.person.dataVersion >= PersonService.kDataVersion;
    if (!migrated) {
      try {
        await ItemsMigrationService(
          from: FirestorePathsService.getPasswordCol(),
          to: FirestorePathsService.getItemsCol(),
          profile: FirestorePathsService.getUserDoc(),
        ).run();
        PersonService.person.dataVersion = PersonService.kDataVersion;
        migrated = true;
      } catch (_) {
        // Fall back to reading both collections; retried on next launch.
      }
    }
    await personal.load(
        extraSources:
            migrated ? const [] : [FirestorePathsService.getPasswordCol()]);
    await reloadVaults();
  }

  /// (Re)builds the vault service, key store, resolver and per-vault repos.
  /// Safe to call any time (after join/leave, pull-to-refresh, key change).
  static Future<void> reloadVaults() async {
    final master = SecureStorageService.key;
    final user = FirebaseAuth.instance.currentUser!;
    _keys = master == null
        ? null
        : VaultKeyStore(masterKey: CryptoService.keyFromMaster(master));
    Keys.resolver = (vaultId) {
      if (vaultId == null) return Keys.masterOnly(null);
      final k = _keys?.get(vaultId);
      if (k == null) throw StateError('Vault $vaultId is locked');
      return k;
    };
    vaultService = VaultService(
      db: FirebaseFirestore.instance,
      uid: user.uid,
      displayName: PersonService.person.name ?? user.email ?? user.uid,
      keys: _keys ?? VaultKeyStore(masterKey: CryptoService.randomKey()),
    );
    try {
      vaults = await vaultService.loadMine();
    } catch (_) {
      vaults = [];
    }
    if (_keys != null) await vaultService.loadKeys(vaults);
    vaultRepos.clear();
    for (final v in vaults) {
      if (isLocked(v.id)) continue;
      final repo = ItemRepository(
        vaultService.vaultsCol.doc(v.id).collection('items'),
        vaultId: v.id,
        history: (action, id) => HistoryService.log(action, id, vaultId: v.id),
      );
      try {
        await repo.load();
        vaultRepos[v.id] = repo;
      } catch (_) {
        // Membership may have been revoked meanwhile — skip this vault only.
      }
    }
  }

  static Future<void> incrementUsage(String itemId, {required bool copy}) {
    final item = items.firstWhere((i) => i.id == itemId);
    return repoFor(item.vaultId).incrementUsage(item, copy: copy);
  }

  /// Moves an item (all versions for passwords) to another source: decrypt
  /// with the source key, encrypt with the target key, write, delete source.
  static Future<Item> move(Item item, String? toVaultId) async {
    if (item.vaultId == toVaultId) return item;
    final from = repoFor(item.vaultId);
    final to = repoFor(toVaultId);
    final versions = item.type == ItemType.password && !item.isDraft
        ? from.versionsOf(item.purposeId!)
        : [item];
    Item? moved;
    for (final v in versions) {
      final plain = v.decrypted();
      final copy =
          Item.copyTo(v, col: to.col, vaultId: toVaultId, plainText: plain);
      await to.save(copy);
      if (v.id == item.id) moved = copy;
    }
    await from.delete(item);
    return moved!;
  }
}
