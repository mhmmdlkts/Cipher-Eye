import 'package:flutter/material.dart';
import 'package:kreiseck_branding/kreiseck_branding.dart';

class SplashScreen extends StatefulWidget {
  final bool freeze;
  const SplashScreen({this.freeze = false, super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: MediaQuery.of(context).size.width,
      height: MediaQuery.of(context).size.height,
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            KreiseckLogo(
              width: 180,
              color: KreiseckColors.forBrightness(Theme.of(context).brightness),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 24,
              child: widget.freeze
                  ? null
                  : const CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
