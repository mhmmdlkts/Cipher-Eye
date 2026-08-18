import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/firestore_paths_service.dart';

class Person {
  String? uid;
  String? name;
  List<String> usernames = [];

  /// Aggregate crypto/security version of this profile. Only bumped to the
  /// current version once every password entry has been migrated. Used as a
  /// fast "all migrated" check on launch — decryption always relies on the
  /// per-item [Item.v], never on this flag.
  int securityVersion = 1;

  /// Data-layout version of this account. 3 = passwords live in /items.
  int dataVersion = 1;

  Person.fromSnapshot(DocumentSnapshot<Object?> snap) {
    if (snap.data() == null) {
      return;
    }
    Map<String, dynamic> o = snap.data() as Map<String, dynamic>;

    uid = snap.id;
    if (o.containsKey('name')) {
      name = o['name'];
    }
    if (o.containsKey('name')) {
      name = o['name'];
    }
    if (o.containsKey('usernames')) {
      List<dynamic> a = o['usernames'];
      usernames = a.map((e) => e.toString()).toList();
    }
    if (o.containsKey('securityVersion')) {
      securityVersion = (o['securityVersion'] as num).toInt();
    }
    if (o.containsKey('dataVersion')) {
      dataVersion = (o['dataVersion'] as num).toInt();
    }
  }

  Map<String, dynamic> toJson({bool withNull = true}) {
    Map<String, dynamic> map = {
      'name': name,
      'usernames': usernames,
      'securityVersion': securityVersion,
      'dataVersion': dataVersion,
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

  Future push() async => await FirestorePathsService.getUserDoc().set(toJson());
  Future update() async => await FirestorePathsService.getUserDoc().update(toJson(withNull: false));
}
