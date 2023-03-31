import 'package:cipher_eye/screens/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../services/init_service.dart';
import 'home_page.dart';

class FirstScreen extends StatefulWidget {
  const FirstScreen({super.key});

  @override
  _FirstScreenState createState() => _FirstScreenState();
}

class _FirstScreenState extends State<FirstScreen> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool showSplashScreen = true;
  bool _authenticated = false;

  @override
  void initState() {
    super.initState();
    InitService.init().then((val) { if (mounted) setState(() { showSplashScreen = false; }); });
    _authenticate();
  }

  Future<void> _authenticate() async {
    try {
      bool isAuthenticated = await _localAuth.authenticate(
        localizedReason: 'Bitte authentifizieren Sie sich',
        options: AuthenticationOptions(
          useErrorDialogs: true,
          stickyAuth: true,
          biometricOnly: false,
        ),
      );

      if (isAuthenticated) {
        // Der Benutzer wurde erfolgreich authentifiziert
        print('Authentifizierung erfolgreich');
        setState(() {
          _authenticated = true;
        });
      } else {
        // Die Authentifizierung war nicht erfolgreich
        print('Authentifizierung fehlgeschlagen');
      }
    } catch (e) {
      // Ein Fehler ist aufgetreten
      print('Authentifizierungsfehler: $e');
    }
  }



  @override
  Widget build2(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('FaceID-Beispiel'),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: _authenticate,
          child: Text('Mit FaceID authentifizieren'),
        ),
      ),
    );
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

  Widget _getBody() => Scaffold(
    body: HomePage(),
  );
}