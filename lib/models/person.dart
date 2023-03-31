import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/firestore_paths_service.dart';

class Person {
  String? uid;
  String? name;
  List<String> usernames = [];

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
  }

  Map<String, dynamic> toJson({bool withNull = true}) {
    Map<String, dynamic> map = {
      'name': name,
      'usernames': usernames,
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
