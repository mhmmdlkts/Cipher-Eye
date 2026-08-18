# Items-Datenmodell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the password-only model with a unified `Item` model (`password | card | note | document | file`), add card and note entries end-to-end, and migrate `users/{uid}/passwords` → `users/{uid}/items`.

**Architecture:** `Item` is the single Firestore document shape; sensitive data lives in the encrypted `value/iv/v` blob (raw string for passwords, JSON for every other type). `CryptoService` does AES-GCM with an explicit key; `ItemRepository` wraps one collection (personal now, vaults later); `ItemService` is the static facade the existing UI already talks to. A silent, verified copy-then-delete migration moves legacy password docs into `items`.

**Tech Stack:** Flutter 3.x, Riverpod 2, cloud_firestore 6, encrypt 5 (AES-GCM), fake_cloud_firestore (tests), Firebase CLI (rules deploy).

**Spec:** `docs/superpowers/specs/2026-08-18-items-model-design.md`

## Execution order

1 → 2 → 3 → 4 → 5 → 6 → 8 → 9 → 7 → 10. Tasks 8 and 9 create the screens Task 7 navigates to, so landing them first keeps every commit compiling.

## Global Constraints

- Crypto stays AES-256-GCM, 12-byte random IV, `v = 2`; legacy v1 (AES-SIC, zero IV) must still decrypt.
- Only `type`, `title`, `username` (password only), `purposeId`, timestamps, flags and counters are plaintext. Everything else goes into the encrypted blob.
- Firestore rules for `items` are deployed **before** the app release; rules for `passwords` stay until the migration is retired.
- Migration never deletes an original before the copy is verified; idempotent and resumable.
- No AI/assistant markers anywhere (commits, code, docs). German UI strings, code comments in English (matches the codebase).
- Run `flutter analyze` (must be clean) and `flutter test` (all green) before every commit.

---

### Task 1: Firestore rules into the repo, `items` collection allowed, deploy

**Files:**
- Create: `firestore.rules`
- Create: `.firebaserc`
- Modify: `firebase.json`

**Interfaces:**
- Produces: deployed rules allowing owner-only `users/{uid}/items/{itemId}`.

- [ ] **Step 1: Write the rules file** (deployed rules fetched from the Rules API, plus `items`)

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function isAuthenticated() {
      return request.auth != null;
    }
    function isOwner(userId) {
      return request.auth.uid == userId;
    }

    // Profile: owner reads/writes (name, usernames, securityVersion, dataVersion).
    match /users/{userId} {
      allow read, write: if isAuthenticated() && isOwner(userId);
    }

    // Unified items (passwords, cards, notes, documents, files).
    match /users/{userId}/items/{itemId} {
      allow read, create, update, delete: if isAuthenticated() && isOwner(userId);
    }

    // Legacy password collection: kept readable/deletable until every account
    // has migrated into /items. Creating new docs here is no longer allowed.
    match /users/{userId}/passwords/{passwordId} {
      allow read, update, delete: if isAuthenticated() && isOwner(userId);
      allow create: if false;
    }

    // History: append-only, owner only.
    match /users/{userId}/history/{historyId} {
      allow create, read: if isAuthenticated() && isOwner(userId);
      allow update, delete: if false;
    }
  }
}
```

- [ ] **Step 2: Point the CLI at the project and register the rules file**

`.firebaserc`:
```json
{
  "projects": { "default": "cipher-eye" }
}
```

`firebase.json` — add a top-level `firestore` key next to the existing `flutter` key:
```json
"firestore": { "rules": "firestore.rules" }
```
(Keep the existing `flutter` block untouched.)

- [ ] **Step 3: Dry-run and deploy**

Run: `firebase deploy --only firestore:rules --project cipher-eye`
Expected: `✔ Deploy complete!` — then re-fetch the release and confirm the `items` match block is live:
`TOKEN=$(gcloud auth print-access-token); curl -s -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: cipher-eye" https://firebaserules.googleapis.com/v1/projects/cipher-eye/releases/cloud.firestore`

- [ ] **Step 4: Commit**

```bash
git add firestore.rules .firebaserc firebase.json
git commit -m "Firestore rules in repo; allow users/{uid}/items"
```

---

### Task 2: `ItemType` and typed payloads

**Files:**
- Create: `lib/models/item_type.dart`
- Create: `lib/models/item_payload.dart`
- Test: `test/item_payload_test.dart`

**Interfaces:**
- Produces: `enum ItemType { password, card, note, document, file }` with `String get key`, `static ItemType fromKey(String?)`, `String get label`, `IconData get icon`.
- Produces: `CardData`, `NoteData`, `DocumentData`, `FileData` — each with `Map<String, dynamic> toJson()` (empty fields omitted) and `factory X.fromJson(Map<String, dynamic>)`; `String encode()` / `static X decode(String)` via `jsonEncode/jsonDecode`.

- [ ] **Step 1: Write the failing test**

```dart
// test/item_payload_test.dart
import 'package:cipher_eye/models/item_payload.dart';
import 'package:cipher_eye/models/item_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ItemType round-trips through its key and falls back to password', () {
    for (final t in ItemType.values) {
      expect(ItemType.fromKey(t.key), t);
    }
    expect(ItemType.fromKey(null), ItemType.password);
    expect(ItemType.fromKey('nonsense'), ItemType.password);
  });

  test('CardData omits empty fields and round-trips', () {
    const c = CardData(number: '4111 1111 1111 1111', holder: 'Max', cvv: '123');
    final json = c.toJson();
    expect(json.containsKey('expiry'), isFalse);
    expect(json.containsKey('pin'), isFalse);
    expect(CardData.decode(c.encode()), c);
  });

  test('NoteData round-trips', () {
    const n = NoteData(text: 'WLAN: geheim');
    expect(NoteData.decode(n.encode()), n);
  });

  test('DocumentData round-trips incl. docType', () {
    const d = DocumentData(docType: DocType.passport, number: 'P123', expires: '2031-05-01');
    expect(DocumentData.decode(d.encode()), d);
    expect(DocumentData.decode('{}').docType, DocType.other);
  });

  test('FileData round-trips', () {
    const f = FileData(note: 'Vertrag');
    expect(FileData.decode(f.encode()), f);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/item_payload_test.dart`
Expected: FAIL — `item_payload.dart` / `item_type.dart` not found.

- [ ] **Step 3: Implement**

```dart
// lib/models/item_type.dart
import 'package:flutter/material.dart';

enum ItemType {
  password('password', 'Passwort', Icons.key_outlined),
  card('card', 'Karte', Icons.credit_card_outlined),
  note('note', 'Notiz', Icons.sticky_note_2_outlined),
  document('document', 'Dokument', Icons.badge_outlined),
  file('file', 'Datei', Icons.insert_drive_file_outlined);

  const ItemType(this.key, this.label, this.icon);

  /// Value stored in Firestore.
  final String key;
  final String label;
  final IconData icon;

  static ItemType fromKey(String? key) =>
      ItemType.values.firstWhere((t) => t.key == key,
          orElse: () => ItemType.password);
}
```

```dart
// lib/models/item_payload.dart
import 'dart:convert';

/// Typed views on the encrypted JSON blob of non-password items. Every field
/// is optional; empty strings are omitted from the JSON so the blob only
/// contains what the user actually entered.
Map<String, dynamic> _compact(Map<String, String?> m) => {
      for (final e in m.entries)
        if (e.value != null && e.value!.isNotEmpty) e.key: e.value,
    };

String? _s(Map<String, dynamic> j, String k) => j[k]?.toString();

class CardData {
  const CardData({
    this.number, this.holder, this.expiry, this.cvv, this.pin,
    this.iban, this.bank, this.note,
  });
  final String? number, holder, expiry, cvv, pin, iban, bank, note;

  Map<String, dynamic> toJson() => _compact({
        'number': number, 'holder': holder, 'expiry': expiry, 'cvv': cvv,
        'pin': pin, 'iban': iban, 'bank': bank, 'note': note,
      });
  factory CardData.fromJson(Map<String, dynamic> j) => CardData(
        number: _s(j, 'number'), holder: _s(j, 'holder'), expiry: _s(j, 'expiry'),
        cvv: _s(j, 'cvv'), pin: _s(j, 'pin'), iban: _s(j, 'iban'),
        bank: _s(j, 'bank'), note: _s(j, 'note'),
      );
  String encode() => jsonEncode(toJson());
  static CardData decode(String s) =>
      CardData.fromJson(jsonDecode(s) as Map<String, dynamic>);

  @override
  bool operator ==(Object o) => o is CardData && o.encode() == encode();
  @override
  int get hashCode => encode().hashCode;
}

class NoteData {
  const NoteData({this.text});
  final String? text;
  Map<String, dynamic> toJson() => _compact({'text': text});
  factory NoteData.fromJson(Map<String, dynamic> j) => NoteData(text: _s(j, 'text'));
  String encode() => jsonEncode(toJson());
  static NoteData decode(String s) =>
      NoteData.fromJson(jsonDecode(s) as Map<String, dynamic>);
  @override
  bool operator ==(Object o) => o is NoteData && o.text == text;
  @override
  int get hashCode => text.hashCode;
}

enum DocType {
  passport('passport', 'Reisepass'),
  id('id', 'Personalausweis'),
  driver('driver', 'Führerschein'),
  other('other', 'Sonstiges');
  const DocType(this.key, this.label);
  final String key, label;
  static DocType fromKey(String? k) =>
      DocType.values.firstWhere((d) => d.key == k, orElse: () => DocType.other);
}

class DocumentData {
  const DocumentData({
    this.docType = DocType.other, this.number, this.issued, this.expires, this.note,
  });
  final DocType docType;
  final String? number, issued, expires, note;
  Map<String, dynamic> toJson() => {
        'docType': docType.key,
        ..._compact({'number': number, 'issued': issued, 'expires': expires, 'note': note}),
      };
  factory DocumentData.fromJson(Map<String, dynamic> j) => DocumentData(
        docType: DocType.fromKey(_s(j, 'docType')),
        number: _s(j, 'number'), issued: _s(j, 'issued'),
        expires: _s(j, 'expires'), note: _s(j, 'note'),
      );
  String encode() => jsonEncode(toJson());
  static DocumentData decode(String s) =>
      DocumentData.fromJson(jsonDecode(s) as Map<String, dynamic>);
  @override
  bool operator ==(Object o) => o is DocumentData && o.encode() == encode();
  @override
  int get hashCode => encode().hashCode;
}

class FileData {
  const FileData({this.note});
  final String? note;
  Map<String, dynamic> toJson() => _compact({'note': note});
  factory FileData.fromJson(Map<String, dynamic> j) => FileData(note: _s(j, 'note'));
  String encode() => jsonEncode(toJson());
  static FileData decode(String s) =>
      FileData.fromJson(jsonDecode(s) as Map<String, dynamic>);
  @override
  bool operator ==(Object o) => o is FileData && o.note == note;
  @override
  int get hashCode => note.hashCode;
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/item_payload_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/models/item_type.dart lib/models/item_payload.dart test/item_payload_test.dart
git commit -m "Item types and typed payloads for cards, notes, documents, files"
```

---

### Task 3: `CryptoService` with an explicit key

**Files:**
- Create: `lib/services/crypto_service.dart`
- Modify: `lib/services/password_service.dart:45-129` (delegate `encode/decode` to `CryptoService`)
- Test: `test/crypto_service_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class CryptoService {
    static const int kVersion = 2;
    static Key keyFromMaster(String master);          // Key.fromUtf8
    static Key randomKey();                            // 32 random bytes (vaults later)
    static ({String value, String iv}) encrypt(String plain, Key key);
    static String decrypt({required String value, String? iv, int? v, required Key key});
  }
  ```
- `PasswordService.encode/decode/kCryptoVersion` keep their signatures and delegate using the master key (`SecureStorageService.key`).

- [ ] **Step 1: Write the failing test**

```dart
// test/crypto_service_test.dart
import 'package:cipher_eye/services/crypto_service.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final key = CryptoService.keyFromMaster('ABCDEFGHIJKLMNOPQRSTUVWXYZ012345');

  test('encrypt/decrypt round-trip with fresh IVs', () {
    final a = CryptoService.encrypt('geheim', key);
    final b = CryptoService.encrypt('geheim', key);
    expect(a.iv, isNot(b.iv));
    expect(CryptoService.decrypt(value: a.value, iv: a.iv, v: 2, key: key), 'geheim');
  });

  test('wrong key fails (GCM tag)', () {
    final other = CryptoService.randomKey();
    final e = CryptoService.encrypt('geheim', key);
    expect(() => CryptoService.decrypt(value: e.value, iv: e.iv, v: 2, key: other),
        throwsA(anything));
  });

  test('legacy v1 blobs decrypt', () {
    final legacy = Encrypter(AES(key)).encrypt('alt', iv: IV.allZerosOfLength(16)).base64;
    expect(CryptoService.decrypt(value: legacy, iv: null, v: 1, key: key), 'alt');
  });

  test('randomKey is 32 bytes and unique', () {
    expect(CryptoService.randomKey().bytes.length, 32);
    expect(CryptoService.randomKey().base64, isNot(CryptoService.randomKey().base64));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/crypto_service_test.dart` → FAIL (file missing).

- [ ] **Step 3: Implement and delegate**

```dart
// lib/services/crypto_service.dart
import 'package:encrypt/encrypt.dart';

/// AES-256-GCM with an explicit key. Used with the master key for personal
/// items and (later) with per-vault keys for shared items.
class CryptoService {
  /// v1 (legacy): AES-SIC, fixed zero IV. v2: AES-GCM, random IV.
  static const int kVersion = 2;
  static const int _gcmIvLength = 12;

  static Key keyFromMaster(String master) => Key.fromUtf8(master);

  static Key randomKey() => Key.fromSecureRandom(32);

  static ({String value, String iv}) encrypt(String plain, Key key) {
    final iv = IV.fromSecureRandom(_gcmIvLength);
    final encrypted = Encrypter(AES(key, mode: AESMode.gcm)).encrypt(plain, iv: iv);
    return (value: encrypted.base64, iv: iv.base64);
  }

  static String decrypt(
      {required String value, String? iv, int? v, required Key key}) {
    if ((v ?? 1) >= kVersion && iv != null) {
      return Encrypter(AES(key, mode: AESMode.gcm))
          .decrypt(Encrypted.fromBase64(value), iv: IV.fromBase64(iv));
    }
    // Byte-compatible with the original implementation (SIC + PKCS7 + zero IV).
    return Encrypter(AES(key))
        .decrypt(Encrypted.fromBase64(value), iv: IV.allZerosOfLength(16));
  }
}
```

In `lib/services/password_service.dart` replace lines 45–129 (`kCryptoVersion`, `_gcmIvLength`, `_requireKey`, `encode`, `decode`, `_decodeLegacy`) with:

```dart
  static const int kCryptoVersion = CryptoService.kVersion;

  static Key _requireKey() {
    final k = SecureStorageService.key;
    if (k == null) throw StateError('Encryption key is not set');
    return CryptoService.keyFromMaster(k);
  }

  static ({String value, String iv}) encode(String value) =>
      CryptoService.encrypt(value, _requireKey());

  static String decode({required String value, String? iv, int? v}) =>
      CryptoService.decrypt(value: value, iv: iv, v: v, key: _requireKey());
```
(add `import 'crypto_service.dart';`, keep the `encrypt` import for `Key`).

- [ ] **Step 4: Run all tests**

Run: `flutter test` → PASS (existing `crypto_migration_test.dart` still green).

- [ ] **Step 5: Commit**

```bash
git add lib/services/crypto_service.dart lib/services/password_service.dart test/crypto_service_test.dart
git commit -m "CryptoService with explicit key; PasswordService delegates"
```

---

### Task 4: `Item` model (replaces `Password`)

**Files:**
- Create: `lib/models/item.dart`
- Modify: `lib/models/password.dart` → becomes `typedef Password = Item;` (transition only)
- Test: `test/item_model_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class Item implements Comparable<Item> {
    String? id; ItemType type; String? title; String? username; Timestamp? timestamp;
    Timestamp? updatedAt; String? purposeId; String? value; String? iv; int v;
    bool isFavorite, isDraft, isLatest, isVisible; int copyCount, viewCount;
    List<Map<String, dynamic>> attachments;
    DocumentReference? ref;                       // where this doc lives
    String? get website; set website(String?);    // alias of title (password)
    Item.password({required CollectionReference col, required String website, required String username, required String plainText, bool isFavorite});
    Item.draft({required CollectionReference col, String? username, required String plainText});
    Item.payload({required CollectionReference col, required ItemType type, required String title, required String plainJson, bool isFavorite});
    Item.fromSnapshot(DocumentSnapshot snap);     // ref = snap.reference
    Map<String, dynamic> toJson({bool withNull = true});
    Future<void> push(); Future<void> update();
    void applyEdits({required String website, required String username, required String plainText, bool finalize});
    void setPayload({required String title, required String plainJson});
    String decrypted(); String getPlainText(); bool get needsMigration; Future<void> migrateCrypto();
    static String purposeIdCreate({required String website, required String username});
  }
  ```

- [ ] **Step 1: Write the failing test**

```dart
// test/item_model_test.dart
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
```

- [ ] **Step 2: Add the test dependency and run to verify it fails**

Run: `flutter pub add --dev fake_cloud_firestore` then `flutter test test/item_model_test.dart`
Expected: FAIL — `item.dart` missing. (If `fake_cloud_firestore` cannot resolve against `cloud_firestore ^6.5.0`, pin the newest compatible major and note it in the commit.)

- [ ] **Step 3: Implement `Item`**

```dart
// lib/models/item.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

import '../services/history_service.dart';
import '../services/password_service.dart';
import 'item_type.dart';

/// One stored entry: password, card, note, document or file. Sensitive data is
/// only ever in [value] (AES-GCM, see [PasswordService.encode]); for passwords
/// the plaintext is the bare password, for every other type a JSON payload
/// (see item_payload.dart).
class Item implements Comparable<Item> {
  String? id;
  ItemType type = ItemType.password;
  String? title;
  String? username;
  Timestamp? timestamp;
  Timestamp? updatedAt;
  String? purposeId;
  String? value;
  String? iv;
  int v = 1;
  bool isFavorite = false;
  int copyCount = 0;
  int viewCount = 0;
  bool isDraft = false;
  bool isLatest = false;
  bool isVisible = false;
  List<Map<String, dynamic>> attachments = [];

  /// The Firestore document this item lives in (set on load / creation).
  DocumentReference? ref;

  String? _plainText;

  /// Password entries historically called the title "website".
  String? get website => title;
  set website(String? w) => title = w;

  Item.password({
    required CollectionReference col,
    required String website,
    required String username,
    required String plainText,
    this.isFavorite = false,
  }) {
    ref = col.doc();
    id = ref!.id;
    type = ItemType.password;
    title = website;
    this.username = username;
    purposeId = purposeIdCreate(website: website, username: username);
    _encrypt(plainText);
    timestamp = Timestamp.now();
  }

  /// A work-in-progress password: generated, no website yet.
  Item.draft({required CollectionReference col, this.username, required String plainText}) {
    ref = col.doc();
    id = ref!.id;
    type = ItemType.password;
    title = '';
    purposeId = purposeIdCreate(website: '', username: username ?? '');
    _encrypt(plainText);
    isDraft = true;
    timestamp = Timestamp.now();
  }

  /// Any non-password type: [plainJson] is the encoded payload.
  Item.payload({
    required CollectionReference col,
    required this.type,
    required String title,
    required String plainJson,
    this.isFavorite = false,
  }) {
    ref = col.doc();
    id = ref!.id;
    this.title = title;
    _encrypt(plainJson);
    timestamp = Timestamp.now();
  }

  void _encrypt(String plain) {
    final e = PasswordService.encode(plain);
    value = e.value;
    iv = e.iv;
    v = PasswordService.kCryptoVersion;
    _plainText = null;
  }

  void applyEdits({
    required String website,
    required String username,
    required String plainText,
    bool finalize = false,
  }) {
    title = website;
    this.username = username;
    purposeId = purposeIdCreate(website: website, username: username);
    _encrypt(plainText);
    isDraft = !finalize;
    timestamp = Timestamp.now();
  }

  /// Non-password types: replace title + payload in place.
  void setPayload({required String title, required String plainJson}) {
    this.title = title;
    _encrypt(plainJson);
    updatedAt = Timestamp.now();
  }

  static String purposeIdCreate({required String website, required String username}) =>
      sha256.convert(utf8.encode(website + username)).toString();

  Item.fromSnapshot(DocumentSnapshot<Object?> snap) {
    ref = snap.reference;
    id = snap.id;
    final o = snap.data() as Map<String, dynamic>?;
    if (o == null) return;
    type = ItemType.fromKey(o['type'] as String?);
    title = (o['title'] ?? o['website']) as String?;
    username = o['username'] as String?;
    value = o['value'] as String?;
    iv = o['iv'] as String?;
    if (o['v'] != null) v = (o['v'] as num).toInt();
    purposeId = o['purposeId'] as String?;
    timestamp = o['timestamp'] as Timestamp?;
    updatedAt = o['updatedAt'] as Timestamp?;
    isFavorite = o['isFavorite'] == true;
    isDraft = o['isDraft'] == true;
    if (o['copyCount'] != null) copyCount = (o['copyCount'] as num).toInt();
    if (o['viewCount'] != null) viewCount = (o['viewCount'] as num).toInt();
    if (o['attachments'] is List) {
      attachments = (o['attachments'] as List)
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
  }

  Map<String, dynamic> toJson({bool withNull = true}) {
    final map = <String, dynamic>{
      'type': type.key,
      'title': title,
      'username': username,
      'purposeId': purposeId,
      'value': value,
      'iv': iv,
      'v': v,
      'timestamp': timestamp,
      'updatedAt': updatedAt,
      'isFavorite': isFavorite,
      'isDraft': isDraft,
      if (attachments.isNotEmpty) 'attachments': attachments,
    };
    if (withNull) return map;
    return {for (final e in map.entries) if (e.value != null) e.key: e.value};
  }

  Future<void> push() => ref!.set(toJson(), SetOptions(merge: true));
  Future<void> update() => ref!.update(toJson(withNull: false));

  String getPlainText() {
    if (_plainText == null) {
      HistoryService.saveCopyHistory(id!);
      _plainText = PasswordService.decode(value: value!, iv: iv, v: v);
    }
    return _plainText!;
  }

  /// Decrypts WITHOUT logging — for on-screen display.
  String decrypted() => PasswordService.decode(value: value!, iv: iv, v: v);

  bool get needsMigration => v < PasswordService.kCryptoVersion;

  Future<void> migrateCrypto() async {
    if (!needsMigration) return;
    final plain = PasswordService.decode(value: value!, iv: iv, v: v);
    final encoded = PasswordService.encode(plain);
    final roundTrip = PasswordService.decode(
        value: encoded.value, iv: encoded.iv, v: PasswordService.kCryptoVersion);
    if (roundTrip != plain) {
      throw StateError('Migration self-check failed for item $id');
    }
    await ref!.update(
        {'value': encoded.value, 'iv': encoded.iv, 'v': PasswordService.kCryptoVersion});
    value = encoded.value;
    iv = encoded.iv;
    v = PasswordService.kCryptoVersion;
    _plainText = null;
  }

  @override
  int compareTo(Item other) {
    if (isFavorite && !other.isFavorite) return -1;
    if (!isFavorite && other.isFavorite) return 1;
    return other.timestamp?.compareTo(timestamp ?? Timestamp(0, 0)) ?? 0;
  }
}
```

`lib/models/password.dart` becomes:
```dart
import 'item.dart';

/// Transitional alias — every password is an [Item] of type password.
typedef Password = Item;
```
Then fix the compile errors in callers that used the removed constructors:
- `add_new_password_screen.dart`: `Password.createDraft(username:, plaintText:)` → `Item.draft(col: FirestorePathsService.getPasswordCol(), username:, plainText:)`; `Password.create(website:, username:, plaintText:)` → `Item.password(col: FirestorePathsService.getPasswordCol(), website:, username:, plainText:)`. (The collection is switched to `items` in Task 5.)
- `password_service.dart` `init()`: `Password.fromSnapshot(doc)` stays valid via the typedef.

- [ ] **Step 4: Run tests + analyze**

Run: `flutter analyze && flutter test` → clean, all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/item.dart lib/models/password.dart lib/screens/add_new_password_screen.dart pubspec.yaml pubspec.lock test/item_model_test.dart
git commit -m "Item model: typed entries with encrypted payload; Password becomes an alias"
```

---

### Task 5: `ItemRepository` + `ItemService` facade, `items` collection path

**Files:**
- Create: `lib/services/item_repository.dart`
- Create: `lib/services/item_service.dart`
- Modify: `lib/services/firestore_paths_service.dart` (add `getItemsCol()`, `getItemDoc()`)
- Modify: `lib/services/password_service.dart` (becomes a thin re-export of `ItemService`; keep `encode/decode/kCryptoVersion` here)
- Modify: `lib/services/init_service.dart:19-22` (`ItemService.init()`)
- Test: `test/item_repository_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class ItemRepository {
    ItemRepository(this.col);
    final CollectionReference col;
    final List<Item> items;
    Future<void> load({List<CollectionReference> extraSources = const []});
    List<Item> get latest;      // isLatest && !isDraft (passwords) + all non-password
    List<Item> get drafts;
    List<Item> versionsOf(String purposeId);
    Future<void> add(Item item);            // new password (or any type) → marks latest
    Future<void> updateVersion(Item item);  // password edit → new version doc
    Future<void> save(Item item);           // non-password in-place edit → push()
    Future<void> delete(Item item);         // all versions for passwords, drafts by id
    Future<void> incrementUsage(Item item, {required bool copy});
    void maskAll();
  }
  class ItemService {          // static facade
    static late ItemRepository personal;
    static List<Item> get items => personal.items;  // etc.: latest, drafts, versionsOf, maskAll
    static Future<void> init();
    static Future<void> incrementUsage(String itemId, {required bool copy});
  }
  ```
- `PasswordService.passwords/newPasswords/drafts/versionsOf/maskAll/addNewPassword/updatePassword/deletePassword/incrementUsage/init` forward to `ItemService.personal` — so the UI keeps compiling until Task 7 switches it over.

- [ ] **Step 1: Write the failing test**

```dart
// test/item_repository_test.dart
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
    repo = ItemRepository(db.collection('users').doc('u1').collection('items'));
  });

  test('add + load marks the newest version per purpose as latest', () async {
    final a = Item.password(col: repo.col, website: 'w', username: 'u', plainText: '1');
    await repo.add(a);
    final b = Item.password(col: repo.col, website: 'w', username: 'u', plainText: '2');
    await repo.updateVersion(b);
    final fresh = ItemRepository(repo.col);
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
    final fresh = ItemRepository(repo.col);
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/item_repository_test.dart` → FAIL (missing file).

- [ ] **Step 3: Implement**

```dart
// lib/services/item_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/item.dart';
import '../models/item_type.dart';
import 'history_service.dart';

/// All items of one collection (the personal `items` collection today; one
/// per vault later). Owns loading, version bookkeeping and persistence.
class ItemRepository {
  ItemRepository(this.col);

  final CollectionReference col;
  final List<Item> items = [];

  /// Loads [col] plus any [extraSources] (legacy collections). Items keep the
  /// document reference they were loaded from, so writes go back to the right
  /// place. When the same id exists in several sources, [col] wins.
  Future<void> load({List<CollectionReference> extraSources = const []}) async {
    final byId = <String, Item>{};
    for (final src in extraSources) {
      for (final d in (await src.get()).docs) {
        byId[d.id] = Item.fromSnapshot(d);
      }
    }
    for (final d in (await col.get()).docs) {
      byId[d.id] = Item.fromSnapshot(d);
    }
    items
      ..clear()
      ..addAll(byId.values);
    _recomputeLatest();
    items.sort();
  }

  void _recomputeLatest() {
    final newestByPurpose = <String, Item>{};
    for (final it in items) {
      it.isLatest = false;
      if (it.type != ItemType.password || it.isDraft) continue;
      final key = it.purposeId ?? it.id!;
      final cur = newestByPurpose[key];
      if (cur == null || _ts(it) > _ts(cur)) newestByPurpose[key] = it;
    }
    for (final it in newestByPurpose.values) {
      it.isLatest = true;
    }
  }

  static int _ts(Item i) => i.timestamp?.millisecondsSinceEpoch ?? 0;

  /// What the list shows: latest password per purpose + every non-password.
  List<Item> get latest => items
      .where((i) => !i.isDraft && (i.type != ItemType.password || i.isLatest))
      .toList();

  List<Item> get drafts => items.where((i) => i.isDraft).toList();

  List<Item> versionsOf(String purposeId) {
    final list = items
        .where((i) => i.type == ItemType.password && i.purposeId == purposeId && !i.isDraft)
        .toList()
      ..sort((a, b) => _ts(b).compareTo(_ts(a)));
    return list;
  }

  Future<void> add(Item item) async {
    items.add(item);
    _recomputeLatest();
    if (!item.isDraft) HistoryService.saveCreateHistory(item.id!);
    await item.push();
  }

  /// Password edit: the new version is stored next to the old one.
  Future<void> updateVersion(Item item) async {
    items.add(item);
    _recomputeLatest();
    HistoryService.saveUpdateHistory(item.id!);
    await item.push();
  }

  /// In-place save (drafts, non-password types).
  Future<void> save(Item item) async {
    if (!items.contains(item)) items.add(item);
    _recomputeLatest();
    await item.push();
  }

  Future<void> delete(Item item) async {
    HistoryService.saveDeleteHistory(item.id!);
    final victims = (item.type == ItemType.password && !item.isDraft)
        ? items.where((i) => i.type == ItemType.password && !i.isDraft && i.purposeId == item.purposeId).toList()
        : [item];
    items.removeWhere(victims.contains);
    _recomputeLatest();
    for (final v in victims) {
      await v.ref!.delete();
    }
  }

  Future<void> incrementUsage(Item item, {required bool copy}) {
    final field = copy ? 'copyCount' : 'viewCount';
    if (copy) { item.copyCount++; } else { item.viewCount++; }
    return item.ref!.update({field: FieldValue.increment(1)});
  }

  void maskAll() {
    for (final i in items) {
      i.isVisible = false;
    }
  }
}
```

```dart
// lib/services/item_service.dart
import '../models/item.dart';
import 'firestore_paths_service.dart';
import 'item_repository.dart';
import 'person_service.dart';

/// Static facade over the personal item repository (kept static so the
/// existing UI/services keep working; vaults add more repositories later).
class ItemService {
  static late ItemRepository personal;

  static List<Item> get items => personal.items;
  static List<Item> get latest => personal.latest;
  static List<Item> get drafts => personal.drafts;
  static List<Item> versionsOf(String purposeId) => personal.versionsOf(purposeId);
  static void maskAll() => personal.maskAll();

  static Future<void> init() async {
    personal = ItemRepository(FirestorePathsService.getItemsCol());
    // Until the account has migrated (Task 6), also read the legacy collection.
    final migrated = PersonService.person.dataVersion >= PersonService.kDataVersion;
    await personal.load(
        extraSources: migrated ? const [] : [FirestorePathsService.getPasswordCol()]);
  }

  static Future<void> incrementUsage(String itemId, {required bool copy}) {
    final item = personal.items.firstWhere((i) => i.id == itemId);
    return personal.incrementUsage(item, copy: copy);
  }
}
```

`firestore_paths_service.dart` — add:
```dart
  static const String _itemsKey = "items";
  static CollectionReference getItemsCol() => getUserDoc().collection(_itemsKey);
  static DocumentReference getItemDoc({required String itemId}) => getItemsCol().doc(itemId);
```

`person.dart` — add field + parse + serialize:
```dart
  /// Data-layout version of this account. 3 = passwords live in /items.
  int dataVersion = 1;
  // fromSnapshot: if (o.containsKey('dataVersion')) dataVersion = (o['dataVersion'] as num).toInt();
  // toJson: 'dataVersion': dataVersion,
```
`person_service.dart` — add `static const int kDataVersion = 3;`.

`password_service.dart` — delete the list/CRUD parts and forward:
```dart
class PasswordService {
  static List<Item> get passwords => ItemService.items;
  static List<Item> get newPasswords => ItemService.latest.where((i) => i.type == ItemType.password).toList();
  static List<Item> get drafts => ItemService.drafts;
  static List<Item> versionsOf(String purposeId) => ItemService.versionsOf(purposeId);
  static void maskAll() => ItemService.maskAll();
  static Future<void> incrementUsage(String passwordId, {required bool copy}) =>
      ItemService.incrementUsage(passwordId, copy: copy);
  static Future<void> init() => ItemService.init();
  static Future addNewPassword(Item p) => ItemService.personal.add(p);
  static Future updatePassword(Item p) => ItemService.personal.updateVersion(p);
  static Future deletePassword(Item p) => ItemService.personal.delete(p);
  // kCryptoVersion / _requireKey / encode / decode from Task 3 stay here.
}
```
`passwords_provider.dart` `addDraft`/`saveDraft`: replace `PasswordService.passwords.add(draft)` + `draft.push()` with `await ItemService.personal.save(draft)`; the manual `isLatest` loop in `saveDraft` goes away (`save` recomputes).
`add_new_password_screen.dart`: the two `getPasswordCol()` from Task 4 → `FirestorePathsService.getItemsCol()`.
`migration_service.dart`: `PasswordService.passwords` still resolves (crypto migration keeps working on items).
`init_service.dart`: `PasswordService.init()` → `ItemService.init()`; **`PersonService.initPerson()` must complete before `ItemService.init()`** (it reads `dataVersion`), so replace the `Future.wait` with two sequential awaits.

- [ ] **Step 4: Run tests + analyze**

Run: `flutter analyze && flutter test` → clean, all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services lib/models lib/providers lib/screens/add_new_password_screen.dart test/item_repository_test.dart
git commit -m "ItemRepository + ItemService; personal items collection with legacy fallback"
```

---

### Task 6: Silent, verified migration `passwords` → `items`

**Files:**
- Create: `lib/services/items_migration_service.dart`
- Modify: `lib/services/item_service.dart` (`init` runs the migration first)
- Test: `test/items_migration_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class ItemsMigrationService {
    ItemsMigrationService({required CollectionReference from, required CollectionReference to, required DocumentReference profile});
    Future<bool> run();   // true when the profile now says dataVersion >= 3
  }
  ```

- [ ] **Step 1: Write the failing test**

```dart
// test/items_migration_test.dart
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
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/items_migration_test.dart` → FAIL.

- [ ] **Step 3: Implement**

```dart
// lib/services/items_migration_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import 'person_service.dart';

/// One-time move of legacy `passwords` docs into the unified `items`
/// collection. No crypto involved (blobs are copied byte-for-byte), so it runs
/// silently on load. Copy → verify → delete; safe to rerun at any point.
class ItemsMigrationService {
  ItemsMigrationService({required this.from, required this.to, required this.profile});

  final CollectionReference from;
  final CollectionReference to;
  final DocumentReference profile;

  static const int _batchLimit = 400;

  Future<bool> run() async {
    final legacy = (await from.get()).docs;

    // 1) Copy (merge, so a resumed run doesn't clobber a finished copy).
    for (var i = 0; i < legacy.length; i += _batchLimit) {
      final batch = to.firestore.batch();
      for (final d in legacy.skip(i).take(_batchLimit)) {
        batch.set(to.doc(d.id), _convert(d.data() as Map<String, dynamic>), SetOptions(merge: true));
      }
      await batch.commit();
    }

    // 2) Verify every id exists in the target before touching the source.
    for (final d in legacy) {
      if (!(await to.doc(d.id).get()).exists) {
        throw StateError('Migration verification failed for ${d.id}');
      }
    }

    // 3) Delete originals.
    for (var i = 0; i < legacy.length; i += _batchLimit) {
      final batch = from.firestore.batch();
      for (final d in legacy.skip(i).take(_batchLimit)) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }

    // 4) Mark the account.
    await profile.set({'dataVersion': PersonService.kDataVersion}, SetOptions(merge: true));
    return true;
  }

  static Map<String, dynamic> _convert(Map<String, dynamic> o) {
    final out = Map<String, dynamic>.from(o);
    out['type'] = 'password';
    out['title'] = o['title'] ?? o['website'];
    out.remove('website');
    return out;
  }
}
```

`item_service.dart` — `init()` becomes:
```dart
  static Future<void> init() async {
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
      } catch (_) {
        // Fall back to reading both collections; retried on next launch.
      }
    }
    await personal.load(
        extraSources: migrated ? const [] : [FirestorePathsService.getPasswordCol()]);
  }
```

- [ ] **Step 4: Run tests + analyze**

Run: `flutter analyze && flutter test` → clean, all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/items_migration_service.dart lib/services/item_service.dart test/items_migration_test.dart
git commit -m "Migrate legacy passwords into the items collection (copy, verify, delete)"
```

---

### Task 7: Providers + home list for all types + FAB type chooser

**Files:**
- Create: `lib/providers/items_provider.dart`
- Modify: `lib/providers/passwords_provider.dart` (thin derived provider)
- Modify: `lib/screens/home_page.dart` (tile per type, search on title, FAB sheet)
- Modify: `lib/screens/password_detail_screen.dart`, `lib/screens/add_new_password_screen.dart` (`ref.read(itemsProvider.notifier)` for add/update/delete/drafts)

**Interfaces:**
- Produces:
  ```dart
  class ItemsNotifier extends Notifier<List<Item>> {
    void refresh(); void maskAll();
    Future<void> add(Item); Future<void> updateVersion(Item); Future<void> save(Item); Future<void> delete(Item);
    Future<void> addDraft(Item); Future<void> saveDraft(Item, {bool finalize});
  }
  final itemsProvider = NotifierProvider<ItemsNotifier, List<Item>>;
  final passwordsProvider = Provider<List<Item>>((ref) => ref.watch(itemsProvider).where((i) => i.type == ItemType.password).toList());
  ```

- [ ] **Step 1: Implement `items_provider.dart`** (moves the sorting logic from `PasswordsNotifier`, drafts first, then by usage, then timestamp; all types)

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../services/item_service.dart';

class ItemsNotifier extends Notifier<List<Item>> {
  @override
  List<Item> build() => _combined();

  List<Item> _combined() {
    int ts(Item i) => i.timestamp?.millisecondsSinceEpoch ?? 0;
    int usage(Item i) => i.copyCount + i.viewCount;
    final drafts = ItemService.drafts..sort((a, b) => ts(b).compareTo(ts(a)));
    final entries = ItemService.latest
      ..sort((a, b) {
        final byUsage = usage(b).compareTo(usage(a));
        return byUsage != 0 ? byUsage : ts(b).compareTo(ts(a));
      });
    return [...drafts, ...entries];
  }

  void refresh() => state = _combined();
  void maskAll() { ItemService.maskAll(); refresh(); }

  Future<void> add(Item item) async { await ItemService.personal.add(item); refresh(); }
  Future<void> updateVersion(Item item) async { await ItemService.personal.updateVersion(item); refresh(); }
  Future<void> save(Item item) async { await ItemService.personal.save(item); refresh(); }
  Future<void> delete(Item item) async { await ItemService.personal.delete(item); refresh(); }
  Future<void> addDraft(Item draft) => save(draft);
  Future<void> saveDraft(Item draft, {bool finalize = false}) => save(draft);
}

final itemsProvider = NotifierProvider<ItemsNotifier, List<Item>>(ItemsNotifier.new);
```

`passwords_provider.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/item.dart';
import '../models/item_type.dart';
import 'items_provider.dart';

/// Passwords only (drafts included), derived from [itemsProvider].
final passwordsProvider = Provider<List<Item>>(
    (ref) => ref.watch(itemsProvider).where((i) => i.type == ItemType.password).toList());
```
Callers of `ref.read(passwordsProvider.notifier)` → `ref.read(itemsProvider.notifier)` (`add`, `update`→`updateVersion`, `delete`, `addDraft`, `saveDraft`, `maskAll`).

- [ ] **Step 2: Home list**

In `home_page.dart`:
- `List<Password> get passwords` → `List<Item> get items` reading `ref.watch(itemsProvider)`; search matches `title` and `username` (same normalisation as today).
- `getSinglePasswordField(Item it)`:
  - leading avatar: password → first letter of `title` (as today); other types → `Icon(it.type.icon)`.
  - subtitle: password → username + masked value line (as today); card/note → `Text(it.type.label)` only (no sensitive preview).
  - `onTap`: password → copy (as today); draft → editor; card/note → open detail. `onLongPress`: password only.
- FAB `onPressed`: `showModalBottomSheet` with `ListTile`s for `ItemType.password` ("Passwort"), `ItemType.card` ("Karte"), `ItemType.note` ("Notiz"); document/file listed but disabled with subtitle "Bald verfügbar". Selecting pushes `AddNewPasswordScreen()`, `CardEditorScreen()`, `NoteEditorScreen()` (Task 8).
- `_open(Item it)`: password → `PasswordDetailScreen`, else `ItemDetailScreen(it)` (Task 9). Until Tasks 8/9 exist, add the screens as stubs in this task only if needed to compile — preferable: implement Task 8/9 files first as minimal `Scaffold`s in the same commit sequence, or land Task 7 after 8/9. **Order for execution: 8 → 9 → 7** if you want every commit to compile; the plan lists them here for readability.

- [ ] **Step 3: Run analyze + tests, then a manual smoke run** (`flutter run -d macos` or iOS simulator): list shows existing passwords, tap copies, FAB sheet appears.

- [ ] **Step 4: Commit**

```bash
git add lib/providers lib/screens/home_page.dart lib/screens/password_detail_screen.dart lib/screens/add_new_password_screen.dart
git commit -m "Home list and providers work on items of every type; FAB type chooser"
```

---

### Task 8: Card and note editors

**Files:**
- Create: `lib/screens/card_editor_screen.dart`
- Create: `lib/screens/note_editor_screen.dart`
- Create: `lib/services/card_number_formatter.dart` + Test: `test/card_number_formatter_test.dart`

**Interfaces:**
- Produces: `CardEditorScreen({Item? existing})`, `NoteEditorScreen({Item? existing})` — pop after save. `CardNumberFormatter extends TextInputFormatter` (digits grouped in 4s, max 19 digits).

- [ ] **Step 1: Failing formatter test**

```dart
// test/card_number_formatter_test.dart
import 'package:cipher_eye/services/card_number_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TextEditingValue fmt(String s) => CardNumberFormatter()
      .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length)));

  test('groups digits in fours and drops non-digits', () {
    expect(fmt('4111111111111111').text, '4111 1111 1111 1111');
    expect(fmt('41a1-1').text, '4111');
  });
  test('caps at 19 digits', () {
    expect(fmt('12345678901234567890123').text, '1234 5678 9012 3456 789');
  });
  test('cursor stays at the end', () {
    final v = fmt('12345');
    expect(v.selection.baseOffset, v.text.length);
  });
}
```

- [ ] **Step 2: Run → FAIL. Implement**

```dart
// lib/services/card_number_formatter.dart
import 'package:flutter/services.dart';

class CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final capped = digits.length > 19 ? digits.substring(0, 19) : digits;
    final buf = StringBuffer();
    for (var i = 0; i < capped.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write(' ');
      buf.write(capped[i]);
    }
    final text = buf.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
```

- [ ] **Step 3: Card editor**

```dart
// lib/screens/card_editor_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../models/item_payload.dart';
import '../models/item_type.dart';
import '../providers/items_provider.dart';
import '../providers/key_provider.dart';
import '../services/card_number_formatter.dart';
import '../services/firestore_paths_service.dart';
import '../services/haptics.dart';
import '../widgets/app_text_field.dart';

class CardEditorScreen extends ConsumerStatefulWidget {
  const CardEditorScreen({super.key, this.existing});
  final Item? existing;
  @override
  ConsumerState<CardEditorScreen> createState() => _CardEditorScreenState();
}

class _CardEditorScreenState extends ConsumerState<CardEditorScreen> {
  final _title = TextEditingController();
  final _number = TextEditingController();
  final _holder = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();
  final _pin = TextEditingController();
  final _iban = TextEditingController();
  final _bank = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _title.text = e.title ?? '';
      try {
        final c = CardData.decode(e.decrypted());
        _number.text = c.number ?? ''; _holder.text = c.holder ?? '';
        _expiry.text = c.expiry ?? ''; _cvv.text = c.cvv ?? ''; _pin.text = c.pin ?? '';
        _iban.text = c.iban ?? ''; _bank.text = c.bank ?? ''; _note.text = c.note ?? '';
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _number, _holder, _expiry, _cvv, _pin, _iban, _bank, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || !ref.read(hasKeyProvider)) return;
    setState(() => _saving = true);
    final data = CardData(
      number: _number.text.trim(), holder: _holder.text.trim(), expiry: _expiry.text.trim(),
      cvv: _cvv.text.trim(), pin: _pin.text.trim(), iban: _iban.text.trim(),
      bank: _bank.text.trim(), note: _note.text.trim(),
    );
    final notifier = ref.read(itemsProvider.notifier);
    if (widget.existing != null) {
      widget.existing!.setPayload(title: _title.text.trim(), plainJson: data.encode());
      await notifier.save(widget.existing!);
    } else {
      await notifier.add(Item.payload(
        col: FirestorePathsService.getItemsCol(), type: ItemType.card,
        title: _title.text.trim(), plainJson: data.encode(),
      ));
    }
    if (!mounted) return;
    Haptics.success();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Neue Karte' : 'Karte bearbeiten')),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppTextField(controller: _title, label: 'Bezeichnung', hint: 'z. B. Visa Sparkasse', prefixIcon: Icons.credit_card, onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          AppTextField(controller: _number, label: 'Kartennummer', hint: '1234 5678 9012 3456', prefixIcon: Icons.numbers,
              keyboardType: TextInputType.number, inputFormatters: [CardNumberFormatter()]),
          const SizedBox(height: 12),
          AppTextField(controller: _holder, label: 'Karteninhaber', hint: 'Name wie auf der Karte', prefixIcon: Icons.person_outline),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: AppTextField(controller: _expiry, label: 'Gültig bis', hint: 'MM/JJ', prefixIcon: Icons.event, keyboardType: TextInputType.datetime)),
            const SizedBox(width: 12),
            Expanded(child: AppTextField(controller: _cvv, label: 'CVV', hint: '123', prefixIcon: Icons.lock_outline, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
          ]),
          const SizedBox(height: 12),
          AppTextField(controller: _pin, label: 'PIN', hint: 'optional', prefixIcon: Icons.pin_outlined, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
          const SizedBox(height: 12),
          AppTextField(controller: _iban, label: 'IBAN', hint: 'optional', prefixIcon: Icons.account_balance_outlined),
          const SizedBox(height: 12),
          AppTextField(controller: _bank, label: 'Bank', hint: 'optional', prefixIcon: Icons.account_balance),
          const SizedBox(height: 12),
          AppTextField(controller: _note, label: 'Notiz', hint: 'optional', prefixIcon: Icons.notes, maxLines: 3),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _title.text.trim().isEmpty || _saving ? null : _save,
              child: Padding(padding: const EdgeInsets.all(16), child: _saving ? const CircularProgressIndicator() : const Text('Speichern')),
            ),
          ),
        ],
      ),
    );
  }
}
```
`lib/widgets/app_text_field.dart` already has `keyboardType`; add `List<TextInputFormatter>? inputFormatters` and `int maxLines = 1` (constructor params + fields, passed through to the inner text field; `import 'package:flutter/services.dart'`).

- [ ] **Step 4: Note editor** — same skeleton with only `_title` (label 'Titel', hint 'z. B. WLAN Zuhause', icon `Icons.sticky_note_2_outlined`) and `_text` (`AppTextField(... label: 'Notiz', maxLines: 10)`), payload `NoteData(text: _text.text)`, `ItemType.note`, titles 'Neue Notiz' / 'Notiz bearbeiten'.

- [ ] **Step 5: Run analyze + tests, commit**

```bash
git add lib/screens/card_editor_screen.dart lib/screens/note_editor_screen.dart lib/services/card_number_formatter.dart lib/widgets/app_text_field.dart test/card_number_formatter_test.dart
git commit -m "Card and note editors with encrypted payloads"
```

---

### Task 9: `CopyRow` widget + generic item detail screen

**Files:**
- Create: `lib/widgets/copy_row.dart` (extract from `password_detail_screen.dart` `_copyRow`)
- Create: `lib/screens/item_detail_screen.dart`
- Modify: `lib/screens/password_detail_screen.dart` (use `CopyRow`)

**Interfaces:**
- Produces: `CopyRow({required String label, required String value, required VoidCallback onTap, VoidCallback? onLongPress, Widget? trailing, bool mono = false})`.
- Produces: `ItemDetailScreen(Item item)` for `card`/`note` (document/file added by the attachments plan).

- [ ] **Step 1: Extract `CopyRow`**

Move `_copyRow` from `password_detail_screen.dart` into `lib/widgets/copy_row.dart` as a `StatelessWidget` with the same layout (Material + InkWell, label small, value 16pt, trailing copy icon by default). Replace the two call sites in `password_detail_screen.dart` with `CopyRow(...)`.

- [ ] **Step 2: Item detail screen**

```dart
// lib/screens/item_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../models/item_payload.dart';
import '../models/item_type.dart';
import '../providers/items_provider.dart';
import '../providers/key_provider.dart';
import '../services/clipboard_service.dart';
import '../services/haptics.dart';
import '../services/history_service.dart';
import '../services/item_service.dart';
import '../widgets/copy_row.dart';
import 'card_editor_screen.dart';
import 'note_editor_screen.dart';

class ItemDetailScreen extends ConsumerStatefulWidget {
  const ItemDetailScreen(this.item, {super.key});
  final Item item;
  @override
  ConsumerState<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<ItemDetailScreen> {
  final Set<String> _revealed = {};
  Item get item => widget.item;

  Future<void> _copy(String label, String value) async {
    if (!ref.read(hasKeyProvider)) return;
    Haptics.selection();
    await ClipboardService.copySensitive(value);
    HistoryService.saveCopyHistory(item.id!);
    ItemService.incrementUsage(item.id!, copy: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label kopiert – wird in 30 s aus der Zwischenablage gelöscht'),
      duration: const Duration(seconds: 2),
    ));
  }

  void _toggle(String key) {
    Haptics.selection();
    setState(() => _revealed.contains(key) ? _revealed.remove(key) : _revealed.add(key));
    if (_revealed.contains(key)) {
      HistoryService.saveViewHistory(item.id!);
      ItemService.incrementUsage(item.id!, copy: false);
    }
  }

  Widget _secret(String key, String label, String? value, {bool mono = true}) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    final shown = _revealed.contains(key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CopyRow(
        label: label,
        value: shown ? value : List.filled(value.length.clamp(4, 16), '•').join(),
        mono: mono,
        onTap: () => _copy(label, value),
        onLongPress: () => _toggle(key),
        trailing: IconButton(
          tooltip: shown ? 'Verbergen' : 'Anzeigen',
          icon: Icon(shown ? Icons.visibility : Icons.visibility_off),
          onPressed: () => _toggle(key),
        ),
      ),
    );
  }

  Widget _plain(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CopyRow(label: label, value: value, onTap: () => _copy(label, value)),
    );
  }

  Future<void> _edit() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) =>
        item.type == ItemType.card ? CardEditorScreen(existing: item) : NoteEditorScreen(existing: item)));
    if (mounted) setState(() {});
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${item.type.label} löschen'),
        content: Text('„${item.title ?? ''}“ wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Haptics.warning();
    await ref.read(itemsProvider.notifier).delete(item);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String? plain;
    try { plain = ref.watch(hasKeyProvider) ? item.decrypted() : null; } catch (_) { plain = null; }
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(item.title ?? item.type.label),
        actions: [
          IconButton(tooltip: 'Bearbeiten', icon: const Icon(Icons.edit_outlined), onPressed: _edit),
          IconButton(tooltip: 'Löschen', icon: Icon(Icons.delete_outline, color: scheme.error), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (plain == null)
            const Text('Kein Encryption-Key gesetzt — Inhalte können nicht angezeigt werden.')
          else if (item.type == ItemType.card) ..._cardBody(CardData.decode(plain))
          else if (item.type == ItemType.note) ..._noteBody(NoteData.decode(plain)),
          const SizedBox(height: 8),
          Text('Antippen zum Kopieren · lange drücken zum Anzeigen',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  List<Widget> _cardBody(CardData c) => [
        _secret('number', 'Kartennummer', c.number),
        _plain('Karteninhaber', c.holder),
        _plain('Gültig bis', c.expiry),
        _secret('cvv', 'CVV', c.cvv),
        _secret('pin', 'PIN', c.pin),
        _plain('IBAN', c.iban),
        _plain('Bank', c.bank),
        _plain('Notiz', c.note),
      ];

  List<Widget> _noteBody(NoteData n) => [
        _secret('text', 'Notiz', n.text, mono: false),
      ];
}
```

- [ ] **Step 3: Analyze, tests, manual smoke** (create a card, open it, tap number → copied; long-press → revealed; edit; delete).

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/copy_row.dart lib/screens/item_detail_screen.dart lib/screens/password_detail_screen.dart
git commit -m "Item detail screen for cards and notes; shared CopyRow"
```

---

### Task 10: Retire the `Password` alias, rename, final sweep

**Files:**
- Delete: `lib/models/password.dart`
- Modify: every `import '../models/password.dart'` → `item.dart`; every `Password` type name → `Item`
- Modify: `lib/services/password_service.dart` → keep **only** `kCryptoVersion/_requireKey/encode/decode` (still used by `Item`); the list/CRUD forwarders are removed once no caller remains (`grep -rn "PasswordService\." lib`).
- Modify: `test/crypto_migration_test.dart` if it references removed members.

- [ ] **Step 1: Replace usages**

Run: `grep -rln "models/password.dart\|\bPassword\b" lib test` and fix each file (`Password` → `Item`, imports → `item.dart`).

- [ ] **Step 2: Delete alias file, prune `PasswordService`**

Delete `lib/models/password.dart`. Remove forwarders from `PasswordService` whose callers are gone; keep the crypto trio and its doc comment.

- [ ] **Step 3: Verify**

Run: `flutter analyze && flutter test` → clean, all PASS. Then `flutter build ios --debug --no-codesign` → succeeds.

- [ ] **Step 4: Manual end-to-end** on simulator/Mac: existing account logs in → passwords appear (migration ran silently; Firestore console shows `items`, `passwords` empty) → create password, card, note → detail copy/reveal → delete → relaunch, all still there.

- [ ] **Step 5: Commit**

```bash
git add -A lib test
git commit -m "Retire Password alias; Item is the single model"
```
