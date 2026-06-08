import 'package:cipher_eye/services/history_service.dart';
import 'package:cipher_eye/services/password_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/firestore_paths_service.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class Password implements Comparable<Password>{
  String? id;
  String? username;
  Timestamp? timestamp;
  String? purposeId;
  String? website;
  String? value;
  String? iv;
  int v = 1;
  bool isFavorite = false;
  int copyCount = 0;
  int viewCount = 0;
  bool isLatest = false;
  bool isVisible = false;
  String? _plainText;

  Password.create({
    required this.website,
    required this.username,
    required String plaintText,
    this.isFavorite = false,}) {
    id = FirestorePathsService.getPasswordCol().doc().id;
    purposeId = purposeIdCreate(website: website??'', username: username??'');
    final encoded = PasswordService.encode(plaintText);
    value = encoded.value;
    iv = encoded.iv;
    v = PasswordService.kCryptoVersion;
    timestamp = Timestamp.now();
  }

  String purposeIdCreate({required String website, required String username}) {
    String combined = website + username;
    List<int> bytes = utf8.encode(combined);
    Digest sha256Digest = sha256.convert(bytes);
    return sha256Digest.toString();
  }

  Password.fromSnapshot(DocumentSnapshot<Object?> snap) {
    if (snap.data() == null) {
      return;
    }
    Map<String, dynamic> o = snap.data() as Map<String, dynamic>;

    id = snap.id;
    if (o.containsKey('username')) {
      username = o['username'];
    }
    if (o.containsKey('website')) {
      website = o['website'];
    }
    if (o.containsKey('value')) {
      value = o['value'];
    }
    if (o.containsKey('iv')) {
      iv = o['iv'];
    }
    if (o.containsKey('v')) {
      v = (o['v'] as num).toInt();
    }
    if (o.containsKey('purposeId')) {
      purposeId = o['purposeId'];
    }
    if (o.containsKey('timestamp')) {
      timestamp = o['timestamp'];
    }
    if (o.containsKey('isFavorite')) {
      isFavorite = o['isFavorite'];
    }
    if (o.containsKey('copyCount')) {
      copyCount = (o['copyCount'] as num).toInt();
    }
    if (o.containsKey('viewCount')) {
      viewCount = (o['viewCount'] as num).toInt();
    }
  }

  Map<String, dynamic> toJson({bool withNull = true}) {
    Map<String, dynamic> map = {
      'value': value,
      'iv': iv,
      'v': v,
      'website': website,
      'username': username,
      'purposeId': purposeId,
      'timestamp': timestamp,
      'isFavorite': isFavorite,
    };
    if (withNull) {
      return map;
    }
    Map<String, dynamic> newMap = {};
    map.forEach((key, value) {
      if (value != null) {
        newMap.addAll({key: value});
      }
    });
    return newMap;
  }

  Future push() async => await FirestorePathsService.getPasswordDoc(passwordId: id!).set(toJson());
  Future update() async => await FirestorePathsService.getPasswordDoc(passwordId: id!).update(toJson(withNull: false));

  String getPlainText() {
    if (_plainText == null) {
      HistoryService.saveCopyHistory(id!);
      _plainText = PasswordService.decode(value: value!, iv: iv, v: v);
    }
    return _plainText!;
  }

  /// Decrypts the value WITHOUT logging a copy-history event — for on-screen
  /// display (revealing). Logging is done explicitly when the user copies.
  String decrypted() => PasswordService.decode(value: value!, iv: iv, v: v);

  bool get needsMigration => v < PasswordService.kCryptoVersion;

  /// Re-encrypts this entry into the current scheme (v2, AES-GCM) and persists
  /// value/iv/v. Decrypts the legacy blob in place — the plaintext never leaves
  /// the device and is not logged to history.
  Future<void> migrateCrypto() async {
    if (!needsMigration) {
      return;
    }
    final plain = PasswordService.decode(value: value!, iv: iv, v: v);
    final encoded = PasswordService.encode(plain);

    // Safety net: never overwrite the only stored copy unless the freshly
    // encrypted blob round-trips back to the exact same plaintext. GCM is
    // authenticated, so a bad blob would otherwise be unrecoverable.
    final roundTrip = PasswordService.decode(
        value: encoded.value, iv: encoded.iv, v: PasswordService.kCryptoVersion);
    if (roundTrip != plain) {
      throw StateError('Migration self-check failed for password $id');
    }

    await FirestorePathsService.getPasswordDoc(passwordId: id!).update(
        {'value': encoded.value, 'iv': encoded.iv, 'v': PasswordService.kCryptoVersion});

    // Only update in-memory state after the write succeeds, so a failure leaves
    // the object consistent with what is still stored (v1).
    value = encoded.value;
    iv = encoded.iv;
    v = PasswordService.kCryptoVersion;
    _plainText = null;
  }

  @override
  int compareTo(Password other) {
    if (isFavorite && !other.isFavorite) {
      return -1;
    }
    if (!isFavorite && other.isFavorite) {
      return 1;
    }
    return other.timestamp?.compareTo(timestamp??Timestamp(0, 0))??0;
  }
}
