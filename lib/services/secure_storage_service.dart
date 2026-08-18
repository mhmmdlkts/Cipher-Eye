import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'pin_hasher.dart';

class SecureStorageService {
  static const String _legacyPinKey = 'pin';
  static const String _pinHashKey = 'pin_hash';
  static const String _pinSaltKey = 'pin_salt';
  static const String _storageKey = 'encryption_key';
  static const String _pinOfferDismissedKey = 'pin_offer_dismissed';
  static const _secureStorage = FlutterSecureStorage();
  static String? key;
  static String? _pinHash;
  static String? _pinSalt;
  static bool _pinOfferDismissed = false;

  /// On web there is no OS keychain: flutter_secure_storage falls back to
  /// browser storage (IndexedDB/localStorage), which is readable by XSS,
  /// extensions and dev-tools. Since the encryption key decrypts every
  /// password, it must NEVER be persisted in the browser. On web the key
  /// therefore lives only in memory for the session and the user re-enters the
  /// same master key after each page reload. Native keeps using the keychain.
  static bool get _persistKey => !kIsWeb;

  static Future init() async {
    key = _persistKey ? await _getKey() : null;
    _pinHash = await _secureStorage.read(key: _pinHashKey);
    _pinSalt = await _secureStorage.read(key: _pinSaltKey);
    _pinOfferDismissed =
        await _secureStorage.read(key: _pinOfferDismissedKey) == '1';
    // A PIN stored in plaintext by older versions is re-stored as salt+hash.
    final legacy = await _secureStorage.read(key: _legacyPinKey);
    if (legacy != null) {
      if (_pinHash == null) {
        await setPin(legacy);
      }
      await _secureStorage.delete(key: _legacyPinKey);
    }
  }

  /// Whether an app PIN has been set up (needed for the PIN unlock fallback).
  static bool get hasPin => _pinHash != null && _pinSalt != null;

  /// Whether the user declined the one-time offer to create a fallback PIN.
  static bool get pinOfferDismissed => _pinOfferDismissed;

  static Future setPinOfferDismissed() async {
    await _secureStorage.write(key: _pinOfferDismissedKey, value: '1');
    _pinOfferDismissed = true;
  }

  static Future setPin(String pin) async {
    final salt = PinHasher.newSalt();
    final hash = PinHasher.hash(pin, salt);
    await _secureStorage.write(key: _pinSaltKey, value: salt);
    await _secureStorage.write(key: _pinHashKey, value: hash);
    _pinSalt = salt;
    _pinHash = hash;
  }

  /// Verifies [enteredPin] against the stored hash. Never accepts anything
  /// while no PIN is set — set-up is an explicit, separate step.
  static bool checkPin(String enteredPin) {
    if (!hasPin) return false;
    return PinHasher.verify(enteredPin, _pinSalt!, _pinHash!);
  }

  static Future putKey(String k) async {
    if (_persistKey) {
      await _secureStorage.write(key: _storageKey, value: k);
    }
    key = k;
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
}
