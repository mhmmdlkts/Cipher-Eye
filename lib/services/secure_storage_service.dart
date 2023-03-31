import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const String _storageKey = 'encryption_key';
  static const _secureStorage = FlutterSecureStorage();
  static String? key;

  static Future init() async {
    key = await _getKey();
  }

  static Future putKey(String k) async {
    await _secureStorage.write(key: _storageKey, value: k);
    key = k;
  }

  static Future<String?> _getKey() async {
    return await _secureStorage.read(key: _storageKey);
  }

  static Future removeKey() async {
    await _secureStorage.delete(key: _storageKey);
    key = null;
  }
}