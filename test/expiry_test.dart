import 'package:cipher_eye/models/item.dart';
import 'package:cipher_eye/models/item_payload.dart';
import 'package:cipher_eye/models/item_type.dart';
import 'package:cipher_eye/services/expiry.dart';
import 'package:cipher_eye/services/item_repository.dart';
import 'package:cipher_eye/services/secure_storage_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore db;
  final now = DateTime(2026, 8, 19);
  setUp(() {
    SecureStorageService.key = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ012345';
    db = FakeFirebaseFirestore();
    Expiry.clearCache();
  });

  Item doc(String? expires) => Item.payload(
      col: db.collection('users').doc('u').collection('items'),
      type: ItemType.document,
      title: 'Pass',
      plainJson: DocumentData(docType: DocType.passport, expires: expires).encode());

  test('levels: none / soon / critical / expired', () {
    expect(Expiry.of(doc('01.01.2030'), now: now).level, ExpiryLevel.none);
    expect(Expiry.of(doc('01.11.2026'), now: now).level, ExpiryLevel.soon);
    expect(Expiry.of(doc('25.08.2026'), now: now).level, ExpiryLevel.critical);
    expect(Expiry.of(doc('01.08.2026'), now: now).level, ExpiryLevel.expired);
    expect(Expiry.of(doc(null), now: now).level, ExpiryLevel.none);
    expect(Expiry.of(doc('kaputt'), now: now).level, ExpiryLevel.none);
  });

  test('labels are human', () {
    expect(Expiry.of(doc('20.08.2026'), now: now).label, 'Läuft morgen ab');
    expect(Expiry.of(doc('19.08.2026'), now: now).label, 'Läuft heute ab');
    expect(Expiry.of(doc('10.08.2026'), now: now).label, 'Abgelaufen seit 9 Tagen');
    expect(Expiry.of(doc('01.11.2026'), now: now).label, 'Läuft in 2 Monaten ab');
  });

  test('card expiry MM/YY means end of month', () {
    final card = Item.payload(
        col: db.collection('users').doc('u').collection('items'),
        type: ItemType.card,
        title: 'Visa',
        plainJson: const CardData(expiry: '08/26').encode());
    final info = Expiry.of(card, now: now);
    expect(info.date, DateTime(2026, 8, 31));
    expect(info.level, ExpiryLevel.critical);
  });

  test('acknowledgement is bound to the expiry string', () {
    final d = doc('01.11.2026');
    final info = Expiry.of(d, now: now);
    expect(Expiry.isAcked(d, info), isFalse);
    d.expiryAck = Expiry.ackHash(d, info.raw!);
    expect(Expiry.isAcked(d, info), isTrue);
    d.setPayload(title: 'Pass', plainJson: const DocumentData(expires: '01.12.2026').encode());
    expect(Expiry.isAcked(d, Expiry.of(d, now: now)), isFalse);
  });

  test('renewal archives the old item and links both ways', () async {
    final repo = ItemRepository(db.collection('users').doc('u').collection('items'), history: (_, __) {});
    final old = doc('01.08.2026');
    await repo.add(old);
    final fresh = doc('01.08.2036')..predecessorId = old.id;
    await repo.save(fresh);
    old.archived = true;
    old.supersededBy = fresh.id;
    await repo.save(old);
    final again = ItemRepository(repo.col, history: (_, __) {});
    await again.load();
    expect(again.latest.map((i) => i.id), [fresh.id]);
    expect(again.predecessorsOf(again.byId(fresh.id!)!).map((i) => i.id), [old.id]);
    expect(again.byId(old.id!)!.archived, isTrue);
  });

  test('deleting the successor restores the archived predecessor', () async {
    final repo = ItemRepository(db.collection('users').doc('u').collection('items'), history: (_, __) {});
    final old = doc('01.08.2026');
    await repo.add(old);
    final fresh = doc('01.08.2036')..predecessorId = old.id;
    await repo.save(fresh);
    old.archived = true;
    old.supersededBy = fresh.id;
    await repo.save(old);
    await repo.delete(fresh);
    expect(repo.latest.map((i) => i.id), [old.id]);
    expect(((await repo.col.doc(old.id).get()).data()! as Map)['archived'], false);
  });
}
