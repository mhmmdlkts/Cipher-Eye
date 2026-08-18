import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'pin_hasher.dart';

class SecureStorageService {
  static const String _legacyPinKey = 'pin';
  static const String _pinHashKey = 'pin_hash';
  static const String _pinSaltKey = 'pin_salt';
  static const String _storageKey = 'encryption_key';
  static const String _pinOfferDismissedKey = 'pin_offer_dismissed';
  static const String _pinFailsKey = 'pin_fails';
  static const String _pinLockUntilKey = 'pin_lock_until';
  static const _secureStorage = FlutterSecureStorage();
  static String? key;
  static String? _pinHash;
  static String? _pinSalt;
  static bool _pinOfferDismissed = false;
  static int _pinFails = 0;
  static DateTime? _pinLockUntil;

  /// Wrong attempts before the first lockout; each further failure doubles
  /// the lockout (30 s, 60 s, … capped at 1 h). Persisted, so restarting the
  /// app or re-opening the dialog does not reset it.
  static const int pinFreeAttempts = 5;
  static const Duration _pinBaseLock = Duration(seconds: 30);
  static const Duration _pinMaxLock = Duration(hours: 1);

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
    _pinFails = int.tryParse(await _secureStorage.read(key: _pinFailsKey) ?? '') ?? 0;
    final lockMs = int.tryParse(await _secureStorage.read(key: _pinLockUntilKey) ?? '');
    _pinLockUntil = lockMs == null ? null : DateTime.fromMillisecondsSinceEpoch(lockMs);
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
    await _resetPinFails();
  }

  /// Remaining lockout after too many wrong PINs, or null when not locked.
  static Duration? get pinLockRemaining {
    final until = _pinLockUntil;
    if (until == null) return null;
    final left = until.difference(DateTime.now());
    return left.isNegative ? null : left;
  }

  /// Verifies [enteredPin] against the stored hash. Never accepts anything
  /// while no PIN is set — set-up is an explicit, separate step — and never
  /// while locked out. Failures are counted and persisted.
  static Future<bool> checkPin(String enteredPin) async {
    if (!hasPin || pinLockRemaining != null) return false;
    final ok = PinHasher.verify(enteredPin, _pinSalt!, _pinHash!);
    if (ok) {
      await _resetPinFails();
      return true;
    }
    _pinFails++;
    await _secureStorage.write(key: _pinFailsKey, value: '$_pinFails');
    if (_pinFails >= pinFreeAttempts) {
      var lock = _pinBaseLock * (1 << (_pinFails - pinFreeAttempts));
      if (lock > _pinMaxLock) lock = _pinMaxLock;
      _pinLockUntil = DateTime.now().add(lock);
      await _secureStorage.write(
          key: _pinLockUntilKey,
          value: '${_pinLockUntil!.millisecondsSinceEpoch}');
    }
    return false;
  }

  static Future<void> _resetPinFails() async {
    _pinFails = 0;
    _pinLockUntil = null;
    await _secureStorage.delete(key: _pinFailsKey);
    await _secureStorage.delete(key: _pinLockUntilKey);
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
