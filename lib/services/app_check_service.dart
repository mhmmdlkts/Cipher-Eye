import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Firebase App Check: proves requests come from this app before Firestore/
/// Storage answer them. Release builds use App Attest (DeviceCheck fallback)
/// on Apple, Play Integrity on Android and reCAPTCHA Enterprise on web;
/// debug builds use the debug provider (register the printed debug token in
/// the Firebase console → App Check → Apps).
class AppCheckService {
  /// Web needs a reCAPTCHA Enterprise site key from the Firebase console;
  /// pass it with `--dart-define=RECAPTCHA_SITE_KEY=…`. Without it App Check
  /// stays inactive on web (works only while enforcement is off).
  static const String _recaptchaSiteKey =
      String.fromEnvironment('RECAPTCHA_SITE_KEY');

  static Future<void> activate() async {
    try {
      if (kIsWeb) {
        if (kDebugMode) {
          await FirebaseAppCheck.instance
              .activate(providerWeb: WebDebugProvider());
        } else if (_recaptchaSiteKey.isNotEmpty) {
          await FirebaseAppCheck.instance.activate(
              providerWeb: ReCaptchaEnterpriseProvider(_recaptchaSiteKey));
        }
        return;
      }
      await FirebaseAppCheck.instance.activate(
        providerApple: kDebugMode
            ? const AppleDebugProvider()
            : const AppleAppAttestWithDeviceCheckFallbackProvider(),
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
      );
      await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
    } catch (e) {
      // Never block start-up on App Check; requests then simply carry no
      // token (rejected only once enforcement is switched on).
      debugPrint('App Check activation failed: $e');
    }
  }
}
