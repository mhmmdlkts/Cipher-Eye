import '../models/item.dart';
import 'firestore_paths_service.dart';
import 'item_repository.dart';
import 'items_migration_service.dart';
import 'person_service.dart';

/// Static facade over the personal item repository (kept static so the
/// existing UI/services keep working; vaults add more repositories later).
class ItemService {
  static late ItemRepository personal;

  static List<Item> get items => personal.items;
  static List<Item> get latest => personal.latest;
  static List<Item> get drafts => personal.drafts;
  static List<Item> versionsOf(String purposeId) =>
      personal.versionsOf(purposeId);
  static void maskAll() => personal.maskAll();

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
  }

  static Future<void> incrementUsage(String itemId, {required bool copy}) {
    final item = personal.items.firstWhere((i) => i.id == itemId);
    return personal.incrementUsage(item, copy: copy);
  }
}
