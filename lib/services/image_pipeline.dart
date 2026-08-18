import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

typedef EncodedImage = ({Uint8List bytes, int width, int height});

/// Pure-Dart image processing (runs in an isolate via [compute]): bakes EXIF
/// orientation, strips metadata, downscales and re-encodes as JPEG; builds
/// compact export PDFs.
class ImagePipeline {
  static const int storeMaxEdge = 2000;
  static const int storeQuality = 85;
  static const int exportMaxEdge = 1500;
  static const int exportQuality = 70;

  static Future<EncodedImage> normalize(Uint8List input,
      {int maxEdge = storeMaxEdge, int quality = storeQuality}) {
    return compute(_normalizeSync, (input, maxEdge, quality));
  }

  static Future<Uint8List> exportJpeg(Uint8List jpeg,
      {int maxEdge = exportMaxEdge, int quality = exportQuality}) async {
    return (await compute(_normalizeSync, (jpeg, maxEdge, quality))).bytes;
  }

  static Future<Uint8List> rotate(Uint8List jpeg, int quarterTurns) {
    return compute(_rotateSync, (jpeg, quarterTurns));
  }

  /// One page per image, A4 portrait or landscape by aspect, image fitted.
  static Future<Uint8List> buildPdf(List<Uint8List> pages,
      {int maxEdge = exportMaxEdge, int quality = exportQuality}) async {
    final doc = await compute(_buildPdfSync, (pages, maxEdge, quality));
    return doc;
  }

  static EncodedImage _normalizeSync((Uint8List, int, int) args) {
    final (input, maxEdge, quality) = args;
    var image = img.decodeImage(input);
    if (image == null) throw const FormatException('Bild konnte nicht gelesen werden');
    image = img.bakeOrientation(image);
    final longest = image.width > image.height ? image.width : image.height;
    if (longest > maxEdge) {
      image = image.width >= image.height
          ? img.copyResize(image, width: maxEdge, interpolation: img.Interpolation.average)
          : img.copyResize(image, height: maxEdge, interpolation: img.Interpolation.average);
    }
    // encodeJpg writes no EXIF block → metadata (GPS etc.) is dropped.
    image.exif = img.ExifData();
    final bytes = Uint8List.fromList(img.encodeJpg(image, quality: quality));
    return (bytes: bytes, width: image.width, height: image.height);
  }

  static Uint8List _rotateSync((Uint8List, int) args) {
    final (input, turns) = args;
    var image = img.decodeImage(input);
    if (image == null) throw const FormatException('Bild konnte nicht gelesen werden');
    image = img.copyRotate(image, angle: 90.0 * (turns % 4));
    return Uint8List.fromList(img.encodeJpg(image, quality: storeQuality));
  }

  static Future<Uint8List> _buildPdfSync((List<Uint8List>, int, int) args) async {
    final (pages, maxEdge, quality) = args;
    final doc = pw.Document(compress: true);
    for (final raw in pages) {
      final enc = _normalizeSync((raw, maxEdge, quality));
      final landscape = enc.width > enc.height;
      final format = landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
      doc.addPage(pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(18),
        build: (_) => pw.Center(
          child: pw.Image(pw.MemoryImage(enc.bytes), fit: pw.BoxFit.contain),
        ),
      ));
    }
    return Uint8List.fromList(await doc.save());
  }
}
