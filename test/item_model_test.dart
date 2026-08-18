import 'package:cipher_eye/models/item.dart';
import 'package:cipher_eye/models/item_payload.dart';
import 'package:cipher_eye/models/item_type.dart';
import 'package:cipher_eye/services/crypto_service.dart';
import 'package:cipher_eye/services/keys.dart';
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

  test('items in a vault use the vault key, not the master key', () {
    final vaultKey = CryptoService.randomKey();
    Keys.resolver = (id) => id == 'v1'
        ? vaultKey
        : CryptoService.keyFromMaster(SecureStorageService.key!);
    addTearDown(() => Keys.resolver = Keys.masterOnly);
    final col = db.collection('vaults').doc('v1').collection('items');
    final it = Item.password(
        col: col, vaultId: 'v1', website: 'w', username: 'u', plainText: 'secret');
    expect(it.decrypted(), 'secret');
    expect(CryptoService.decrypt(value: it.value!, iv: it.iv, v: it.v, key: vaultKey), 'secret');
    expect(
        () => CryptoService.decrypt(value: it.value!, iv: it.iv, v: it.v,
            key: CryptoService.keyFromMaster(SecureStorageService.key!)),
        throwsA(anything));
  });

  test('copyTo re-encrypts for another key and keeps metadata', () {
    final vaultKey = CryptoService.randomKey();
    Keys.resolver = (id) => id == 'v1'
        ? vaultKey
        : CryptoService.keyFromMaster(SecureStorageService.key!);
    addTearDown(() => Keys.resolver = Keys.masterOnly);
    final personal = db.collection('users').doc('u1').collection('items');
    final src = Item.password(col: personal, website: 'w', username: 'u', plainText: 'pw')
      ..copyCount = 3;
    final copy = Item.copyTo(src,
        col: db.collection('vaults').doc('v1').collection('items'),
        vaultId: 'v1', plainText: src.decrypted());
    expect(copy.id, isNot(src.id));
    expect(copy.purposeId, src.purposeId);
    expect(copy.copyCount, 3);
    expect(copy.decrypted(), 'pw');
    expect(CryptoService.decrypt(value: copy.value!, iv: copy.iv, v: copy.v, key: vaultKey), 'pw');
  });
}
