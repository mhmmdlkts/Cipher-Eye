import 'package:cipher_eye/models/item.dart';
import 'package:cipher_eye/models/item_payload.dart';
import 'package:cipher_eye/models/item_type.dart';
import 'package:cipher_eye/services/item_repository.dart';
import 'package:cipher_eye/services/secure_storage_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ItemRepository repo;
  setUp(() {
    SecureStorageService.key = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ012345';
    db = FakeFirebaseFirestore();
    repo = ItemRepository(db.collection('users').doc('u1').collection('items'),
        history: (_, __) {});
  });

  test('add + load marks the newest version per purpose as latest', () async {
    final a = Item.password(col: repo.col, website: 'w', username: 'u', plainText: '1');
    await repo.add(a);
    final b = Item.password(col: repo.col, website: 'w', username: 'u', plainText: '2');
    await repo.updateVersion(b);
    final fresh = ItemRepository(repo.col, history: (_, __) {});
    await fresh.load();
    expect(fresh.items.length, 2);
    expect(fresh.latest.map((i) => i.id), [b.id]);
    expect(fresh.versionsOf(a.purposeId!).first.id, b.id);
  });

  test('non-password items are always in latest and edited in place', () async {
    final n = Item.payload(col: repo.col, type: ItemType.note, title: 'N',
        plainJson: const NoteData(text: 'a').encode());
    await repo.add(n);
    n.setPayload(title: 'N2', plainJson: const NoteData(text: 'b').encode());
    await repo.save(n);
    final fresh = ItemRepository(repo.col, history: (_, __) {});
    await fresh.load();
    expect(fresh.latest.single.title, 'N2');
    expect(NoteData.decode(fresh.latest.single.decrypted()).text, 'b');
  });

  test('delete removes every version of a password, a draft only itself', () async {
    final a = Item.password(col: repo.col, website: 'w', username: 'u', plainText: '1');
    await repo.add(a);
    final b = Item.password(col: repo.col, website: 'w', username: 'u', plainText: '2');
    await repo.updateVersion(b);
    final d = Item.draft(col: repo.col, username: 'u', plainText: 'x');
    await repo.add(d);
    await repo.delete(d);
    expect((await repo.col.get()).docs.length, 2);
    await repo.delete(b);
    expect((await repo.col.get()).docs, isEmpty);
    expect(repo.items, isEmpty);
  });

  test('load can merge extra (legacy) sources', () async {
    final legacy = db.collection('users').doc('u1').collection('passwords');
    await legacy.doc('old').set({'website': 'l', 'username': 'u', 'value': 'v', 'iv': 'i', 'v': 2,
        'purposeId': 'p', 'timestamp': DateTime(2024)});
    await repo.load(extraSources: [legacy]);
    expect(repo.items.single.title, 'l');
    expect(repo.items.single.ref!.path, legacy.doc('old').path);
  });
}
