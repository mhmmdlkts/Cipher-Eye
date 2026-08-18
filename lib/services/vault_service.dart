import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/vault.dart';
import 'crypto_service.dart';
import 'invite_code.dart';
import 'vault_key_store.dart';

class InviteError implements Exception {
  InviteError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Everything about vault membership. Item CRUD inside a vault is
/// ItemRepository's job; this class only deals with vaults, invites and keys.
class VaultService {
  VaultService({
    required this.db,
    required this.uid,
    required this.displayName,
    required VaultKeyStore keys,
  }) : keysStore = keys;

  final FirebaseFirestore db;
  final String uid;
  final String displayName;
  final VaultKeyStore keysStore;

  CollectionReference get vaultsCol => db.collection('vaults');
  DocumentReference _keyDoc(String vaultId) =>
      db.collection('users').doc(uid).collection('vaultKeys').doc(vaultId);

  Future<Vault> create(String name) async {
    final ref = vaultsCol.doc();
    final key = CryptoService.randomKey();
    final vault = Vault(
      id: ref.id,
      name: name.trim(),
      ownerId: uid,
      memberIds: [uid],
      memberNames: {uid: displayName},
      createdAt: Timestamp.now(),
    );
    final batch = db.batch();
    batch.set(ref, vault.toJson());
    batch.set(_keyDoc(ref.id), keysStore.wrap(key));
    await batch.commit();
    keysStore.put(ref.id, key);
    return vault;
  }

  Future<InviteCode> createInvite(Vault vault,
      {Duration ttl = const Duration(days: 7)}) async {
    final key = keysStore.get(vault.id);
    if (key == null) throw InviteError('Tresor-Key nicht verfügbar');
    final code = InviteCode.generate(vault.id, key);
    await vaultsCol
        .doc(vault.id)
        .collection('invites')
        .doc(code.inviteId)
        .set({
      'createdBy': uid,
      'createdAt': Timestamp.now(),
      'expiresAt': Timestamp.fromDate(DateTime.now().add(ttl)),
      'usedBy': null,
      'usedAt': null,
    });
    return code;
  }

  Future<Vault> join(InviteCode code) async {
    final vaultRef = vaultsCol.doc(code.vaultId);
    final invRef = vaultRef.collection('invites').doc(code.inviteId);
    final inv = await invRef.get();
    if (!inv.exists) throw InviteError('Einladung ungültig');
    final data = inv.data() as Map<String, dynamic>;
    if (data['usedBy'] != null) {
      throw InviteError('Einladung wurde bereits verwendet');
    }
    final exp = data['expiresAt'] as Timestamp?;
    if (exp == null || exp.toDate().isBefore(DateTime.now())) {
      throw InviteError('Einladung ist abgelaufen');
    }
    final batch = db.batch();
    batch.update(vaultRef, {
      'memberIds': FieldValue.arrayUnion([uid]),
      'memberNames.$uid': displayName,
      'joinInvite': code.inviteId,
    });
    batch.update(invRef, {'usedBy': uid, 'usedAt': Timestamp.now()});
    batch.set(_keyDoc(code.vaultId), keysStore.wrap(code.vaultKey));
    await batch.commit();
    keysStore.put(code.vaultId, code.vaultKey);
    return Vault.fromSnapshot(await vaultRef.get());
  }

  Future<void> rename(Vault vault, String name) async {
    await vaultsCol.doc(vault.id).update({'name': name.trim()});
    vault.name = name.trim();
  }

  /// Deletes the open invites a member created (used when they leave or are
  /// removed, so their codes cannot be redeemed afterwards).
  Future<void> _revokeInvitesOf(String vaultId, String memberUid) async {
    try {
      final snap = await vaultsCol
          .doc(vaultId)
          .collection('invites')
          .where('createdBy', isEqualTo: memberUid)
          .get();
      for (final d in snap.docs) {
        await d.reference.delete();
      }
    } catch (_) {
      // Rules also refuse invites of non-members; this is belt and braces.
    }
  }

  Future<void> leave(Vault vault) async {
    await _revokeInvitesOf(vault.id, uid);
    final batch = db.batch();
    batch.update(vaultsCol.doc(vault.id), {
      'memberIds': FieldValue.arrayRemove([uid]),
      'memberNames.$uid': FieldValue.delete(),
    });
    batch.delete(_keyDoc(vault.id));
    await batch.commit();
    keysStore.remove(vault.id);
  }

  Future<void> removeMember(Vault vault, String memberUid) async {
    await _revokeInvitesOf(vault.id, memberUid);
    await vaultsCol.doc(vault.id).update({
      'memberIds': FieldValue.arrayRemove([memberUid]),
      'memberNames.$memberUid': FieldValue.delete(),
    });
    vault.memberIds.remove(memberUid);
    vault.memberNames.remove(memberUid);
  }

  /// Deletes the vault with every item, history event and invite in it.
  Future<void> delete(Vault vault) async {
    final ref = vaultsCol.doc(vault.id);
    for (final sub in ['items', 'history', 'invites']) {
      final docs = (await ref.collection(sub).get()).docs;
      for (var i = 0; i < docs.length; i += 400) {
        final batch = db.batch();
        for (final d in docs.skip(i).take(400)) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
    }
    final batch = db.batch();
    batch.delete(ref);
    batch.delete(_keyDoc(vault.id));
    await batch.commit();
    keysStore.remove(vault.id);
  }

  Future<List<Vault>> loadMine() async {
    final snap = await vaultsCol.where('memberIds', arrayContains: uid).get();
    final list = snap.docs.map(Vault.fromSnapshot).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Unwraps every stored key we can; vaults whose key is missing or does not
  /// unwrap (wrong master key) simply stay locked.
  Future<void> loadKeys(List<Vault> vaults) async {
    for (final v in vaults) {
      if (keysStore.get(v.id) != null) continue;
      try {
        final doc = await _keyDoc(v.id).get();
        if (!doc.exists) continue;
        keysStore.put(
            v.id, keysStore.unwrap(doc.data() as Map<String, dynamic>));
      } catch (_) {
        // stays locked
      }
    }
  }
}
