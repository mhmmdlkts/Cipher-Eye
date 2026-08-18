import 'dart:typed_data';

import 'package:cipher_eye/models/attachment.dart';
import 'package:cipher_eye/models/item.dart';
import 'package:cipher_eye/models/item_payload.dart';
import 'package:cipher_eye/models/item_type.dart';
import 'package:cipher_eye/services/attachment_service.dart';
import 'package:cipher_eye/services/secure_storage_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseStorage storage;
  late AttachmentService svc;
  late Item item;
  final plain = Uint8List.fromList(List.generate(4000, (i) => (i * 7) % 256));

  setUp(() {
    SecureStorageService.key = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ012345';
    db = FakeFirebaseFirestore();
    storage = MockFirebaseStorage();
    svc = AttachmentService(storage: storage, db: db, uid: 'u1');
    item = Item.payload(
        col: db.collection('users').doc('u1').collection('items'),
        type: ItemType.document,
        title: 'Pass',
        plainJson: const DocumentData().encode());
  });

  test('upload stores an encrypted blob and download decrypts it', () async {
    final att = await svc.upload(item,
        plain: plain, kind: AttachmentKind.image, label: 'S1', mime: 'image/jpeg', order: 0);
    expect(att.bytes, plain.length);
    expect(att.sha256, isNotNull);
    final stored = await storage.ref(svc.pathFor(item, att.id)).getData();
    expect(stored, isNotNull);
    expect(stored!.length, plain.length + 28);
    expect(stored.sublist(12, 40), isNot(plain.sublist(0, 28)));

    final fresh = AttachmentService(storage: storage, db: db, uid: 'u1');
    expect(await fresh.download(item, att), plain);
  });

  test('delete removes the object; runGc retries recorded paths', () async {
    final att = await svc.upload(item,
        plain: plain, kind: AttachmentKind.image, label: 'S1', mime: 'image/jpeg', order: 0);
    await svc.delete(item, att);
    expect((await db.collection('users').doc('u1').collection('gc').get()).docs, isEmpty);

    // A path left behind by a failed delete is retried by runGc.
    final leftover = svc.pathFor(item, 'left');
    await storage.ref(leftover).putData(Uint8List(3));
    await db.collection('users').doc('u1').collection('gc').add({'path': leftover});
    await svc.runGc();
    expect((await db.collection('users').doc('u1').collection('gc').get()).docs, isEmpty);
    expect((await storage.ref(svc.pathFor(item, 'other')).listAll()).items, isEmpty);
  });

  test('copyAll re-uploads under the target item', () async {
    final att = await svc.upload(item,
        plain: plain, kind: AttachmentKind.image, label: 'S1', mime: 'image/jpeg', order: 0);
    item.attachments.add(att);
    final target = Item.copyTo(item,
        col: db.collection('users').doc('u1').collection('items'), vaultId: null, plainText: item.decrypted());
    final copies = await svc.copyAll(item, target);
    expect(copies.single.id, isNot(att.id));
    expect(await svc.download(target, copies.single), plain);
  });
}
