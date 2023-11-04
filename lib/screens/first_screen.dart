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

class _FirstScreenState extends State<FirstScreen> with WidgetsBindingObserver {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool showSplashScreen = true;
  bool _authenticated = false;
  final GlobalKey<State> _dialogKey = GlobalKey<State>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance!.addObserver(this);
    InitService.init().then((val) {
      if (mounted) {
        setState(() {
          showSplashScreen = false;
        });
      }
      _authenticate();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance!.removeObserver(this);
    Navigator.of(_dialogKey.currentContext ?? context, rootNavigator: true).pop(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused) {
      setState(() {
        _authenticated = false;
      });
      _authenticate();
    }
  }

  Future<void> _authenticate() async {
    if (kDebugMode) {
      _authenticated = true;
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
        setState(() {
          _authenticated = result;
        });
      }
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
            _authenticated = true;
          });
        } else {
          permission = await Geolocator.requestPermission();
          setState(() {});
        }
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    return _authenticated?Stack(
      children: [
        InitService.isInited?_getBody():Container(),
        showSplashScreen?SplashScreen():Container(),
      ],
    ):Container();
  }

  Widget _getBody() => const Scaffold(
    body: HomePage(),
  );
}