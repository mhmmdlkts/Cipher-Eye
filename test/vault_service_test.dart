import 'package:cipher_eye/services/crypto_service.dart';
import 'package:cipher_eye/services/invite_code.dart';
import 'package:cipher_eye/services/vault_key_store.dart';
import 'package:cipher_eye/services/vault_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore db;
  VaultService svc(String uid) => VaultService(
        db: db,
        uid: uid,
        displayName: 'Name $uid',
        keys: VaultKeyStore(
            masterKey: CryptoService.keyFromMaster(
                'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123$uid'.substring(0, 32))),
      );

  setUp(() => db = FakeFirebaseFirestore());

  test('create → invite → join (2nd and 3rd member) → keys available', () async {
    final a = svc('aaaaaa'), b = svc('bbbbbb'), c = svc('cccccc');
    final vault = await a.create('Oma');
    expect(vault.memberIds, ['aaaaaa']);
    expect(a.keysStore.get(vault.id), isNotNull);
    expect((await db.doc('users/aaaaaa/vaultKeys/${vault.id}').get()).exists, isTrue);

    final inv = await a.createInvite(vault);
    final joined = await b.join(InviteCode.parse(inv.encode())!);
    expect(joined.memberIds, ['aaaaaa', 'bbbbbb']);
    expect(joined.memberNames['bbbbbb'], 'Name bbbbbb');
    expect(b.keysStore.get(vault.id)!.base64, a.keysStore.get(vault.id)!.base64);
    expect((await db.doc('vaults/${vault.id}/invites/${inv.inviteId}').get()).data()!['usedBy'], 'bbbbbb');

    final inv2 = await b.createInvite(vault);
    final joined3 = await c.join(inv2);
    expect(joined3.memberIds, ['aaaaaa', 'bbbbbb', 'cccccc']);
  });

  test('used or expired invites are rejected', () async {
    final a = svc('aaaaaa'), b = svc('bbbbbb'), c = svc('cccccc');
    final vault = await a.create('X');
    final inv = await a.createInvite(vault);
    await b.join(inv);
    expect(() => c.join(inv), throwsA(isA<InviteError>()));
    final expired = await a.createInvite(vault, ttl: const Duration(seconds: -1));
    expect(() => c.join(expired), throwsA(isA<InviteError>()));
  });

  test('leave, removeMember, delete', () async {
    final a = svc('aaaaaa'), b = svc('bbbbbb');
    final vault = await a.create('X');
    await b.join(await a.createInvite(vault));
    await b.leave(vault);
    expect((await a.loadMine()).single.memberIds, ['aaaaaa']);
    expect((await db.doc('users/bbbbbb/vaultKeys/${vault.id}').get()).exists, isFalse);

    await b.join(await a.createInvite(vault));
    await a.removeMember(vault, 'bbbbbb');
    expect((await a.loadMine()).single.memberIds, ['aaaaaa']);

    await db.collection('vaults/${vault.id}/items').add({'title': 't'});
    await a.delete(vault);
    expect((await a.loadMine()), isEmpty);
    expect((await db.collection('vaults/${vault.id}/items').get()).docs, isEmpty);
    expect((await db.doc('users/aaaaaa/vaultKeys/${vault.id}').get()).exists, isFalse);
  });

  test('loadKeys unwraps stored keys with the master key', () async {
    final a = svc('aaaaaa');
    final vault = await a.create('X');
    final fresh = svc('aaaaaa');
    final mine = await fresh.loadMine();
    await fresh.loadKeys(mine);
    expect(fresh.keysStore.get(vault.id)!.base64, a.keysStore.get(vault.id)!.base64);
  });

  test('invites of a removed or leaving member are revoked', () async {
    final a = svc('aaaaaa'), b = svc('bbbbbb'), c = svc('cccccc');
    final vault = await a.create('X');
    await b.join(await a.createInvite(vault));
    final bInvite = await b.createInvite(vault);
    await a.removeMember(vault, 'bbbbbb');
    expect(() => c.join(bInvite), throwsA(isA<InviteError>()));

    await b.join(await a.createInvite(vault));
    final bInvite2 = await b.createInvite(vault);
    await b.leave(vault);
    expect(() => c.join(bInvite2), throwsA(isA<InviteError>()));
  });
}
