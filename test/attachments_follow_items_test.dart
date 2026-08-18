import 'dart:typed_data';

import 'package:cipher_eye/models/attachment.dart';
import 'package:cipher_eye/models/item.dart';
import 'package:cipher_eye/models/item_payload.dart';
import 'package:cipher_eye/models/item_type.dart';
import 'package:cipher_eye/services/attachment_service.dart';
import 'package:cipher_eye/services/crypto_service.dart';
import 'package:cipher_eye/services/item_repository.dart';
import 'package:cipher_eye/services/item_service.dart';
import 'package:cipher_eye/services/keys.dart';
import 'package:cipher_eye/services/secure_storage_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseStorage storage;
  final vaultKey = CryptoService.randomKey();
  final plain = Uint8List.fromList(List.generate(2000, (i) => i % 256));

  setUp(() {
    SecureStorageService.key = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ012345';
    db = FakeFirebaseFirestore();
    storage = MockFirebaseStorage();
    AttachmentService.instance = AttachmentService(storage: storage, db: db, uid: 'u1');
    Keys.resolver = (id) => id == 'v1' ? vaultKey : Keys.masterOnly(null);
    ItemService.personal = ItemRepository(
        db.collection('users').doc('u1').collection('items'), history: (_, __) {});
    ItemService.vaultRepos
      ..clear()
      ..['v1'] = ItemRepository(db.collection('vaults').doc('v1').collection('items'),
          vaultId: 'v1', history: (_, __) {});
  });

  tearDown(() {
    Keys.resolver = Keys.masterOnly;
    AttachmentService.instance = AttachmentService();
  });

  Future<Item> docWithPage() async {
    final item = Item.payload(
        col: ItemService.personal.col,
        type: ItemType.document,
        title: 'Pass',
        plainJson: const DocumentData(docType: DocType.passport).encode());
    await ItemService.personal.add(item);
    final att = await AttachmentService.instance.upload(item,
        plain: plain, kind: AttachmentKind.image, label: 'Vorderseite', mime: 'image/jpeg', order: 0);
    item.attachments = [att];
    await ItemService.personal.save(item);
    return item;
  }

  test('moving into a vault re-uploads the blob under the vault path and removes the old one', () async {
    final item = await docWithPage();
    final oldPath = AttachmentService.instance.pathFor(item, item.attachments.single.id);
    final moved = await ItemService.move(item, 'v1');
    expect(moved.vaultId, 'v1');
    expect(moved.attachments.single.id, isNot(item.attachments.single.id));
    final newPath = AttachmentService.instance.pathFor(moved, moved.attachments.single.id);
    expect(newPath, startsWith('vaults/v1/items/'));
    expect(await storage.ref(newPath).getData(), isNotNull);
    expect(await AttachmentService.instance.download(moved, moved.attachments.single), plain);
    // Old blob is gone, old doc is gone.
    expect(await storage.ref(oldPath).getData(), isNull);
    expect((await ItemService.personal.col.get()).docs, isEmpty);
    expect((await ItemService.vaultRepos['v1']!.col.get()).docs.length, 1);
  });

  test('deleting an item deletes its blobs', () async {
    final item = await docWithPage();
    final path = AttachmentService.instance.pathFor(item, item.attachments.single.id);
    expect(await storage.ref(path).getData(), isNotNull);
    await ItemService.personal.delete(item);
    expect(await storage.ref(path).getData(), isNull);
  });
}
