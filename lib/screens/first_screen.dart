import 'package:cipher_eye/screens/splash_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../popup/pin_entry_popup.dart';
import '../services/init_service.dart';
import '../services/migration_service.dart';
import 'home_page.dart';

class FirstScreen extends StatefulWidget {
  const FirstScreen({super.key});

  @override
  State<FirstScreen> createState() => _FirstScreenState();
}

class _FirstScreenState extends State<FirstScreen> with WidgetsBindingObserver {
  final LocalAuthentication _localAuth = LocalAuthentication();

  /// The app re-locks only after being in the background for at least this long.
  /// Returning sooner — or staying in the foreground — never re-prompts.
  static const Duration _graceDuration = Duration(minutes: 3);

  bool _unlocked = false;
  bool _obscured = false;
  bool _authInProgress = false;
  bool _migrationChecked = false;
  bool _loaded = false;
  DateTime? _leftForegroundAt;
  final GlobalKey<State> _dialogKey = GlobalKey<State>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    InitService.init().then((_) {
      if (!mounted) return;
      setState(() => _loaded = true);
      _runPostUnlockTasks();
    });
    // Lock gate on cold start: prompt as soon as the first frame is up.
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
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
        _authenticate();
      }
    } else {
      // inactive / paused / hidden: cover the content right away so the app
      // switcher snapshot never shows passwords. Only a real `paused` starts
      // the inactivity timer — transient interruptions (the auth sheet, control
      // center) go `inactive` and must not count toward the re-lock grace.
      if (state == AppLifecycleState.paused) {
        _leftForegroundAt ??= DateTime.now();
      }
      if (!_obscured) {
        setState(() => _obscured = true);
      }
    }
  }

  Future<void> _authenticate() async {
    if (_unlocked || _authInProgress) {
      return;
    }
    _authInProgress = true;
    try {
      final ok = kIsWeb ? await _authWeb() : await _authNative();
      if (ok && mounted) {
        setState(() => _unlocked = true);
        _runPostUnlockTasks();
      }
    } finally {
      _authInProgress = false;
    }
  }

  Future<bool> _authNative() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Bitte authentifiziere dich, um Cipher Eye zu entsperren',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
        sensitiveTransaction: true,
      );
    } catch (e) {
      return false;
    }
  }

  Future<bool> _authWeb() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WillPopScope(
        onWillPop: () async => false,
        child: PinEntryPopup(key: _dialogKey),
      ),
    );
    return result == true;
  }

  /// Runs once, only after the user is unlocked AND data has loaded, so the
  /// migration prompt never appears over the lock screen.
  void _runPostUnlockTasks() {
    if (!_unlocked || !_loaded || _migrationChecked) {
      return;
    }
    _migrationChecked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeMigrate());
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
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
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
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
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

  Widget _coverScreen() {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: const Center(
        child: Icon(Icons.remove_red_eye, size: 96, color: Colors.white),
      ),
    );
  }

  Widget _lockScreen() {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.remove_red_eye, size: 96, color: Colors.white),
            const SizedBox(height: 24),
            const Text(
              'Gesperrt',
              style: TextStyle(color: Colors.white, fontSize: 20),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _authInProgress ? null : _authenticate,
              icon: const Icon(Icons.lock_open, color: Colors.white),
              label: const Text('Entsperren',
                  style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
