import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/person.dart';
import 'firestore_paths_service.dart';

class PersonService {
  /// Data layout the app writes. 3 = unified `items` collection.
  static const int kDataVersion = 3;

  static bool _isInited = false;
  static late Person person;

  static Future initPerson({DateTime? now}) async {
    DocumentSnapshot snapshot = await FirestorePathsService.getUserDoc().get();
    person = Person.fromSnapshot(snapshot);

    _isInited = true;
  }

  static bool isInited() => _isInited;

  static void cleanPerson() {
    _isInited = false;
  }
}