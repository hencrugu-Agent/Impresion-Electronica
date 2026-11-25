import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdfx/pdfx.dart';
import 'models.dart';

const int printWidth = 384;

/// Renderiza el PDF (hilo principal, requiere plugin) y procesa en isolate.
Future<List<RasterPage>> pdfToRaster(Uint8List pdfBytes) async {
  final doc = await PdfDocument.openData(pdfBytes);
  final pngs = <Uint8List>[];
  try {
    for (var i = 1; i <= doc.pagesCount; i++) {
      final page = await doc.getPage(i);
      // ~3x (≈216 dpi) para texto pequeño nítido
      final r = await page.render(
        width: page.width * 3,
        height: page.height * 3,
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      await page.close();
      if (r != null) pngs.add(r.bytes);
    }
  } finally {
    await doc.close();
  }
  final results = <RasterPage>[];
  for (final png in pngs) {
    final p = await compute(_process, png);
    if (p != null) results.add(p);
  }
  return results;
}

RasterPage? _process(Uint8List png) {
  final src = img.decodePng(png);
  if (src == null) return null;
  final w = src.width, h = src.height;
  final gray = Uint8List(w * h);
  var i = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = src.getPixel(x, y);
      final a = p.a / p.maxChannelValue;
      var l = p.luminance / p.maxChannelValue * 255;
      l = 255 - (255 - l) * a;
      gray[i++] = l.round().clamp(0, 255);
    }
  }
  // Auto-crop de márgenes blancos
  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (gray[y * w + x] < 200) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return null; // página en blanco
  const pad = 4;
  minX = (minX - pad).clamp(0, w - 1);
  minY = (minY - pad).clamp(0, h - 1);
  maxX = (maxX + pad).clamp(0, w - 1);
  maxY = (maxY + pad).clamp(0, h - 1);
  final cw = maxX - minX + 1, ch = maxY - minY + 1;

  final g = img.Image(width: cw, height: ch, numChannels: 1);
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      final v = gray[(y + minY) * w + x + minX];
      g.setPixelRgb(x, y, v, v, v);
    }
  }
  final newH = (ch * printWidth / cw).round().clamp(1, 100000);
  final rs = img.copyResize(g,
      width: printWidth, height: newH, interpolation: img.Interpolation.average);

  // Umbral adaptativo (media local con imagen integral)
  const W = printWidth;
  final H = newH;
  final lum = Uint8List(W * H);
  for (var y = 0; y < H; y++) {
    for (var x = 0; x < W; x++) {
      lum[y * W + x] = rs.getPixel(x, y).r.toInt();
    }
  }
  final integral = List<int>.filled((W + 1) * (H + 1), 0);
  for (var y = 1; y <= H; y++) {
    var row = 0;
    for (var x = 1; x <= W; x++) {
      row += lum[(y - 1) * W + x - 1];
      integral[y * (W + 1) + x] = integral[(y - 1) * (W + 1) + x] + row;
    }
  }
  const r = 8; // ventana 17x17
  final bits = Uint8List(48 * H);
  final out = img.Image(width: W, height: H, numChannels: 1);
  for (var y = 0; y < H; y++) {
    final y0 = (y - r).clamp(0, H - 1), y1 = (y + r).clamp(0, H - 1) + 1;
    for (var x = 0; x < W; x++) {
      final x0 = (x - r).clamp(0, W - 1), x1 = (x + r).clamp(0, W - 1) + 1;
      final sum = integral[y1 * (W + 1) + x1] -
          integral[y0 * (W + 1) + x1] -
          integral[y1 * (W + 1) + x0] +
          integral[y0 * (W + 1) + x0];
      final mean = sum / ((x1 - x0) * (y1 - y0));
      final v = lum[y * W + x];
      final black = v < mean * 0.88 && v < 215 || v < 90;
      if (black) bits[y * 48 + (x >> 3)] |= 0x80 >> (x & 7);
      final c = black ? 0 : 255;
      out.setPixelRgb(x, y, c, c, c);
    }
  }
  return RasterPage(W, H, bits, Uint8List.fromList(img.encodePng(out)));
}
