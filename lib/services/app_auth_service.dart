import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../popup/pin_entry_popup.dart';
import 'secure_storage_service.dart';

/// Outcome of a device (biometric / passcode) authentication attempt.
enum DeviceAuthResult {
  /// The user authenticated successfully.
  success,

  /// The user cancelled or failed the prompt.
  cancelled,

  /// The device has no lock at all — nothing to authenticate against.
  unsupported,

  /// The prompt errored out or never came back (plugin error, timeout).
  failed,
}

/// Single entry point for authenticating the user: device auth first, app-PIN
/// as the fallback. Every prompt is bounded by [timeout] so a hanging system
/// sheet (seen with the iOS build running on macOS) can never wedge the app.
class AppAuthService {
  static final LocalAuthentication _localAuth = LocalAuthentication();
  static const Duration timeout = Duration(seconds: 30);

  static Future<DeviceAuthResult> deviceAuth(String reason) async {
    if (kIsWeb) return DeviceAuthResult.unsupported;
    try {
      if (!await _localAuth.isDeviceSupported()) {
        return DeviceAuthResult.unsupported;
      }
      var timedOut = false;
      final ok = await _localAuth
          .authenticate(
            localizedReason: reason,
            biometricOnly: false,
            persistAcrossBackgrounding: true,
            sensitiveTransaction: true,
          )
          .timeout(timeout, onTimeout: () {
        timedOut = true;
        _localAuth.stopAuthentication();
        return false;
      });
      if (timedOut) return DeviceAuthResult.failed;
      return ok ? DeviceAuthResult.success : DeviceAuthResult.cancelled;
    } catch (_) {
      return DeviceAuthResult.failed;
    }
  }

  /// Full authentication: device auth, then the app-PIN when device auth is
  /// unavailable or broken. Returns `true` when the user is authenticated.
  ///
  /// On web there is no device auth, so the PIN is the primary factor and may
  /// be created on first use ([allowPinSetup]). On native, PIN set-up is only
  /// offered after a successful device auth (see [offerPinSetup]) — never from
  /// the locked state, otherwise anyone could set a PIN and walk in.
  static Future<bool> authenticate(BuildContext context,
      {required String reason, bool allowPinSetup = kIsWeb}) async {
    final result = await deviceAuth(reason);
    if (!context.mounted) return false;
    switch (result) {
      case DeviceAuthResult.success:
        return true;
      case DeviceAuthResult.cancelled:
        return false;
      case DeviceAuthResult.unsupported:
        if (!SecureStorageService.hasPin && !allowPinSetup) {
          // No device lock and no PIN — nothing to check against.
          return true;
        }
        return authenticateWithPin(context, allowSetup: allowPinSetup);
      case DeviceAuthResult.failed:
        if (!SecureStorageService.hasPin && !allowPinSetup) {
          await _showNoPinDialog(context);
          return false;
        }
        return authenticateWithPin(context, allowSetup: allowPinSetup);
    }
  }

  /// PIN-only authentication. When no PIN exists and [allowSetup] is set, the
  /// user creates one now and is considered authenticated afterwards.
  static Future<bool> authenticateWithPin(BuildContext context,
      {bool allowSetup = false}) async {
    if (!SecureStorageService.hasPin) {
      if (!allowSetup) {
        await _showNoPinDialog(context);
        return false;
      }
      final created = await _showPin(context, PinMode.setup);
      return created == true;
    }
    final ok = await _showPin(context, PinMode.verify);
    return ok == true;
  }

  /// After a successful device unlock on native: offer to create a fallback
  /// PIN once, so a broken biometric prompt later never locks the user out.
  static Future<void> offerPinSetup(BuildContext context) async {
    if (kIsWeb ||
        SecureStorageService.hasPin ||
        SecureStorageService.pinOfferDismissed) {
      return;
    }
    final wants = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ersatz-PIN festlegen?'),
        content: const Text(
          'Falls Face ID / Touch ID einmal nicht reagiert (z. B. auf dem Mac), '
          'kannst du die App mit einer 6-stelligen PIN entsperren. '
          'Du kannst sie später in den Einstellungen ändern.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Später'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('PIN festlegen'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (wants == true) {
      await _showPin(context, PinMode.setup);
    } else {
      await SecureStorageService.setPinOfferDismissed();
    }
  }

  static Future<bool?> _showPin(BuildContext context, PinMode mode) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: mode == PinMode.setup,
        child: PinEntryPopup(mode: mode),
      ),
    );
  }

  static Future<void> _showNoPinDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Authentifizierung nicht möglich'),
        content: const Text(
          'Die Geräte-Authentifizierung hat nicht geantwortet und es ist keine '
          'Ersatz-PIN festgelegt. Bitte versuche es erneut. Nach dem nächsten '
          'erfolgreichen Entsperren kannst du in den Einstellungen eine PIN '
          'festlegen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
