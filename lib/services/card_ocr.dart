import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'card_text_parser.dart';

/// On-device OCR (ML Kit) for card photos; everything stays on the phone.
/// Only iOS/Android; elsewhere returns an empty result.
class CardOcr {
  static bool get available => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  static Future<CardScanResult> scan(Uint8List jpeg) async {
    if (!available) return const CardScanResult();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/ocr-${DateTime.now().microsecondsSinceEpoch}.jpg');
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      await file.writeAsBytes(jpeg, flush: true);
      final result = await recognizer.processImage(InputImage.fromFilePath(file.path));
      return CardTextParser.parse(result.text);
    } catch (_) {
      return const CardScanResult();
    } finally {
      await recognizer.close();
      try {
        await file.delete();
      } catch (_) {}
    }
  }
}
