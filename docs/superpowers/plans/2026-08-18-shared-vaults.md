# Gemeinsame Tresore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let several accounts co-manage items in shared vaults, end-to-end encrypted with a per-vault key that only travels inside an invite code/QR.

**Architecture:** A `Vault` document (name, owner, members) with `items`, `history` and `invites` sub-collections. Items are encrypted with the vault key via the existing `CryptoService`; `Item` resolves its key through a pluggable `KeyResolver` keyed by `vaultId`. Vault keys are wrapped with the master key in `users/{uid}/vaultKeys`. `ItemService` holds one `ItemRepository` per source (personal + each vault) and the UI filters by source. Firestore rules gate membership and joins.

**Tech Stack:** Flutter, Riverpod 2, cloud_firestore 6, encrypt (AES-GCM), crypto (sha256), qr_flutter (QR display), mobile_scanner (QR scan), fake_cloud_firestore (tests).

**Spec:** `docs/superpowers/specs/2026-08-18-shared-vaults-design.md`

## Execution order

1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11. Rules (Task 1) must be deployed by the user before the app is run against real Firestore; every other task is testable with `fake_cloud_firestore`.

## Global Constraints

- Vault key: 32 random bytes; items encrypted AES-256-GCM (`CryptoService`), `v = 2`.
- The vault key is never stored in plaintext server-side: only master-key-wrapped in `users/{uid}/vaultKeys/{vaultId}` and inside the invite code.
- Invite code format `ce1.<vaultId>.<secretB64url>.<keyB64url>`; Firestore holds only `sha256(secret)` as invite doc id; single use; 7-day expiry.
- All members may create/edit/delete items; only the owner renames, removes members, deletes the vault. Members can leave.
- German UI strings, English code comments, no AI markers. `flutter analyze` clean and `flutter test` green before every commit.

---

### Task 1: Firestore rules for vaults + vaultKeys

**Files:**
- Modify: `firestore.rules`

- [ ] **Step 1: Add the vault rules** (inside `match /databases/{database}/documents { … }`, after the `users` blocks)

```
    // ---- Shared vaults ---------------------------------------------------
    function vaultDoc(vaultId) {
      return get(/databases/$(database)/documents/vaults/$(vaultId)).data;
    }
    function isVaultMember(vaultId) {
      return isAuthenticated() && request.auth.uid in vaultDoc(vaultId).memberIds;
    }

    match /vaults/{vaultId} {
      function isMemberOfThis() {
        return request.auth.uid in resource.data.memberIds;
      }
      function isOwnerOfThis() {
        return resource.data.ownerId == request.auth.uid;
      }
      function changedOnly(keys) {
        return request.resource.data.diff(resource.data).affectedKeys().hasOnly(keys);
      }
      // A join adds exactly the caller to memberIds/memberNames and names a
      // valid, unused invite (doc id = sha256 of the secret in the code).
      function isValidJoin() {
        let inv = get(/databases/$(database)/documents/vaults/$(vaultId)/invites/$(request.resource.data.joinInvite));
        return changedOnly(['memberIds', 'memberNames', 'joinInvite'])
          && !(request.auth.uid in resource.data.memberIds)
          && request.resource.data.memberIds == resource.data.memberIds.concat([request.auth.uid])
          && request.resource.data.memberNames.diff(resource.data.memberNames).affectedKeys().hasOnly([request.auth.uid])
          && inv != null
          && inv.data.usedBy == null
          && inv.data.expiresAt > request.time;
      }
      function isSelfLeave() {
        return changedOnly(['memberIds', 'memberNames'])
          && !isOwnerOfThis()
          && request.resource.data.memberIds == resource.data.memberIds.removeAll([request.auth.uid])
          && request.resource.data.memberNames.diff(resource.data.memberNames).affectedKeys().hasOnly([request.auth.uid]);
      }

      allow get: if isAuthenticated() && isMemberOfThis();
      allow list: if isAuthenticated() && isMemberOfThis();
      allow create: if isAuthenticated()
        && request.resource.data.ownerId == request.auth.uid
        && request.resource.data.memberIds == [request.auth.uid];
      allow update: if isAuthenticated() && (
        (isOwnerOfThis() && request.resource.data.ownerId == resource.data.ownerId)
        || isSelfLeave()
        || isValidJoin());
      allow delete: if isAuthenticated() && isOwnerOfThis();

      match /items/{itemId} {
        allow read, write: if isVaultMember(vaultId);
      }
      match /history/{eventId} {
        allow create, read: if isVaultMember(vaultId);
        allow update, delete: if false;
      }
      match /invites/{inviteId} {
        allow create: if isVaultMember(vaultId)
          && request.resource.data.createdBy == request.auth.uid
          && request.resource.data.usedBy == null;
        // Anyone who knows the (secret-derived) id may read a single invite;
        // listing stays members-only.
        allow get: if isAuthenticated();
        allow list: if isVaultMember(vaultId);
        // Redeeming: the joiner stamps usedBy/usedAt exactly once.
        allow update: if isAuthenticated()
          && resource.data.usedBy == null
          && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['usedBy', 'usedAt'])
          && request.resource.data.usedBy == request.auth.uid;
        allow delete: if isVaultMember(vaultId);
      }
    }

    // Wrapped vault keys: only the user themselves.
    match /users/{userId}/vaultKeys/{vaultId} {
      allow read, write: if isAuthenticated() && isOwner(userId);
    }
```

- [ ] **Step 2: Deploy** (user runs it; the sandbox cannot): `firebase deploy --only firestore:rules`. Verify in the console's Rules Playground: member `get /vaults/x` allowed, non-member denied; non-member `update` with a valid `joinInvite` allowed.

- [ ] **Step 3: Commit**

```bash
git add firestore.rules
git commit -m "Firestore rules for shared vaults, invites and wrapped vault keys"
```

---

### Task 2: `Vault` model, invite code, key wrapping

**Files:**
- Create: `lib/models/vault.dart`
- Create: `lib/services/invite_code.dart`
- Create: `lib/services/vault_key_store.dart`
- Test: `test/invite_code_test.dart`, `test/vault_key_wrap_test.dart`

**Interfaces:**
```dart
class Vault {
  String id; String name; String ownerId; List<String> memberIds; Map<String,String> memberNames;
  Timestamp? createdAt; int keyVersion;
  Vault.fromSnapshot(DocumentSnapshot); Map<String,dynamic> toJson();
  bool isOwner(String uid); int get memberCount;
}
class InviteCode {
  InviteCode({required this.vaultId, required this.secret, required this.key}); // Uint8List secret (32), Uint8List key (32)
  static InviteCode generate(String vaultId, Key vaultKey);
  String encode();                       // 'ce1.<vaultId>.<b64url secret>.<b64url key>'
  static InviteCode? parse(String text); // null on any format error
  String get inviteId;                   // sha256(secret) hex
  Key get vaultKey;
}
class VaultKeyStore {
  VaultKeyStore({required this.masterKey});                 // Key
  Map<String, dynamic> wrap(Key vaultKey);                  // {value, iv, v}
  Key unwrap(Map<String, dynamic> doc);                     // throws on wrong master key
  void put(String vaultId, Key key); Key? get(String vaultId); void remove(String vaultId); void clear();
}
```

- [ ] **Step 1: Failing tests**

```dart
// test/invite_code_test.dart
import 'package:cipher_eye/services/crypto_service.dart';
import 'package:cipher_eye/services/invite_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encode/parse round-trip', () {
    final key = CryptoService.randomKey();
    final inv = InviteCode.generate('v123', key);
    final text = inv.encode();
    expect(text.startsWith('ce1.v123.'), isTrue);
    final back = InviteCode.parse(text)!;
    expect(back.vaultId, 'v123');
    expect(back.vaultKey.base64, key.base64);
    expect(back.inviteId, inv.inviteId);
    expect(back.inviteId.length, 64);
  });

  test('parse tolerates surrounding whitespace and rejects garbage', () {
    final inv = InviteCode.generate('v', CryptoService.randomKey());
    expect(InviteCode.parse('  ${inv.encode()}\n'), isNotNull);
    expect(InviteCode.parse('ce1.v.abc'), isNull);
    expect(InviteCode.parse('ce2.v.a.b'), isNull);
    expect(InviteCode.parse(''), isNull);
    expect(InviteCode.parse('ce1.v.${'A' * 43}.short'), isNull);
  });

  test('two invites for the same vault differ in secret but share the key', () {
    final key = CryptoService.randomKey();
    final a = InviteCode.generate('v', key), b = InviteCode.generate('v', key);
    expect(a.inviteId, isNot(b.inviteId));
    expect(a.vaultKey.base64, b.vaultKey.base64);
  });
}
```

```dart
// test/vault_key_wrap_test.dart
import 'package:cipher_eye/services/crypto_service.dart';
import 'package:cipher_eye/services/vault_key_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wrap/unwrap round-trip with the master key', () {
    final store = VaultKeyStore(masterKey: CryptoService.keyFromMaster('ABCDEFGHIJKLMNOPQRSTUVWXYZ012345'));
    final vk = CryptoService.randomKey();
    final doc = store.wrap(vk);
    expect(doc['v'], 2);
    expect(doc['value'], isNot(contains(vk.base64)));
    expect(store.unwrap(doc).base64, vk.base64);
  });

  test('wrong master key fails to unwrap', () {
    final a = VaultKeyStore(masterKey: CryptoService.keyFromMaster('ABCDEFGHIJKLMNOPQRSTUVWXYZ012345'));
    final b = VaultKeyStore(masterKey: CryptoService.keyFromMaster('ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ'));
    final doc = a.wrap(CryptoService.randomKey());
    expect(() => b.unwrap(doc), throwsA(anything));
  });

  test('in-memory map', () {
    final store = VaultKeyStore(masterKey: CryptoService.randomKey());
    final k = CryptoService.randomKey();
    store.put('v', k);
    expect(store.get('v')!.base64, k.base64);
    store.remove('v');
    expect(store.get('v'), isNull);
  });
}
```

- [ ] **Step 2: Run → FAIL. Implement**

```dart
// lib/models/vault.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Vault {
  Vault({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.memberIds,
    Map<String, String>? memberNames,
    this.createdAt,
    this.keyVersion = 1,
  }) : memberNames = memberNames ?? {};

  final String id;
  String name;
  final String ownerId;
  List<String> memberIds;
  Map<String, String> memberNames;
  Timestamp? createdAt;
  int keyVersion;

  bool isOwner(String uid) => ownerId == uid;
  int get memberCount => memberIds.length;
  String nameOf(String uid) => memberNames[uid] ?? uid.substring(0, 6);

  factory Vault.fromSnapshot(DocumentSnapshot<Object?> snap) {
    final o = (snap.data() as Map<String, dynamic>?) ?? {};
    return Vault(
      id: snap.id,
      name: (o['name'] as String?) ?? '',
      ownerId: (o['ownerId'] as String?) ?? '',
      memberIds: List<String>.from(o['memberIds'] as List? ?? const []),
      memberNames: Map<String, String>.from(o['memberNames'] as Map? ?? const {}),
      createdAt: o['createdAt'] as Timestamp?,
      keyVersion: (o['keyVersion'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'ownerId': ownerId,
        'memberIds': memberIds,
        'memberNames': memberNames,
        'createdAt': createdAt ?? FieldValue.serverTimestamp(),
        'keyVersion': keyVersion,
      };
}
```

```dart
// lib/services/invite_code.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

/// The only place the vault key travels: `ce1.<vaultId>.<secret>.<key>`
/// (base64url, no padding). Firestore stores just sha256(secret) as the
/// invite's document id, so possession of the code proves the invite.
class InviteCode {
  InviteCode({required this.vaultId, required this.secret, required this.key});

  static const String _prefix = 'ce1';
  final String vaultId;
  final Uint8List secret;
  final Uint8List key;

  static InviteCode generate(String vaultId, Key vaultKey) => InviteCode(
        vaultId: vaultId,
        secret: SecureRandom(32).bytes,
        key: Uint8List.fromList(vaultKey.bytes),
      );

  String encode() => [_prefix, vaultId, _b64(secret), _b64(key)].join('.');

  static InviteCode? parse(String text) {
    final parts = text.trim().split('.');
    if (parts.length != 4 || parts[0] != _prefix || parts[1].isEmpty) return null;
    try {
      final secret = _unb64(parts[2]);
      final key = _unb64(parts[3]);
      if (secret.length != 32 || key.length != 32) return null;
      return InviteCode(vaultId: parts[1], secret: secret, key: key);
    } catch (_) {
      return null;
    }
  }

  String get inviteId => sha256.convert(secret).toString();
  Key get vaultKey => Key(key);

  static String _b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');
  static Uint8List _unb64(String s) =>
      base64Url.decode(s.padRight(s.length + (4 - s.length % 4) % 4, '='));
}
```

```dart
// lib/services/vault_key_store.dart
import 'package:encrypt/encrypt.dart';

import 'crypto_service.dart';

/// Holds unwrapped vault keys for the session and wraps/unwraps them with the
/// master key for storage in users/{uid}/vaultKeys.
class VaultKeyStore {
  VaultKeyStore({required this.masterKey});

  final Key masterKey;
  final Map<String, Key> _keys = {};

  Map<String, dynamic> wrap(Key vaultKey) {
    final e = CryptoService.encrypt(vaultKey.base64, masterKey);
    return {'value': e.value, 'iv': e.iv, 'v': CryptoService.kVersion};
  }

  Key unwrap(Map<String, dynamic> doc) => Key.fromBase64(CryptoService.decrypt(
        value: doc['value'] as String,
        iv: doc['iv'] as String?,
        v: (doc['v'] as num?)?.toInt(),
        key: masterKey,
      ));

  void put(String vaultId, Key key) => _keys[vaultId] = key;
  Key? get(String vaultId) => _keys[vaultId];
  void remove(String vaultId) => _keys.remove(vaultId);
  void clear() => _keys.clear();
  Iterable<String> get vaultIds => _keys.keys;
}
```

- [ ] **Step 3: Run tests → PASS. Commit**

```bash
git add lib/models/vault.dart lib/services/invite_code.dart lib/services/vault_key_store.dart test/invite_code_test.dart test/vault_key_wrap_test.dart
git commit -m "Vault model, invite code format, master-key wrapping of vault keys"
```

---

### Task 3: Per-source keys — `KeyResolver` in `Item`

**Files:**
- Create: `lib/services/keys.dart`
- Modify: `lib/models/item.dart` (`vaultId` field, use `Keys.resolve(vaultId)` for encrypt/decrypt)
- Modify: `lib/services/item_repository.dart` (`vaultId` ctor arg, stamped on every loaded item)
- Test: extend `test/item_model_test.dart`

**Interfaces:**
```dart
typedef KeyResolver = Key Function(String? vaultId);
class Keys {
  static KeyResolver resolver = masterOnly;          // swapped by ItemService in Task 5
  static Key masterOnly(String? vaultId);            // throws StateError for non-null vaultId
  static Key resolve(String? vaultId) => resolver(vaultId);
}
// Item: String? vaultId;  Item.password/draft/payload gain `String? vaultId` param.
// ItemRepository(col, {vaultId, history})  → item.vaultId = vaultId on load/add.
```

- [ ] **Step 1: Failing test** (append to `test/item_model_test.dart`)

```dart
  test('items in a vault use the vault key, not the master key', () {
    final vaultKey = CryptoService.randomKey();
    Keys.resolver = (id) => id == 'v1' ? vaultKey : CryptoService.keyFromMaster(SecureStorageService.key!);
    addTearDown(() => Keys.resolver = Keys.masterOnly);
    final col = db.collection('vaults').doc('v1').collection('items');
    final it = Item.password(col: col, vaultId: 'v1', website: 'w', username: 'u', plainText: 'secret');
    expect(it.decrypted(), 'secret');
    expect(CryptoService.decrypt(value: it.value!, iv: it.iv, v: it.v, key: vaultKey), 'secret');
    expect(() => CryptoService.decrypt(value: it.value!, iv: it.iv, v: it.v,
        key: CryptoService.keyFromMaster(SecureStorageService.key!)), throwsA(anything));
  });
```
(add imports `package:cipher_eye/services/crypto_service.dart`, `package:cipher_eye/services/keys.dart`).

- [ ] **Step 2: Implement**

```dart
// lib/services/keys.dart
import 'package:encrypt/encrypt.dart';

import 'crypto_service.dart';
import 'secure_storage_service.dart';

typedef KeyResolver = Key Function(String? vaultId);

/// Which AES key an item uses: the master key for personal items
/// (`vaultId == null`), the vault key for shared ones. The resolver is
/// installed by ItemService once vault keys are loaded.
class Keys {
  static KeyResolver resolver = masterOnly;

  static Key masterOnly(String? vaultId) {
    if (vaultId != null) {
      throw StateError('Vault key for $vaultId is not available');
    }
    final k = SecureStorageService.key;
    if (k == null) throw StateError('Encryption key is not set');
    return CryptoService.keyFromMaster(k);
  }

  static Key resolve(String? vaultId) => resolver(vaultId);
}
```

In `lib/models/item.dart`:
- add `String? vaultId;` (runtime only — never in `toJson`).
- constructors `Item.password/draft/payload` get `this.vaultId` as optional named parameter.
- `_encrypt`: `final e = CryptoService.encrypt(plain, Keys.resolve(vaultId)); value = e.value; iv = e.iv; v = CryptoService.kVersion;`
- `decrypted()`, `getPlainText()`, `migrateCrypto()`: use `CryptoService.decrypt(value: value!, iv: iv, v: v, key: Keys.resolve(vaultId))` and `CryptoService.encrypt(plain, Keys.resolve(vaultId))`; `needsMigration` compares with `CryptoService.kVersion`.
- imports: `../services/crypto_service.dart`, `../services/keys.dart`; drop `password_service.dart`.

In `lib/services/item_repository.dart`: constructor `ItemRepository(this.col, {this.vaultId, HistoryLogger? history})`, field `final String? vaultId;`; in `load()` after `Item.fromSnapshot(d)` set `..vaultId = vaultId`; in `add/updateVersion/save` set `item.vaultId = vaultId` before pushing.

`PasswordService.encode/decode` stay (settings/migration use them) but now simply call `CryptoService` with `Keys.masterOnly(null)`.

- [ ] **Step 3: analyze + test → green. Commit**

```bash
git add lib/services/keys.dart lib/models/item.dart lib/services/item_repository.dart lib/services/password_service.dart test/item_model_test.dart
git commit -m "Items resolve their AES key per source (master vs vault key)"
```

---

### Task 4: `VaultService` (create, invite, join, leave, remove, delete)

**Files:**
- Create: `lib/services/vault_service.dart`
- Test: `test/vault_service_test.dart`

**Interfaces:**
```dart
class VaultService {
  VaultService({required FirebaseFirestore db, required String uid, required String displayName, required VaultKeyStore keys});
  CollectionReference get vaultsCol;                                  // db.collection('vaults')
  Future<Vault> create(String name);                                  // random key, wrapped key doc, member = creator
  Future<InviteCode> createInvite(Vault vault, {Duration ttl = const Duration(days: 7)});
  Future<Vault> join(InviteCode code);                                // batch: vault update + invite usedBy + vaultKeys
  Future<void> rename(Vault vault, String name);
  Future<void> leave(Vault vault);
  Future<void> removeMember(Vault vault, String memberUid);
  Future<void> delete(Vault vault);                                   // items, history, invites, vault, own vaultKeys
  Future<List<Vault>> loadMine();                                     // memberIds arrayContains uid
  Future<void> loadKeys(List<Vault> vaults);                          // unwrap users/{uid}/vaultKeys into keys store
}
class InviteError implements Exception { final String message; }
```

- [ ] **Step 1: Failing test**

```dart
// test/vault_service_test.dart
import 'package:cipher_eye/services/crypto_service.dart';
import 'package:cipher_eye/services/invite_code.dart';
import 'package:cipher_eye/services/vault_key_store.dart';
import 'package:cipher_eye/services/vault_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore db;
  VaultService svc(String uid) => VaultService(
        db: db, uid: uid, displayName: 'Name $uid',
        keys: VaultKeyStore(masterKey: CryptoService.keyFromMaster('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123$uid'.substring(0, 32))));

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
}
```

- [ ] **Step 2: Implement**

```dart
// lib/services/vault_service.dart
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
      id: ref.id, name: name.trim(), ownerId: uid, memberIds: [uid],
      memberNames: {uid: displayName}, createdAt: Timestamp.now(),
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
    await vaultsCol.doc(vault.id).collection('invites').doc(code.inviteId).set({
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
    if (data['usedBy'] != null) throw InviteError('Einladung wurde bereits verwendet');
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

  Future<void> leave(Vault vault) async {
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
    await vaultsCol.doc(vault.id).update({
      'memberIds': FieldValue.arrayRemove([memberUid]),
      'memberNames.$memberUid': FieldValue.delete(),
    });
    vault.memberIds.remove(memberUid);
    vault.memberNames.remove(memberUid);
  }

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
        keysStore.put(v.id, keysStore.unwrap(doc.data() as Map<String, dynamic>));
      } catch (_) {
        // stays locked
      }
    }
  }
}
```

- [ ] **Step 3: analyze + test → green. Commit**

```bash
git add lib/services/vault_service.dart test/vault_service_test.dart
git commit -m "VaultService: create, invite, join, leave, remove, delete, key loading"
```

---

### Task 5: `ItemService` with multiple sources; vault history

**Files:**
- Modify: `lib/services/item_service.dart`
- Modify: `lib/services/history_service.dart`, `lib/models/history.dart` (vault history target + `uid`/`displayName`)
- Modify: `lib/providers/history_provider.dart` (family key includes vaultId)
- Modify: `lib/services/init_service.dart` (`ItemService.init()` already called; nothing else)

**Interfaces:**
```dart
class ItemService {
  static late ItemRepository personal;
  static final Map<String, ItemRepository> vaultRepos = {};   // vaultId → repo
  static List<Vault> vaults = [];
  static late VaultService vaultService;                        // built in init()
  static bool isLocked(String vaultId);                          // no key
  static Iterable<ItemRepository> get repos;                    // personal + unlocked vaults
  static List<Item> get items / latest / drafts;                // union over repos
  static ItemRepository repoFor(String? vaultId);
  static Future<void> init();                                   // personal (as before) + vaults + keys + resolver
  static Future<void> reloadVaults();                           // after create/join/leave/delete or pull-to-refresh
  static Future<void> incrementUsage(String itemId, {required bool copy});
  static Future<Item> move(Item item, String? toVaultId);       // re-encrypt + move (all versions for passwords)
}
// History: History.create({required action, password, String? vaultId}) → writes to vaults/{id}/history when vaultId != null, includes uid + displayName.
// HistoryService.saveXHistory(String itemId, {String? vaultId})
// passwordHistoryProvider: family<List<History>, ({String? vaultId, String itemId})>
```

- [ ] **Step 1: Implement `ItemService`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/item.dart';
import '../models/item_type.dart';
import '../models/vault.dart';
import 'crypto_service.dart';
import 'firestore_paths_service.dart';
import 'history_service.dart';
import 'item_repository.dart';
import 'items_migration_service.dart';
import 'keys.dart';
import 'person_service.dart';
import 'secure_storage_service.dart';
import 'vault_key_store.dart';
import 'vault_service.dart';

class ItemService {
  static late ItemRepository personal;
  static final Map<String, ItemRepository> vaultRepos = {};
  static List<Vault> vaults = [];
  static late VaultService vaultService;
  static VaultKeyStore? _keys;

  static bool isLocked(String vaultId) => _keys?.get(vaultId) == null;

  static Iterable<ItemRepository> get repos => [personal, ...vaultRepos.values];
  static List<Item> get items => [for (final r in repos) ...r.items];
  static List<Item> get latest => [for (final r in repos) ...r.latest];
  static List<Item> get drafts => [for (final r in repos) ...r.drafts];
  static List<Item> versionsOf(String purposeId, {String? vaultId}) =>
      repoFor(vaultId).versionsOf(purposeId);
  static void maskAll() { for (final r in repos) { r.maskAll(); } }

  static ItemRepository repoFor(String? vaultId) =>
      vaultId == null ? personal : vaultRepos[vaultId]!;

  static Vault? vaultById(String? id) =>
      id == null ? null : vaults.where((v) => v.id == id).firstOrNull;

  static Future<void> init() async {
    // --- personal (unchanged from the items plan) ---
    personal = ItemRepository(FirestorePathsService.getItemsCol());
    var migrated = PersonService.person.dataVersion >= PersonService.kDataVersion;
    if (!migrated) {
      try {
        await ItemsMigrationService(
          from: FirestorePathsService.getPasswordCol(),
          to: FirestorePathsService.getItemsCol(),
          profile: FirestorePathsService.getUserDoc(),
        ).run();
        PersonService.person.dataVersion = PersonService.kDataVersion;
        migrated = true;
      } catch (_) {}
    }
    await personal.load(
        extraSources: migrated ? const [] : [FirestorePathsService.getPasswordCol()]);

    // --- vaults ---
    await reloadVaults();
  }

  /// (Re)builds the vault service, key store, resolver and per-vault repos.
  /// Safe to call any time (after join/leave, pull-to-refresh, key change).
  static Future<void> reloadVaults() async {
    final master = SecureStorageService.key;
    final user = FirebaseAuth.instance.currentUser!;
    _keys = master == null ? null : VaultKeyStore(masterKey: CryptoService.keyFromMaster(master));
    Keys.resolver = (vaultId) {
      if (vaultId == null) return Keys.masterOnly(null);
      final k = _keys?.get(vaultId);
      if (k == null) throw StateError('Vault $vaultId is locked');
      return k;
    };
    vaultService = VaultService(
      db: FirebaseFirestore.instance,
      uid: user.uid,
      displayName: PersonService.person.name ?? user.email ?? user.uid,
      keys: _keys ?? VaultKeyStore(masterKey: CryptoService.randomKey()),
    );
    vaults = await vaultService.loadMine();
    if (_keys != null) await vaultService.loadKeys(vaults);
    vaultRepos.clear();
    for (final v in vaults) {
      if (isLocked(v.id)) continue;
      final repo = ItemRepository(
        vaultService.vaultsCol.doc(v.id).collection('items'),
        vaultId: v.id,
        history: (action, id) => HistoryService.log(action, id, vaultId: v.id),
      );
      await repo.load();
      vaultRepos[v.id] = repo;
    }
  }

  static Future<void> incrementUsage(String itemId, {required bool copy}) {
    final item = items.firstWhere((i) => i.id == itemId);
    return repoFor(item.vaultId).incrementUsage(item, copy: copy);
  }

  /// Moves an item (all versions for passwords) to another source: decrypt
  /// with the source key, encrypt with the target key, write, delete source.
  static Future<Item> move(Item item, String? toVaultId) async {
    if (item.vaultId == toVaultId) return item;
    final from = repoFor(item.vaultId);
    final to = repoFor(toVaultId);
    final versions = item.type == ItemType.password && !item.isDraft
        ? from.versionsOf(item.purposeId!)
        : [item];
    Item? moved;
    for (final v in versions) {
      final plain = v.decrypted();
      final copy = Item.copyTo(v, col: to.col, vaultId: toVaultId, plainText: plain);
      await to.save(copy);
      if (v.id == item.id) moved = copy;
    }
    await from.delete(item);          // removes every version for passwords
    return moved!;
  }
}
```
Add to `Item`:
```dart
  /// Same content, re-encrypted for another collection/key. Keeps title,
  /// username, purposeId, timestamps, flags and counters; new document id.
  Item.copyTo(Item src, {required CollectionReference col, required String? vaultId, required String plainText}) {
    ref = col.doc();
    id = ref!.id;
    this.vaultId = vaultId;
    type = src.type;
    title = src.title;
    username = src.username;
    purposeId = src.purposeId;
    timestamp = src.timestamp;
    updatedAt = src.updatedAt;
    isFavorite = src.isFavorite;
    isDraft = src.isDraft;
    copyCount = src.copyCount;
    viewCount = src.viewCount;
    attachments = List.of(src.attachments);
    _encrypt(plainText);
  }
```
(`copyCount/viewCount` must then also be written by `toJson` — add `'copyCount': copyCount, 'viewCount': viewCount` to the map.)

- [ ] **Step 2: History with vault target**

`lib/models/history.dart`: `History.create({required this.action, this.password, this.vaultId})` → `id = _col().doc().id`, add fields `String? vaultId; String? displayName;`, `_col()` = `vaultId == null ? FirestorePathsService.getHistoryCol() : FirebaseFirestore.instance.collection('vaults').doc(vaultId!).collection('history')`; `toJson` adds `'uid': uid, 'displayName': displayName`; `push()` → `_col().doc(id!).set(toJson())`; `fromSnapshot` reads `uid`, `displayName`. Set `displayName = PersonService.person.name` in `create` (import person_service).

`lib/services/history_service.dart`: every `saveXHistory(String id)` becomes `saveXHistory(String id, {String? vaultId})` passing it to `History.create`; add
```dart
  static void log(String action, String itemId, {String? vaultId}) {
    switch (action) {
      case 'create': saveCreateHistory(itemId, vaultId: vaultId);
      case 'update': saveUpdateHistory(itemId, vaultId: vaultId);
      case 'delete': saveDeleteHistory(itemId, vaultId: vaultId);
    }
  }
```
`ItemRepository._defaultHistory` → `HistoryService.log(action, itemId)`.

`lib/providers/history_provider.dart`:
```dart
typedef HistoryKey = ({String? vaultId, String itemId});
final passwordHistoryProvider = FutureProvider.family<List<History>, HistoryKey>((ref, key) async {
  final col = key.vaultId == null
      ? FirestorePathsService.getHistoryCol()
      : FirebaseFirestore.instance.collection('vaults').doc(key.vaultId).collection('history');
  final snap = await col.where('password', isEqualTo: key.itemId).get();
  … (sort as before)
});
```
Update the callers in `password_detail_screen.dart` (`passwordHistoryProvider((vaultId: pass.vaultId, itemId: pass.id!))`) and pass `vaultId: pass.vaultId` to every `HistoryService.saveXHistory` call in `home_page.dart`, `password_detail_screen.dart`, `item_detail_screen.dart`, `add_new_password_screen.dart`, and `Item.getPlainText()`.

- [ ] **Step 3: analyze + test → green (existing repository tests pass `history:` explicitly). Commit**

```bash
git add lib/services lib/models lib/providers lib/screens
git commit -m "ItemService spans personal + vault repositories; vault-scoped history; move between sources"
```

---

### Task 6: Providers for vaults and the source filter

**Files:**
- Create: `lib/providers/vaults_provider.dart`
- Modify: `lib/providers/items_provider.dart` (`reloadVaults()`, `move()`, `save` on the right repo)

**Interfaces:**
```dart
final vaultsProvider = NotifierProvider<VaultsNotifier, List<Vault>>;   // state = ItemService.vaults
class VaultsNotifier { Future<void> refresh(); Future<Vault> create(String name); Future<Vault> join(InviteCode); Future<void> leave(Vault); Future<void> removeMember(Vault, String uid); Future<void> rename(Vault, String); Future<void> delete(Vault); }
/// null = all sources, 'personal' = personal only, otherwise a vaultId.
final sourceFilterProvider = StateProvider<String?>((_) => null);
final filteredItemsProvider = Provider<List<Item>>(...);   // itemsProvider filtered by sourceFilterProvider
```

- [ ] **Step 1: Implement**

```dart
// lib/providers/vaults_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../models/vault.dart';
import '../services/invite_code.dart';
import '../services/item_service.dart';
import 'items_provider.dart';

class VaultsNotifier extends Notifier<List<Vault>> {
  @override
  List<Vault> build() => List.of(ItemService.vaults);

  Future<void> refresh() async {
    await ItemService.reloadVaults();
    state = List.of(ItemService.vaults);
    ref.read(itemsProvider.notifier).refresh();
  }

  Future<Vault> create(String name) async {
    final v = await ItemService.vaultService.create(name);
    await refresh();
    return v;
  }

  Future<Vault> join(InviteCode code) async {
    final v = await ItemService.vaultService.join(code);
    await refresh();
    return v;
  }

  Future<void> leave(Vault v) async { await ItemService.vaultService.leave(v); await refresh(); }
  Future<void> removeMember(Vault v, String uid) async { await ItemService.vaultService.removeMember(v, uid); await refresh(); }
  Future<void> rename(Vault v, String name) async { await ItemService.vaultService.rename(v, name); await refresh(); }
  Future<void> delete(Vault v) async { await ItemService.vaultService.delete(v); await refresh(); }
}

final vaultsProvider = NotifierProvider<VaultsNotifier, List<Vault>>(VaultsNotifier.new);

/// null = all, 'personal' = personal items only, else a vaultId.
final sourceFilterProvider = StateProvider<String?>((_) => null);
const String kPersonalSource = 'personal';

final filteredItemsProvider = Provider<List<Item>>((ref) {
  final all = ref.watch(itemsProvider);
  final f = ref.watch(sourceFilterProvider);
  if (f == null) return all;
  if (f == kPersonalSource) return all.where((i) => i.vaultId == null).toList();
  return all.where((i) => i.vaultId == f).toList();
});
```

`items_provider.dart`: `add/updateVersion/save/delete` use `ItemService.repoFor(item.vaultId)` instead of `ItemService.personal`; add
```dart
  Future<Item> move(Item item, String? toVaultId) async {
    final moved = await ItemService.move(item, toVaultId);
    refresh();
    return moved;
  }
```

- [ ] **Step 2: analyze → clean. Commit**

```bash
git add lib/providers
git commit -m "Vault and source-filter providers"
```

---

### Task 7: Home — filter chips, vault badge, pull-to-refresh, drawer entry

**Files:**
- Modify: `lib/screens/home_page.dart`

- [ ] **Step 1: Filter chips** — above the list (inside the `Column`, after the no-key banner), only when `ref.watch(vaultsProvider).isNotEmpty`:

```dart
  Widget _sourceChips() {
    final vaults = ref.watch(vaultsProvider);
    final current = ref.watch(sourceFilterProvider);
    Widget chip(String? value, String label, IconData icon) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            avatar: Icon(icon, size: 16),
            label: Text(label),
            selected: current == value,
            onSelected: (_) {
              Haptics.selection();
              ref.read(sourceFilterProvider.notifier).state = value;
            },
          ),
        );
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          chip(null, 'Alle', Icons.all_inclusive),
          chip(kPersonalSource, 'Persönlich', Icons.person_outline),
          for (final v in vaults)
            chip(v.id, v.name, ItemService.isLocked(v.id) ? Icons.lock_outline : Icons.group_outlined),
        ],
      ),
    );
  }
```
The list reads `ref.watch(filteredItemsProvider)` instead of `itemsProvider` (the search filter in `passwords` getter stays on top of it).

- [ ] **Step 2: Vault badge on the tile** — in `getSinglePasswordField`, when `pass.vaultId != null` append to the `title` Row:
```dart
          if (pass.vaultId != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.group_outlined, size: 12, color: scheme.primary),
                const SizedBox(width: 4),
                Text(ItemService.vaultById(pass.vaultId)?.name ?? 'Tresor',
                    style: TextStyle(fontSize: 10, color: scheme.primary, fontWeight: FontWeight.bold)),
              ]),
            ),
          ],
```

- [ ] **Step 3: Pull-to-refresh** — wrap the `ListView.separated` in `RefreshIndicator(onRefresh: () => ref.read(vaultsProvider.notifier).refresh(), child: …)` (also give the empty state an always-scrollable `ListView` so refresh works there too).

- [ ] **Step 4: Drawer** — add `ListTile(leading: Icon(Icons.group_outlined), title: Text('Tresore'), onTap: → VaultsScreen)` above 'Einstellungen' (screen created in Task 9; add the import then).

- [ ] **Step 5: analyze, commit**

```bash
git add lib/screens/home_page.dart
git commit -m "Home: source filter chips, vault badges, pull-to-refresh"
```

---

### Task 8: Editors choose the location; detail shows it; move on save

**Files:**
- Create: `lib/widgets/source_picker.dart`
- Modify: `lib/screens/add_new_password_screen.dart`, `lib/screens/card_editor_screen.dart`, `lib/screens/note_editor_screen.dart`, `lib/screens/password_detail_screen.dart`, `lib/screens/item_detail_screen.dart`

- [ ] **Step 1: `SourcePicker`**

```dart
// lib/widgets/source_picker.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/vaults_provider.dart';
import '../services/item_service.dart';

/// "Speicherort": personal or one of the (unlocked) vaults. Value = vaultId or null.
class SourcePicker extends ConsumerWidget {
  const SourcePicker({super.key, required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vaults = ref.watch(vaultsProvider).where((v) => !ItemService.isLocked(v.id)).toList();
    if (vaults.isEmpty) return const SizedBox.shrink();
    return DropdownButtonFormField<String?>(
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Speicherort', prefixIcon: Icon(Icons.folder_outlined)),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Persönlich')),
        for (final v in vaults) DropdownMenuItem<String?>(value: v.id, child: Text('Tresor „${v.name}“')),
      ],
      onChanged: onChanged,
    );
  }
}
```

- [ ] **Step 2: Editors**

Each editor keeps `String? _vaultId` (initialised from `widget.existing?.vaultId` / `widget.editVersion?.vaultId ?? widget.draft?.vaultId`), renders `SourcePicker(value: _vaultId, onChanged: (v) => setState(() => _vaultId = v))` under the title field, and:
- create: `Item.payload(col: ItemService.repoFor(_vaultId).col, vaultId: _vaultId, …)` / `Item.password(col: ItemService.repoFor(_vaultId).col, vaultId: _vaultId, …)`; drafts stay personal until finalized (`Item.draft` unchanged) — on finalize with `_vaultId != null`, save the draft then `ref.read(itemsProvider.notifier).move(draft, _vaultId)`.
- edit: after `save`/`updateVersion`, if `_vaultId != existing.vaultId` → `await ref.read(itemsProvider.notifier).move(existing, _vaultId)`.
- `AddNewPasswordScreen` edit-version path: `Item.password(col: ItemService.repoFor(_vaultId).col, vaultId: _vaultId, …)`; when the source changed, first `move` the old item's purpose (all versions) to `_vaultId`, then `updateVersion` the new one there.

- [ ] **Step 3: Detail screens** — under the header card, when `pass.vaultId != null`:
```dart
  ListTile(
    dense: true,
    leading: const Icon(Icons.group_outlined),
    title: Text('Geteilt in „${ItemService.vaultById(pass.vaultId)?.name ?? 'Tresor'}“'),
    subtitle: Text('${ItemService.vaultById(pass.vaultId)?.memberCount ?? 0} Mitglieder'),
  ),
```
History tiles: when `h.displayName != null` prefix the title with `'${h.displayName} · '`.

- [ ] **Step 4: analyze, tests, commit**

```bash
git add lib/widgets/source_picker.dart lib/screens
git commit -m "Editors pick personal or vault as location; move on change; detail shows the vault"
```

---

### Task 9: Vault screens (list, create, join with QR scan/paste)

**Files:**
- Create: `lib/screens/vaults_screen.dart`
- Create: `lib/screens/vault_join_screen.dart`
- Modify: `pubspec.yaml` (`qr_flutter`, `mobile_scanner`), `ios/Runner/Info.plist` (`NSCameraUsageDescription`), `android/app/src/main/AndroidManifest.xml` (`android.permission.CAMERA`)

- [ ] **Step 1: Dependencies** — `flutter pub add qr_flutter mobile_scanner`; Info.plist: `<key>NSCameraUsageDescription</key><string>Zum Scannen von Einladungscodes für Tresore.</string>`; manifest: `<uses-permission android:name="android.permission.CAMERA" />`.

- [ ] **Step 2: `VaultsScreen`** — `ConsumerWidget`; AppBar 'Tresore' with action `Icons.qr_code_scanner` → `VaultJoinScreen`; body: `ListView` of `ref.watch(vaultsProvider)` (`ListTile(leading: Icon(locked ? Icons.lock_outline : Icons.group_outlined), title: name, subtitle: '${v.memberCount} Mitglieder' + (v.isOwner(uid) ? ' · Du bist Owner' : ''), trailing: chevron → VaultDetailScreen(v))`); empty state text 'Noch keine Tresore. Erstelle einen oder tritt per Einladungscode bei.'; FAB '+' → dialog with `AppTextField` 'Name (z. B. Oma)' → `ref.read(vaultsProvider.notifier).create(name)`; if `!ref.read(hasKeyProvider)` show the usual key warning instead.

- [ ] **Step 3: `VaultJoinScreen`** — `ConsumerStatefulWidget`; a multiline `AppTextField` 'Einladungscode einfügen' + button 'Beitreten' (parses with `InviteCode.parse`, on null → snackbar 'Ungültiger Code'; on `InviteError` → its message; on success → pop with snackbar 'Tresor „name“ beigetreten'); on iOS/Android additionally a `MobileScanner` preview (`onDetect: (capture) → first barcode rawValue → same join path`, guarded by a `_handled` flag so a QR is processed once). On web/desktop the scanner is hidden (`kIsWeb || !(Platform.isIOS || Platform.isAndroid)`).

- [ ] **Step 4: analyze, run on simulator (create vault, open join screen), commit**

```bash
git add pubspec.yaml pubspec.lock ios/Runner/Info.plist android/app/src/main/AndroidManifest.xml lib/screens/vaults_screen.dart lib/screens/vault_join_screen.dart
git commit -m "Vault list, create and join (paste or scan invite code)"
```

---

### Task 10: Vault detail — members, invite QR, owner actions

**Files:**
- Create: `lib/screens/vault_detail_screen.dart`
- Create: `lib/screens/vault_invite_screen.dart`

- [ ] **Step 1: `VaultDetailScreen(Vault)`** — reads the fresh vault from `ref.watch(vaultsProvider)` by id; sections:
  - Header: name, member count; owner: edit icon → rename dialog.
  - 'Einladen' primary button → `VaultInviteScreen(vault)` (disabled with hint when locked).
  - Members list: `ListTile(leading: CircleAvatar(initial), title: v.nameOf(uid), subtitle: uid == v.ownerId ? 'Owner' : 'Mitglied', trailing: owner && uid != me ? IconButton(remove) : null)`; remove → confirm dialog → `removeMember`.
  - Danger zone: member → 'Tresor verlassen' (confirm) → `leave` + pop; owner → 'Tresor löschen' (confirm: 'Alle Einträge im Tresor werden für alle Mitglieder gelöscht.') → `delete` + pop.

- [ ] **Step 2: `VaultInviteScreen(Vault)`** — on open calls `ItemService.vaultService.createInvite(vault)`; shows `QrImageView(data: code.encode(), size: 240)` (`qr_flutter`), the code in a selectable monospace box, buttons 'Code kopieren' (`Clipboard.setData`, snackbar) and 'Neuen Code erzeugen'; footer text 'Gültig 7 Tage, einmal verwendbar. Der Code enthält den Tresor-Schlüssel – nur persönlich weitergeben.'

- [ ] **Step 3: analyze, simulator smoke (invite → copy → second account joins), commit**

```bash
git add lib/screens/vault_detail_screen.dart lib/screens/vault_invite_screen.dart
git commit -m "Vault detail: members, owner actions, invite QR/code"
```

---

### Task 11: Lock handling, error paths, final sweep

**Files:**
- Modify: `lib/screens/first_screen.dart` (mask + clear keys on lock is already done via `maskAll`; nothing else)
- Modify: `lib/screens/settings_screen.dart` (after the master key changes: `ref.read(vaultsProvider.notifier).refresh()`)
- Modify: `lib/screens/home_page.dart` (locked vault chip → tap shows snackbar 'Tresor gesperrt – Encryption-Key prüfen')

- [ ] **Step 1: Wire key change → reload** in `settings_screen.dart` `_save` and key delete: `await ref.read(vaultsProvider.notifier).refresh();`.
- [ ] **Step 2: permission-denied resilience** — in `ItemService.reloadVaults()`, wrap each `repo.load()` in try/catch; on failure drop that vault from `vaultRepos` (member removed meanwhile) — never let one vault break the whole load.
- [ ] **Step 3: Verify** — `flutter analyze` clean, `flutter test` green, `flutter build ios --debug --no-codesign` succeeds. Manual e2e with two accounts (simulator + Mac): create vault → invite → join → add password in vault from B → visible for A after pull-to-refresh → move a personal item into the vault → B sees it → B leaves → B no longer sees it.
- [ ] **Step 4: Commit**

```bash
git add -A lib
git commit -m "Vault lock handling and load resilience"
```
