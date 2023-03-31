// File generated by FlutterFire CLI.
// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDp1tCNUMK_wCNMXfAP1CgFlmayTXi3ODY',
    appId: '1:822677258148:web:d9c7d86a3620a17d018b31',
    messagingSenderId: '822677258148',
    projectId: 'cipher-eye',
    authDomain: 'cipher-eye.firebaseapp.com',
    storageBucket: 'cipher-eye.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDXdJmyGR_XYZEhIly6zAcUfAH6K0KbGH8',
    appId: '1:822677258148:android:28e2fb571697db24018b31',
    messagingSenderId: '822677258148',
    projectId: 'cipher-eye',
    storageBucket: 'cipher-eye.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAxBXqxZjfgok2dyJtAXf6Q-MntNBmvShw',
    appId: '1:822677258148:ios:550214d9b31d002e018b31',
    messagingSenderId: '822677258148',
    projectId: 'cipher-eye',
    storageBucket: 'cipher-eye.appspot.com',
    iosClientId: '822677258148-891220u1iqjij976fqt0rp5apbasgifi.apps.googleusercontent.com',
    iosBundleId: 'kreiseck.ciphereye',
  );
}
