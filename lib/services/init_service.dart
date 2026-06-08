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
    try {
      await SecureStorageService.init();
      await Future.wait([
        PersonService.initPerson(),
        PasswordService.init(),
      ]);
      isInited = true;
    } finally {
      isIniting = false;
    }
    HistoryService.saveInitHistory();
  }

  static void cleanCache() {
    isInited = false;
    isIniting = false;
  }
}