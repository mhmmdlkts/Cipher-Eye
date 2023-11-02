import 'package:cipher_eye/services/firestore_paths_service.dart';
import 'package:cipher_eye/services/history_service.dart';
import 'package:cipher_eye/services/secure_storage_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart';

import '../models/password.dart';

class PasswordService {
  static final List<Password> passwords = [];
  static List<Password> get newPasswords => passwords.where((pass) {return pass.isLatest;}).toList();
  static final Key _aesKey = Key.fromUtf8(SecureStorageService.key!);
  static final IV _iv = IV.fromLength(16);

  static Future<void> init() async {
    QuerySnapshot querySnapshot = await FirestorePathsService.getPasswordCol()
        .orderBy('purposeId').orderBy('timestamp', descending: true).get();

    passwords.clear();
    String? lastPurposeId;
    querySnapshot.docs.forEach((doc) {
      Password password = Password.fromSnapshot(doc);
      if (lastPurposeId == null || lastPurposeId != password.purposeId) {
        password.isLatest = true;
        lastPurposeId = password.purposeId;
      }
      passwords.add(password);
    });
  }

  static Future addNewPassword(Password password) async {
    passwords.where((element) => element.purposeId == password.purposeId).forEach((element) {element.isLatest = false;});
    password.isLatest = true;
    passwords.add(password);
    HistoryService.saveCreateHistory(password.id!);
    password.push();
  }

  static String encode(String value) {
    final encrypter = Encrypter(AES(_aesKey));
    final encrypted = encrypter.encrypt(value, iv: _iv);
    return encrypted.base64;
  }

  static String decode(String value) {
    final encrypter = Encrypter(AES(_aesKey));
    final encrypted = Encrypted.fromBase64(value);
    return encrypter.decrypt(encrypted, iv: _iv);
  }

  static Future deletePassword(Password password) async {
    HistoryService.saveDeleteHistory(password.id!);
    passwords.removeWhere((element) => element.purposeId == password.purposeId);
    await FirestorePathsService.getPasswordDoc(passwordId: password.id!).delete();
  }

}