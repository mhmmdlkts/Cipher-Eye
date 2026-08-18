import '../models/history.dart';

class HistoryService {
  static bool locationDenied = true;

  static Future<void> _save(String action, {String? itemId, String? vaultId}) async {
    final h = History.create(action: action, password: itemId, vaultId: vaultId);
    await h.init();
    await h.push();
  }

  static Future<void> saveInitHistory() => _save('init');

  static Future<void> saveCreateHistory(String itemId, {String? vaultId}) =>
      _save('create', itemId: itemId, vaultId: vaultId);

  static Future<void> saveDeleteHistory(String itemId, {String? vaultId}) =>
      _save('delete', itemId: itemId, vaultId: vaultId);

  static Future<void> saveCopyHistory(String itemId, {String? vaultId}) =>
      _save('copy', itemId: itemId, vaultId: vaultId);

  static Future<void> saveViewHistory(String itemId, {String? vaultId}) =>
      _save('view', itemId: itemId, vaultId: vaultId);

  static Future<void> saveUpdateHistory(String itemId, {String? vaultId}) =>
      _save('update', itemId: itemId, vaultId: vaultId);

  static Future<void> saveExportHistory(String itemId, {String? vaultId}) =>
      _save('export', itemId: itemId, vaultId: vaultId);

  static Future<void> saveShowKey() => _save('key');

  /// Repository hook: create/update/delete events by action name.
  static void log(String action, String itemId, {String? vaultId}) {
    switch (action) {
      case 'create':
        saveCreateHistory(itemId, vaultId: vaultId);
      case 'update':
        saveUpdateHistory(itemId, vaultId: vaultId);
      case 'delete':
        saveDeleteHistory(itemId, vaultId: vaultId);
    }
  }
}
