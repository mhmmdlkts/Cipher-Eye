import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const String _storagePin = 'pin';
  static const String _storageKey = 'encryption_key';
  static const _secureStorage = FlutterSecureStorage();
  static String? key;
  static String? pin;

  static Future init() async {
    key = await _getKey();
    pin = await _getPin();
  }

  static Future putPin(String p) async {
    await _secureStorage.write(key: _storagePin, value: p);
    pin = p;
  }

  static Future putKey(String k) async {
    await _secureStorage.write(key: _storageKey, value: k);
    key = k;
  }

  static Future<String?> _getPin() async {
    return await _secureStorage.read(key: _storagePin);
  }

  static Future<String?> _getKey() async {
    return await _secureStorage.read(key: _storageKey);
  }

  static Future removeKey() async {
    await _secureStorage.delete(key: _storageKey);
    key = null;
  }

  static Future<bool> checkPin(String enteredPin) async {
    if (pin == null) {
      await putPin(enteredPin);
    }
    return enteredPin == pin;
  }
}