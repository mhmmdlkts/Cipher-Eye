import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../screens/crop_screen.dart';
import 'attachment_service.dart';
import 'image_pipeline.dart';

class CapturedPage {
  CapturedPage({required this.jpeg, required this.width, required this.height});
  final Uint8List jpeg;
  final int width;
  final int height;
}

class PickedFile {
  PickedFile({required this.bytes, required this.name, required this.mime});
  final Uint8List bytes;
  final String name;
  final String mime;
}

/// Platform switch for getting document pages: native scanner with edge
/// detection (iOS/Android), otherwise picker + cropper. Every returned page is
/// already normalised (downscaled, EXIF-free JPEG).
class DocumentCapture {
  static bool? _scannerAvailable;

  static bool get isMobile => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  /// VisionKit / ML-Kit scanner: mobile only, and not for the iOS build
  /// running on macOS (no document camera there).
  static Future<bool> scannerAvailable() async {
    if (_scannerAvailable != null) return _scannerAvailable!;
    var ok = isMobile;
    if (ok && Platform.isIOS) {
      try {
        ok = !(await DeviceInfoPlugin().iosInfo).isiOSAppOnMac;
      } catch (_) {}
    }
    return _scannerAvailable = ok;
  }

  static Future<List<CapturedPage>> scan() async {
    final paths = await CunningDocumentScanner.getPictures(
      scannerSource: ScannerSource.camera,
      iosScannerOptions: IosScannerOptions(
        imageFormat: IosImageFormat.jpg,
        jpgCompressionQuality: 0.9,
      ),
    );
    final out = <CapturedPage>[];
    for (final p in paths ?? const <String>[]) {
      final bytes = await XFile(p).readAsBytes();
      out.add(await _normalize(bytes));
    }
    try {
      await CunningDocumentScanner.cleanCache();
    } catch (_) {}
    return out;
  }

  static Future<CapturedPage?> pickImage(BuildContext context,
      {bool camera = false, bool crop = true}) async {
    final x = await ImagePicker().pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 95);
    if (x == null) return null;
    var bytes = await x.readAsBytes();
    if (crop) {
      if (!context.mounted) return null;
      final cropped = await recropBytes(context, bytes);
      if (cropped == null) return null;
      bytes = cropped;
    }
    return _normalize(bytes);
  }

  /// Opens the cropper on existing bytes; null when cancelled.
  static Future<Uint8List?> recropBytes(
      BuildContext context, Uint8List image) {
    return Navigator.push<Uint8List>(
        context, MaterialPageRoute(builder: (_) => CropScreen(image)));
  }

  static Future<CapturedPage?> recrop(
      BuildContext context, Uint8List jpeg) async {
    final cropped = await recropBytes(context, jpeg);
    if (cropped == null) return null;
    return _normalize(cropped);
  }

  static Future<PickedFile?> pickFile() async {
    final f = await FilePicker.pickFile();
    if (f == null) return null;
    if (await f.length() > AttachmentService.maxBytes) {
      throw ArgumentError('Datei ist größer als 20 MB');
    }
    final bytes = await f.readAsBytes();
    return PickedFile(bytes: bytes, name: f.name, mime: _mimeFor(f.name));
  }

  static Future<CapturedPage> _normalize(Uint8List bytes) async {
    final n = await ImagePipeline.normalize(bytes);
    return CapturedPage(jpeg: n.bytes, width: n.width, height: n.height);
  }

  static String _mimeFor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'heic':
        return 'image/heic';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }
}
