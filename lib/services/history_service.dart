import '../models/history.dart';

class HistoryService {
  static bool locationDenied = true;

  static Future<void> saveInitHistory() async {
    History openAppHistory = History.create(action: 'init');
    await openAppHistory.init();
    await openAppHistory.push();
  }

  static Future<void> saveCreateHistory(String passwordId) async {
    History openAppHistory = History.create(action: 'create', password: passwordId);
    await openAppHistory.init();
    await openAppHistory.push();
  }

  static Future<void> saveCopyHistory(String passwordId) async {
    History copyHistory = History.create(action: 'copy', password: passwordId);
    await copyHistory.init();
    await copyHistory.push();
  }
}