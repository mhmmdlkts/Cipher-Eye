import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestorePathsService {

  static const String _usersKey = "users";
  static const String _historyKey = "history";
  static const String _passwordsKey = "passwords";

  static DocumentReference getUserDoc() => FirebaseFirestore.instance.collection(_usersKey).doc(FirebaseAuth.instance.currentUser!.uid);

  static CollectionReference getHistoryCol() => getUserDoc().collection(_historyKey);
  static DocumentReference geHistoryDoc({required String historyId}) => getHistoryCol().doc(historyId);

  static CollectionReference getPasswordCol() => getUserDoc().collection(_passwordsKey);
  static DocumentReference getPasswordDoc({required String passwordId}) => getPasswordCol().doc(passwordId);
}