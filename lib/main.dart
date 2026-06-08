import 'package:cipher_eye/screens/first_screen.dart';
import 'package:cipher_eye/screens/splash_screen.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kreiseck_branding/kreiseck_branding.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cipher Eye',
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: const Color(0xff32614f),
          secondary: const Color(0xff3f826a),
          surface: const Color(0xffe5e5e5),
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSwatch(brightness: Brightness.dark).copyWith(
          primary: const Color(0xff7bbca3),
          secondary: const Color(0xff99e8ca),
          surface: const Color(0xff1a1a1a),
        ),
      ),
      themeMode: ThemeMode.system,
      home: StreamBuilder<auth.User?>(
        stream: auth.FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // Waiting for the very first auth state → branded loading screen.
          if (snapshot.connectionState != ConnectionState.active) {
            return const SplashScreen(freeze: true);
          }
          if (snapshot.data == null) {
            return SignInScreen(
              providers: [EmailAuthProvider()],
              headerBuilder: (context, constraints, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: KreiseckLogo(
                  width: 160,
                  color: KreiseckColors.forBrightness(
                      Theme.of(context).brightness),
                ),
              ),
            );
          }
          // Logged in. FirstScreen owns its own load/lock/splash flow.
          return const FirstScreen();
        },
      ),
    );
  }
}
