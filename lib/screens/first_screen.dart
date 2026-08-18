import 'package:cipher_eye/screens/splash_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:kreiseck_branding/kreiseck_branding.dart';

import '../services/app_auth_service.dart';
import '../services/haptics.dart';
import '../services/secure_storage_service.dart';
import '../services/init_service.dart';
import '../services/migration_service.dart';
import 'home_page.dart';

class FirstScreen extends StatefulWidget {
  const FirstScreen({super.key});

  @override
  State<FirstScreen> createState() => _FirstScreenState();
}

class _FirstScreenState extends State<FirstScreen> with WidgetsBindingObserver {
  /// The app re-locks only after being in the background for at least this long.
  /// Returning sooner — or staying in the foreground — never re-prompts.
  static const Duration _graceDuration = Duration(minutes: 3);

  bool _unlocked = false;
  bool _obscured = false;
  bool _authInProgress = false;
  bool _migrationChecked = false;
  bool _loaded = false;
  DateTime? _leftForegroundAt;
  bool _pinOfferChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    InitService.init().then((_) {
      if (!mounted) return;
      setState(() => _loaded = true);
      _runPostUnlockTasks();
    }).catchError((Object e) {
      // Never hang on the splash if loading fails — let the user into the
      // (possibly empty) app instead of an infinite spinner.
      debugPrint('InitService.init failed: $e');
      if (mounted) setState(() => _loaded = true);
    });
    // Lock gate on cold start: prompt as soon as the first frame is up.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _authenticate(userInitiated: false));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final away = _leftForegroundAt == null
          ? Duration.zero
          : DateTime.now().difference(_leftForegroundAt!);
      _leftForegroundAt = null;
      setState(() {
        _obscured = false;
        if (_unlocked && away >= _graceDuration) {
          _unlocked = false;
        }
      });
      if (!_unlocked) {
        _authenticate(userInitiated: false);
      }
    } else {
      // inactive / paused / hidden: cover the content right away so the app
      // switcher snapshot never shows passwords. Only a real `paused` starts
      // the inactivity timer — transient interruptions (the auth sheet, control
      // center) go `inactive` and must not count toward the re-lock grace.
      if (state == AppLifecycleState.paused) {
        _leftForegroundAt ??= DateTime.now();
      }
      // Only cover when there is actual content to hide (unlocked). While
      // locked the lock screen already hides everything, and the auth prompt's
      // transient `inactive` must not leave a stuck cover after unlocking.
      if (_unlocked && !_obscured) {
        setState(() => _obscured = true);
      }
    }
  }

  static const String _unlockReason =
      'Bitte authentifiziere dich, um Cipher Eye zu entsperren';

  /// Device auth (Face ID / Touch ID / passcode), with the app-PIN as fallback
  /// when the device prompt is unavailable or never answers. [_authInProgress]
  /// is real state so the lock screen reflects it, and it is always reset —
  /// a hanging prompt can no longer leave the unlock button dead.
  Future<void> _authenticate({bool userInitiated = true}) async {
    if (_unlocked || _authInProgress || !mounted) {
      return;
    }
    setState(() => _authInProgress = true);
    try {
      final ok = await AppAuthService.authenticate(
        context,
        reason: _unlockReason,
        silent: !userInitiated,
        onLateSuccess: _onUnlocked,
      );
      if (ok) _onUnlocked();
    } finally {
      if (mounted) setState(() => _authInProgress = false);
    }
  }

  /// Explicit PIN unlock from the lock screen ("Mit PIN entsperren"). Kept
  /// independent of a possibly hanging device prompt so the user always has a
  /// way in.
  bool _pinInProgress = false;
  Future<void> _authenticateWithPin() async {
    if (_unlocked || _pinInProgress || !mounted) {
      return;
    }
    setState(() => _pinInProgress = true);
    try {
      final ok = await AppAuthService.authenticateWithPin(context,
          allowSetup: kIsWeb);
      if (ok) _onUnlocked();
    } finally {
      if (mounted) setState(() => _pinInProgress = false);
    }
  }

  void _onUnlocked() {
    if (!mounted || _unlocked) return;
    Haptics.success();
    setState(() {
      _unlocked = true;
      _obscured = false;
    });
    _runPostUnlockTasks();
  }

  /// Runs once, only after the user is unlocked AND data has loaded, so the
  /// migration prompt never appears over the lock screen.
  void _runPostUnlockTasks() {
    if (!_unlocked || !_loaded || _migrationChecked) {
      return;
    }
    _migrationChecked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _maybeMigrate();
      if (!mounted || _pinOfferChecked) return;
      _pinOfferChecked = true;
      await AppAuthService.offerPinSetup(context);
    });
  }

  /// After load, brings stored passwords up to the current crypto version.
  /// Declining only postpones it — the prompt returns on the next launch.
  Future<void> _maybeMigrate() async {
    if (!mounted || !MigrationService.isNeeded) {
      return;
    }
    // Only the profile flag lags behind (nothing to re-encrypt) → bump silently.
    if (MigrationService.pendingCount == 0) {
      await MigrationService.migrateAll();
      return;
    }
    // Legacy entries exist but the key is missing → can't decrypt to migrate.
    if (!MigrationService.canRun) {
      await _showKeyMissingDialog();
      return;
    }
    final accepted = await _showMigrationConfirmDialog();
    if (accepted == true) {
      await _runMigrationWithProgress();
    }
  }

  Future<bool?> _showMigrationConfirmDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.gpp_maybe, color: Colors.red),
              SizedBox(width: 8),
              Expanded(child: Text('Sicherheitsupdate erforderlich')),
            ],
          ),
          content: Text(
            'Deine ${MigrationService.pendingCount} gespeicherten Passwörter '
            'werden mit einer stärkeren Verschlüsselung neu gesichert.\n\n'
            'Das passiert nur auf diesem Gerät – deine Passwörter verlassen es '
            'dabei nicht. Bitte schließe die App währenddessen nicht.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Später'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Jetzt aktualisieren'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showKeyMissingDialog() {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verschlüsselungs-Key fehlt'),
        content: const Text(
          'Es gibt ältere Passwörter, die neu gesichert werden müssen, aber auf '
          'diesem Gerät ist kein Verschlüsselungs-Key hinterlegt. Bitte gib '
          'zuerst deinen Key in den Einstellungen ein.',
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

  Future<void> _runMigrationWithProgress() async {
    final progress = ValueNotifier<({int done, int total})>(
        (done: 0, total: MigrationService.pendingCount));

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Passwörter werden gesichert …'),
          content: ValueListenableBuilder<({int done, int total})>(
            valueListenable: progress,
            builder: (_, p, __) {
              final frac = p.total == 0 ? 1.0 : p.done / p.total;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: frac),
                  const SizedBox(height: 12),
                  Text('${p.done} von ${p.total}'),
                ],
              );
            },
          ),
        ),
      ),
    );

    try {
      await MigrationService.migrateAll(onProgress: (done, total) {
        progress.value = (done: done, total: total);
      });
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        await _showMigrationErrorDialog();
      }
      return;
    }

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      setState(() {});
    }
  }

  Future<void> _showMigrationErrorDialog() {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update fehlgeschlagen'),
        content: const Text(
          'Beim Sichern ist ein Fehler aufgetreten. Bereits aktualisierte '
          'Passwörter bleiben gesichert; der Rest wird beim nächsten Start '
          'erneut versucht.',
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

  @override
  Widget build(BuildContext context) {
    if (!_unlocked) {
      return _lockScreen();
    }
    if (_obscured) {
      // Unlocked, but the app is leaving the foreground → privacy cover.
      return _coverScreen();
    }
    if (!_loaded) {
      return SplashScreen();
    }
    return HomePage();
  }

  static const Color _lockBackground = Color(0xff121212);

  Widget _coverScreen() {
    return const Scaffold(
      backgroundColor: _lockBackground,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Icon(Icons.remove_red_eye, size: 96, color: Colors.white),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 32),
                child: KreiseckLogo(color: Colors.white, height: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lockScreen() {
    return Scaffold(
      backgroundColor: _lockBackground,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline,
                      size: 76, color: Colors.white.withValues(alpha: 0.9)),
                  const SizedBox(height: 20),
                  const Text(
                    'Gesperrt',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 28),
                  OutlinedButton.icon(
                    onPressed: _authInProgress ? null : _authenticate,
                    icon: _authInProgress
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.lock_open, color: Colors.white),
                    label: Text(_authInProgress ? 'Warte …' : 'Entsperren',
                        style: const TextStyle(color: Colors.white)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                  ),
                  if (kIsWeb || SecureStorageService.hasPin) ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed:
                          _pinInProgress ? null : _authenticateWithPin,
                      icon: Icon(Icons.pin_outlined,
                          size: 18, color: Colors.white.withValues(alpha: 0.7)),
                      label: Text('Mit PIN entsperren',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7))),
                    ),
                  ],
                ],
              ),
            ),
            const Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 32),
                child: KreiseckLogo(color: Colors.white, height: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
