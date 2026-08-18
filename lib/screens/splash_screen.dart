import 'package:flutter/material.dart';
import 'package:kreiseck_branding/kreiseck_branding.dart';

/// Branded loading screen: eye in the middle, Kreiseck logo at the bottom —
/// the same layout as the lock and cover screens.
class SplashScreen extends StatelessWidget {
  final bool freeze;
  const SplashScreen({this.freeze = false, super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Icon(Icons.remove_red_eye,
                  size: 96, color: scheme.primary.withValues(alpha: 0.9)),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: KreiseckLogo(
                  color: KreiseckColors.forBrightness(Theme.of(context).brightness),
                  height: 30,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
