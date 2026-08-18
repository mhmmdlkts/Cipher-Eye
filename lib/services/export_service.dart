import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/attachment.dart';
import '../models/item.dart';
import 'attachment_service.dart';
import 'image_pipeline.dart';

class ExportFile {
  ExportFile({required this.name, required this.bytes, required this.mime});
  final String name;
  final Uint8List bytes;
  final String mime;
}

/// Turns an item's image pages into small PDF/JPEG files and hands them to
/// the share sheet (native) or a download (web). Temp files are removed
/// once the share sheet closes.
class ExportService {
  static List<Attachment> imagePages(Item item) =>
      item.pages.where((a) => a.kind == AttachmentKind.image).toList();

  static String _base(Item item) {
    final t = (item.title ?? 'dokument').trim();
    final safe = t.replaceAll(RegExp(r'[^\w\-. ]+'), '_');
    return safe.isEmpty ? 'dokument' : safe;
  }

  static Future<ExportFile> pdfFor(Item item) async {
    final svc = AttachmentService.instance;
    final pages = <Uint8List>[];
    for (final a in imagePages(item)) {
      pages.add(await svc.download(item, a));
    }
    final pdf = await ImagePipeline.buildPdf(pages);
    return ExportFile(
        name: '${_base(item)}.pdf', bytes: pdf, mime: 'application/pdf');
  }

  static Future<List<ExportFile>> jpegsFor(Item item) async {
    final svc = AttachmentService.instance;
    final out = <ExportFile>[];
    final pages = imagePages(item);
    for (var i = 0; i < pages.length; i++) {
      final a = pages[i];
      final jpeg = await ImagePipeline.exportJpeg(await svc.download(item, a));
      final label = a.label.trim().isEmpty ? 'seite-${i + 1}' : a.label.trim();
      final safe = label.replaceAll(RegExp(r'[^\w\-. ]+'), '_');
      out.add(ExportFile(
          name: '${_base(item)}-$safe.jpg', bytes: jpeg, mime: 'image/jpeg'));
    }
    return out;
  }

  /// Raw (unmodified) attachment, e.g. a PDF or arbitrary file.
  static Future<ExportFile> rawFor(Item item, Attachment att) async {
    final bytes = await AttachmentService.instance.download(item, att);
    return ExportFile(name: att.fileName, bytes: bytes, mime: att.mime);
  }

  static String humanSize(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).round()} KB'
      : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  /// Native: temp files + share sheet, deleted afterwards. Web: share_plus
  /// falls back to a browser download.
  static Future<void> shareFiles(List<ExportFile> files, {String? subject}) async {
    if (files.isEmpty) return;
    if (kIsWeb) {
      await SharePlus.instance.share(ShareParams(
        files: [
          for (final f in files)
            XFile.fromData(f.bytes, name: f.name, mimeType: f.mime),
        ],
        fileNameOverrides: [for (final f in files) f.name],
        subject: subject,
      ));
      return;
    }
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final written = <File>[];
    try {
      for (final f in files) {
        final file = File('${dir.path}/export-$stamp-${f.name}');
        await file.writeAsBytes(f.bytes, flush: true);
        written.add(file);
      }
      await SharePlus.instance.share(ShareParams(
        files: [
          for (var i = 0; i < written.length; i++)
            XFile(written[i].path, mimeType: files[i].mime, name: files[i].name),
        ],
        subject: subject,
      ));
    } finally {
      for (final f in written) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }
}
