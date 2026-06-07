import 'dart:async';

import 'package:flutter/services.dart';

/// Copies sensitive values (passwords) to the clipboard and wipes them again
/// after a short delay — but only if the user hasn't copied something else in
/// the meantime. A static timer so it survives screen navigation.
class ClipboardService {
  ClipboardService._();

  static const Duration clearAfter = Duration(seconds: 30);
  static Timer? _clearTimer;

  static Future<void> copySensitive(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _clearTimer?.cancel();
    _clearTimer = Timer(clearAfter, () async {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text == text) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    });
  }
}
