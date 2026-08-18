import 'package:cipher_eye/popup/pin_entry_popup.dart';
import 'package:cipher_eye/services/secure_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

Future<bool?> _openPin(WidgetTester tester, PinMode mode) async {
  bool? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => TextButton(
        onPressed: () async {
          result = await showDialog<bool>(
              context: ctx, builder: (_) => PinEntryPopup(mode: mode));
        },
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

Future<void> _type(WidgetTester tester, String pin) async {
  for (final c in pin.split('')) {
    await tester.tap(find.widgetWithText(OutlinedButton, c));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await SecureStorageService.init();
  });

  testWidgets('verify mode rejects everything while no PIN is set',
      (tester) async {
    expect(SecureStorageService.hasPin, isFalse);
    expect(await SecureStorageService.checkPin('123456'), isFalse);
  });

  testWidgets('setup mode stores the PIN after two matching entries',
      (tester) async {
    await _openPin(tester, PinMode.setup);
    expect(find.text('Neue PIN festlegen'), findsOneWidget);
    await _type(tester, '135790');
    expect(find.text('PIN wiederholen'), findsOneWidget);
    await _type(tester, '135790');
    expect(find.byType(PinEntryPopup), findsNothing);
    expect(SecureStorageService.hasPin, isTrue);
    expect(await SecureStorageService.checkPin('135790'), isTrue);
    expect(await SecureStorageService.checkPin('135791'), isFalse);
  });

  testWidgets('setup mode restarts on mismatch', (tester) async {
    await _openPin(tester, PinMode.setup);
    await _type(tester, '111111');
    await _type(tester, '222222');
    expect(find.textContaining('stimmen nicht überein'), findsOneWidget);
    expect(find.text('Neue PIN festlegen'), findsOneWidget);
    expect(SecureStorageService.hasPin, isFalse);
  });

  testWidgets('verify mode: wrong PIN shows remaining tries, right PIN pops',
      (tester) async {
    await SecureStorageService.setPin('424242');
    await _openPin(tester, PinMode.verify);
    await _type(tester, '000000');
    expect(find.textContaining('noch 2 Versuche'), findsOneWidget);
    await _type(tester, '424242');
    expect(find.byType(PinEntryPopup), findsNothing);
  });

  testWidgets('legacy plaintext PIN is migrated to a hash on init',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'pin': '987654'});
    await SecureStorageService.init();
    expect(SecureStorageService.hasPin, isTrue);
    expect(await SecureStorageService.checkPin('987654'), isTrue);
  });

  testWidgets('too many wrong PINs lock the PIN out; a right one is refused meanwhile',
      (tester) async {
    await SecureStorageService.setPin('424242');
    for (var i = 0; i < SecureStorageService.pinFreeAttempts; i++) {
      expect(await SecureStorageService.checkPin('000000'), isFalse);
    }
    expect(SecureStorageService.pinLockRemaining, isNotNull);
    expect(await SecureStorageService.checkPin('424242'), isFalse);
    // Lockout survives a re-init (persisted).
    await SecureStorageService.init();
    expect(SecureStorageService.pinLockRemaining, isNotNull);
    // Dialog shows the lockout hint immediately.
    await _openPin(tester, PinMode.verify);
    expect(find.textContaining('Gesperrt'), findsOneWidget);
  });
}
