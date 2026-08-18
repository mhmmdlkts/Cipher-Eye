import 'dart:typed_data';

import 'package:cipher_eye/services/image_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _png(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(200, 30, 30));
  img.fillRect(im, x1: 0, y1: 0, x2: w ~/ 2, y2: h ~/ 2, color: img.ColorRgb8(30, 30, 200));
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  test('normalize downsizes to the max edge and yields JPEG', () async {
    final out = await ImagePipeline.normalize(_png(3000, 1000));
    expect(out.width, 2000);
    expect(out.height, 667);
    expect(out.bytes.sublist(0, 2), [0xFF, 0xD8]);
    final decoded = img.decodeJpg(out.bytes)!;
    expect(decoded.exif.isEmpty, isTrue);
  });

  test('normalize keeps small images at their size', () async {
    final out = await ImagePipeline.normalize(_png(300, 200));
    expect(out.width, 300);
    expect(out.height, 200);
  });

  test('exportJpeg is smaller than the stored image', () async {
    final stored = (await ImagePipeline.normalize(_png(2500, 2500))).bytes;
    final exported = await ImagePipeline.exportJpeg(stored);
    expect(exported.length, lessThan(stored.length));
    expect(img.decodeJpg(exported)!.width, 1500);
  });

  test('rotate swaps width and height', () async {
    final stored = (await ImagePipeline.normalize(_png(400, 200))).bytes;
    final rotated = img.decodeJpg(await ImagePipeline.rotate(stored, 1))!;
    expect(rotated.width, 200);
    expect(rotated.height, 400);
  });

  test('buildPdf produces a PDF with one page per image', () async {
    final pdf = await ImagePipeline.buildPdf([_png(400, 200), _png(200, 400)]);
    expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
    final text = String.fromCharCodes(pdf);
    expect(RegExp(r'/Type\s*/Page[^s]').allMatches(text).length, 2);
  });
}
