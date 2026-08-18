import 'package:cipher_eye/services/history_service.dart';
import 'package:cipher_eye/services/item_service.dart';
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
      // The profile (dataVersion) decides how items are loaded → sequential.
      await PersonService.initPerson();
      await ItemService.init();
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