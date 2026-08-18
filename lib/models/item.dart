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
  Item.draft(
      {required CollectionReference col,
      this.username,
      required String plainText}) {
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
    required this.title,
    required String plainJson,
    this.isFavorite = false,
  }) {
    ref = col.doc();
    id = ref!.id;
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

  /// Updates a password's editable fields (re-encrypting). Keeps a draft a
  /// draft unless [finalize] is set, which promotes it to a real entry.
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

  static String purposeIdCreate(
          {required String website, required String username}) =>
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
    return {
      for (final e in map.entries)
        if (e.value != null) e.key: e.value
    };
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

  /// Decrypts WITHOUT logging a history event — for on-screen display.
  String decrypted() => PasswordService.decode(value: value!, iv: iv, v: v);

  bool get needsMigration => v < PasswordService.kCryptoVersion;

  /// Re-encrypts this entry into the current scheme (v2, AES-GCM) and persists
  /// value/iv/v. The plaintext never leaves the device and is not logged.
  Future<void> migrateCrypto() async {
    if (!needsMigration) return;
    final plain = PasswordService.decode(value: value!, iv: iv, v: v);
    final encoded = PasswordService.encode(plain);
    // Never overwrite the only stored copy unless the fresh blob round-trips.
    final roundTrip = PasswordService.decode(
        value: encoded.value,
        iv: encoded.iv,
        v: PasswordService.kCryptoVersion);
    if (roundTrip != plain) {
      throw StateError('Migration self-check failed for item $id');
    }
    await ref!.update({
      'value': encoded.value,
      'iv': encoded.iv,
      'v': PasswordService.kCryptoVersion
    });
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
