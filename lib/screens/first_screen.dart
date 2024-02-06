import 'package:cipher_eye/screens/splash_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';

import '../popup/pin_entry_popup.dart';
import '../services/init_service.dart';
import 'home_page.dart';

class FirstScreen extends StatefulWidget {
  const FirstScreen({super.key});

  @override
  _FirstScreenState createState() => _FirstScreenState();
}

class _FirstScreenState extends State<FirstScreen>/* with WidgetsBindingObserver */{
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool showSplashScreen = true;

  DateTime _lastAuthenticate = DateTime(2000, 1, 1);
  final int _authLimitSeconds = 60;
  final GlobalKey<State> _dialogKey = GlobalKey<State>();
  bool isAuthOpen = false;

  bool get isAuth => DateTime.now().difference(_lastAuthenticate).inSeconds < _authLimitSeconds;


  @override
  void dispose() {
    super.dispose();

    Navigator.of(_dialogKey.currentContext ?? context, rootNavigator: true).pop(false);
  }

  @override
  void initState() {
    super.initState();
    // WidgetsBinding.instance.addObserver(this);
    InitService.init().then((val) {
      if (mounted) {
        setState(() {
          showSplashScreen = false;
        });
      }
    });
  }

  Future<void> _authenticate() async {
    if (isAuth) {
      _lastAuthenticate = DateTime.now();
      return;
    }
    if (isAuthOpen) {
      return;
    }
    isAuthOpen = true;
    if (kDebugMode) {
      _lastAuthenticate = DateTime.now();
      isAuthOpen = false;
      return;
    }
    if (kIsWeb) {
      bool result = await showDialog(
        context: context,
        barrierDismissible: false,

        builder: (BuildContext context) {
          return WillPopScope(
              child: PinEntryPopup(key: _dialogKey),
              onWillPop: () async => false
          );
        },
      );
      if (mounted) {
        if (result == true) {
          setState(() {
            _lastAuthenticate = DateTime.now();
          });
        }
      }
      isAuthOpen = false;
      return;
    }
    try {
      bool isAuthenticated = await _localAuth.authenticate(
        localizedReason: 'Please authenticate yourself',
        options: const AuthenticationOptions(
          useErrorDialogs: true,
          stickyAuth: true,
          biometricOnly: false,
        ),
      );

      if (isAuthenticated) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          setState(() {
            _lastAuthenticate = DateTime.now();
          });
        } else {
          permission = await Geolocator.requestPermission();
          setState(() {});
        }
      }
    } catch (e) {}
    isAuthOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    _authenticate();
    return Stack(
      children: [
        InitService.isInited?_getBody():Container(),
        showSplashScreen?SplashScreen():Container(),
        if (!isAuth)
          Positioned.fill(child: Container(
            color: Colors.black.withOpacity(isAuth?0:0.5),
            child: Icon(Icons.remove_red_eye, size: 100, color: Colors.white),
          )),
      ],
    );
  }

  Widget _getBody() => HomePage();
}