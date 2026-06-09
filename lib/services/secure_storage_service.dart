import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const String _storagePin = 'pin';
  static const String _storageKey = 'encryption_key';
  static const _secureStorage = FlutterSecureStorage();
  static String? key;
  static String? pin;

  /// On web there is no OS keychain: flutter_secure_storage falls back to
  /// browser storage (IndexedDB/localStorage), which is readable by XSS,
  /// extensions and dev-tools. Since the encryption key decrypts every
  /// password, it must NEVER be persisted in the browser. On web the key
  /// therefore lives only in memory for the session and the user re-enters the
  /// same master key after each page reload. Native keeps using the keychain.
  static bool get _persistKey => !kIsWeb;

  static Future init() async {
    key = _persistKey ? await _getKey() : null;
    pin = await _getPin();
  }

  static Future putPin(String p) async {
    await _secureStorage.write(key: _storagePin, value: p);
    pin = p;
  }

  static Future putKey(String k) async {
    if (_persistKey) {
      await _secureStorage.write(key: _storageKey, value: k);
    }
    key = k;
  }

  static Future<String?> _getPin() async {
    return await _secureStorage.read(key: _storagePin);
  }

  static Future<String?> _getKey() async {
    return await _secureStorage.read(key: _storageKey);
  }

  static Future removeKey() async {
    if (_persistKey) {
      await _secureStorage.delete(key: _storageKey);
    }
    key = null;
  }

  static Future<bool> checkPin(String enteredPin) async {
    if (pin == null) {
      await putPin(enteredPin);
    }
    return enteredPin == pin;
  }
}