import 'package:cipher_eye/models/password.dart';
import 'package:cipher_eye/services/history_service.dart';
import 'package:cipher_eye/services/password_service.dart';
import 'package:cipher_eye/services/person_service.dart';
import 'package:cipher_eye/services/secure_storage_service.dart';

class InitService {

  static bool isInited = false;
  static bool isIniting = false;

  static Future init({bool force = false}) async {
    if ((isIniting || isInited) && !force) {
      return;
    }
    isIniting = true;
    await SecureStorageService.init();
    List<Future> toDo = [
      PersonService.initPerson(),
      PasswordService.init(),
    ];
    await Future.wait(toDo);
    isInited = true;
    isIniting = false;
    HistoryService.saveInitHistory();
  }

  static cleanCache() {
    isInited = false;
    isIniting = false;
  }
}