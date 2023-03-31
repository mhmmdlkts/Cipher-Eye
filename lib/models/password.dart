import 'package:cipher_eye/services/history_service.dart';
import 'package:cipher_eye/services/password_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/firestore_paths_service.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class Password {
  String? id;
  String? username;
  Timestamp? timestamp;
  String? purposeId;
  String? website;
  String? value;
  bool isLatest = false;
  bool isVisible = false;
  String? _plainText;

  Password.create({
    required this.website,
    required this.username,
    required String plaintText}) {
    id = FirestorePathsService.getPasswordCol().doc().id;
    purposeId = purposeIdCreate(website: website??'', username: username??'');
    value = PasswordService.encode(plaintText);
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
    if (o.containsKey('purposeId')) {
      purposeId = o['purposeId'];
    }
    if (o.containsKey('timestamp')) {
      timestamp = o['timestamp'];
    }
  }

  Map<String, dynamic> toJson({bool withNull = true}) {
    Map<String, dynamic> map = {
      'value': value,
      'website': website,
      'username': username,
      'purposeId': purposeId,
      'timestamp': timestamp,
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
      _plainText = PasswordService.decode(value!);
    }
    return _plainText!;
  }
}
