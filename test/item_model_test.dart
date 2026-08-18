import 'package:cipher_eye/models/item.dart';
import 'package:cipher_eye/models/item_payload.dart';
import 'package:cipher_eye/models/item_type.dart';
import 'package:cipher_eye/services/secure_storage_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore db;
  setUp(() {
    SecureStorageService.key = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ012345';
    db = FakeFirebaseFirestore();
  });

  test('password item: title/website alias, encrypted value, toJson shape', () {
    final col = db.collection('users').doc('u1').collection('items');
    final it = Item.password(col: col, website: 'example.org', username: 'max', plainText: 'pw1');
    expect(it.type, ItemType.password);
    expect(it.title, 'example.org');
    expect(it.website, 'example.org');
    expect(it.value, isNot('pw1'));
    expect(it.decrypted(), 'pw1');
    final j = it.toJson();
    expect(j['type'], 'password');
    expect(j['title'], 'example.org');
    expect(j.containsKey('website'), isFalse);
    expect(it.purposeId, Item.purposeIdCreate(website: 'example.org', username: 'max'));
  });

  test('card item stores the JSON payload encrypted', () {
    final col = db.collection('users').doc('u1').collection('items');
    const card = CardData(number: '4111', cvv: '123');
    final it = Item.payload(col: col, type: ItemType.card, title: 'Visa', plainJson: card.encode());
    expect(it.value, isNot(contains('4111')));
    expect(CardData.decode(it.decrypted()), card);
    expect(it.purposeId, isNull);
  });

  test('fromSnapshot reads legacy docs (website → title, missing type → password)', () async {
    final legacy = db.collection('users').doc('u1').collection('passwords').doc('p1');
    await legacy.set({'website': 'old.io', 'username': 'a', 'value': 'x', 'iv': 'y', 'v': 2, 'timestamp': DateTime(2024)});
    final it = Item.fromSnapshot(await legacy.get());
    expect(it.type, ItemType.password);
    expect(it.title, 'old.io');
    expect(it.ref, legacy);
  });

  test('push writes to ref and round-trips through fromSnapshot', () async {
    final col = db.collection('users').doc('u1').collection('items');
    final it = Item.payload(col: col, type: ItemType.note, title: 'N', plainJson: const NoteData(text: 't').encode());
    await it.push();
    final back = Item.fromSnapshot(await col.doc(it.id).get());
    expect(back.type, ItemType.note);
    expect(NoteData.decode(back.decrypted()).text, 't');
  });
}
