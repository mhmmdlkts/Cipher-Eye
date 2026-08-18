import 'package:cipher_eye/services/items_migration_service.dart';
import 'package:cipher_eye/services/person_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore db;
  setUp(() => db = FakeFirebaseFirestore());

  ItemsMigrationService svc() => ItemsMigrationService(
        from: db.collection('users').doc('u').collection('passwords'),
        to: db.collection('users').doc('u').collection('items'),
        profile: db.collection('users').doc('u'),
      );

  test('copies every doc (same id, website→title, type=password), then deletes', () async {
    final from = db.collection('users').doc('u').collection('passwords');
    await from.doc('a').set({'website': 'A', 'username': 'x', 'value': 'v', 'iv': 'i', 'v': 2, 'purposeId': 'p1'});
    await from.doc('b').set({'website': 'B', 'username': 'y', 'value': 'v', 'iv': 'i', 'v': 1, 'isDraft': true});
    expect(await svc().run(), isTrue);
    final to = db.collection('users').doc('u').collection('items');
    final a = (await to.doc('a').get()).data()!;
    expect(a['title'], 'A');
    expect(a['type'], 'password');
    expect(a['purposeId'], 'p1');
    expect(a.containsKey('website'), isFalse);
    expect((await to.doc('b').get()).data()!['isDraft'], true);
    expect((await from.get()).docs, isEmpty);
    expect((await db.collection('users').doc('u').get()).data()!['dataVersion'], PersonService.kDataVersion);
  });

  test('empty legacy collection just bumps the profile', () async {
    expect(await svc().run(), isTrue);
    expect((await db.collection('users').doc('u').get()).data()!['dataVersion'], PersonService.kDataVersion);
  });

  test('is idempotent: rerunning after a completed migration changes nothing', () async {
    final from = db.collection('users').doc('u').collection('passwords');
    await from.doc('a').set({'website': 'A', 'value': 'v', 'iv': 'i', 'v': 2});
    await svc().run();
    await svc().run();
    expect((await db.collection('users').doc('u').collection('items').get()).docs.length, 1);
  });

  test('resumes: copies already present in items are not duplicated, originals removed', () async {
    final from = db.collection('users').doc('u').collection('passwords');
    final to = db.collection('users').doc('u').collection('items');
    await from.doc('a').set({'website': 'A', 'value': 'v', 'iv': 'i', 'v': 2});
    await to.doc('a').set({'title': 'A', 'type': 'password', 'value': 'v', 'iv': 'i', 'v': 2});
    expect(await svc().run(), isTrue);
    expect((await to.get()).docs.length, 1);
    expect((await from.get()).docs, isEmpty);
  });

  test('a resumed run never overwrites an edited copy in items', () async {
    final from = db.collection('users').doc('u').collection('passwords');
    final to = db.collection('users').doc('u').collection('items');
    await from.doc('a').set({'website': 'A', 'value': 'old', 'iv': 'i', 'v': 2});
    await to.doc('a').set({'title': 'A', 'type': 'password', 'value': 'edited', 'iv': 'j', 'v': 2, 'isFavorite': true});
    await svc().run();
    final data = (await to.doc('a').get()).data()!;
    expect(data['value'], 'edited');
    expect(data['isFavorite'], true);
    expect((await from.get()).docs, isEmpty);
  });

  test('bumpProfile=false leaves the profile untouched', () async {
    await svc().run(bumpProfile: false);
    expect((await db.collection('users').doc('u').get()).exists, isFalse);
  });
}
