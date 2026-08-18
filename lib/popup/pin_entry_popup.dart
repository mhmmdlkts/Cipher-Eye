import 'package:cipher_eye/services/haptics.dart';
import 'package:cipher_eye/services/secure_storage_service.dart';
import 'package:flutter/material.dart';

/// PIN dialog. In [PinMode.verify] it checks against the stored PIN and pops
/// `true`/`false` (false after 3 failed tries). In [PinMode.setup] it asks for
/// the PIN twice, stores it and pops `true` (or `null` when cancelled).
enum PinMode { verify, setup }

class PinEntryPopup extends StatefulWidget {
  const PinEntryPopup({super.key, this.mode = PinMode.verify});

  final PinMode mode;

  @override
  State<PinEntryPopup> createState() => _PinEntryPopupState();
}

class _PinEntryPopupState extends State<PinEntryPopup> {
  static const int pinLength = 6;
  String enteredPin = '';
  String? _firstEntry;
  int tryRemains = 3;
  String? _hint;

  bool get _isSetup => widget.mode == PinMode.setup;

  @override
  void initState() {
    super.initState();
    final locked = SecureStorageService.pinLockRemaining;
    if (!_isSetup && locked != null) {
      _hint = 'Gesperrt – bitte ${_fmt(locked)} warten';
    }
  }

  String get _title {
    if (!_isSetup) return 'PIN eingeben';
    return _firstEntry == null ? 'Neue PIN festlegen' : 'PIN wiederholen';
  }

  @override
  Widget build(BuildContext context) {
    final double width =
        (MediaQuery.of(context).size.width - 80).clamp(220.0, 360.0);
    return AlertDialog(
      title: Text(_title, textAlign: TextAlign.center),
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
        child: SizedBox(
          height: 320,
          width: width,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _buildCircles(),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 18,
                    child: Text(
                      _hint ?? '',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13),
                    ),
                  ),
                ],
              ),
              NumericKeyboard(width: width, onNumberSelected: _onKey),
            ],
          ),
        ),
      ),
      actions: _isSetup
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Abbrechen'),
              ),
            ]
          : null,
    );
  }

  void _onKey(int value) {
    if (value == -1) {
      if (enteredPin.isNotEmpty) {
        setState(() {
          enteredPin = enteredPin.substring(0, enteredPin.length - 1);
        });
      }
      return;
    }
    if (enteredPin.length >= pinLength) return;
    setState(() {
      enteredPin = enteredPin + value.toString();
      _hint = null;
    });
    if (enteredPin.length == pinLength) {
      _isSetup ? _handleSetup() : _handleVerify();
    }
  }

  Future<void> _handleVerify() async {
    final locked = SecureStorageService.pinLockRemaining;
    if (locked != null) {
      Haptics.warning();
      setState(() {
        enteredPin = '';
        _hint = 'Gesperrt – bitte ${_fmt(locked)} warten';
      });
      return;
    }
    final ok = await SecureStorageService.checkPin(enteredPin);
    if (!mounted) return;
    if (ok) {
      Haptics.success();
      Navigator.of(context).pop(true);
      return;
    }
    Haptics.warning();
    tryRemains--;
    final nowLocked = SecureStorageService.pinLockRemaining;
    if (nowLocked != null) {
      setState(() {
        enteredPin = '';
        _hint = 'Zu viele Versuche – gesperrt für ${_fmt(nowLocked)}';
      });
      return;
    }
    if (tryRemains <= 0) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      enteredPin = '';
      _hint = 'Falsche PIN – noch $tryRemains Versuch${tryRemains == 1 ? '' : 'e'}';
    });
  }

  static String _fmt(Duration d) => d.inMinutes >= 1
      ? '${d.inMinutes + 1} Min.'
      : '${d.inSeconds.clamp(1, 59)} s';

  Future<void> _handleSetup() async {
    if (_firstEntry == null) {
      Haptics.selection();
      setState(() {
        _firstEntry = enteredPin;
        enteredPin = '';
      });
      return;
    }
    if (_firstEntry != enteredPin) {
      Haptics.warning();
      setState(() {
        _firstEntry = null;
        enteredPin = '';
        _hint = 'PINs stimmen nicht überein – bitte neu festlegen';
      });
      return;
    }
    await SecureStorageService.setPin(enteredPin);
    if (!mounted) return;
    Haptics.success();
    Navigator.of(context).pop(true);
  }

  List<Widget> _buildCircles() {
    const color = Color(0xff3f826a);
    return List.generate(
      pinLength,
      (i) => Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: i < enteredPin.length ? color : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(color: color),
        ),
      ),
    );
  }
}

class NumericKeyboard extends StatelessWidget {
  final double width;
  final Function(int) onNumberSelected;

  const NumericKeyboard({super.key, required this.onNumberSelected, required this.width});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 10,
      runSpacing: 10,
      children: List.generate(12, (index) {
        if (index == 9) {
          return SizedBox(width: width / 4);
        } else if (index == 10) {
          return _buildNumberButton(0);
        } else if (index == 11) {
          return _buildNumberButton(-1);
        } else {
          return _buildNumberButton(index+1);
        }
      }),
    );
  }

  Widget _buildNumberButton(int number) {
    return SizedBox(
      width: width / 4,
      height: 50,
      child: OutlinedButton(
        onPressed: () => onNumberSelected(number.isNegative?-1:number),
        child: number.isNegative?Icon(Icons.backspace):Text(number.toString()),
      ),
    );
  }
}
