import 'dart:convert';
import 'models.dart';

const _cp850 = <int, int>{
  0xE1: 0xA0, 0xE9: 0x82, 0xED: 0xA1, 0xF3: 0xA2, 0xFA: 0xA3,
  0xF1: 0xA4, 0xD1: 0xA5, 0xC1: 0xB5, 0xC9: 0x90, 0xCD: 0xD6,
  0xD3: 0xE0, 0xDA: 0xE9, 0xFC: 0x81, 0xDC: 0x9A, 0xBF: 0xA8,
  0xA1: 0xAD, 0xB0: 0xF8, 0xBA: 0xA7, 0xAA: 0xA6, 0xA2: 0x9B,
  0xE0: 0x85, 0xE8: 0x8A, 0xEC: 0x8D, 0xF2: 0x95, 0xF9: 0x97,
};

List<int> encodeCp850(String s) {
  final out = <int>[];
  for (final r in s.runes) {
    if (r < 0x80) {
      out.add(r);
    } else {
      out.add(_cp850[r] ?? 0x3F);
    }
  }
  return out;
}

class EscPos {
  static const init = [0x1B, 0x40];
  static const codePage850 = [0x1B, 0x74, 0x02]; // ESC t 2 = CP850
  static const fontA = [0x1B, 0x4D, 0x00];

  static List<int> bold(bool on) => [0x1B, 0x45, on ? 1 : 0];
  static List<int> align(int a) => [0x1B, 0x61, a]; // 0 izq,1 centro,2 der
  static List<int> feed(int n) => [0x1B, 0x64, n]; // ESC d n

  static List<int> text(String s) => [...encodeCp850(s), 0x0A];

  /// QR nativo GS ( k, centrado, corrección M.
  static List<int> qr(String data, {int size = 5}) {
    final d = utf8.encode(data);
    final len = d.length + 3;
    return [
      ...align(1),
      0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00, // modelo 2
      0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, size, // tamaño módulo
      0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31, // nivel M
      0x1D, 0x28, 0x6B, len & 0xFF, (len >> 8) & 0xFF, 0x31, 0x50, 0x30, ...d,
      0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30, // imprimir
      0x0A,
      ...align(0),
    ];
  }

  static List<int> ticket(Ticket t) {
    final b = <int>[...init, ...codePage850, ...fontA, ...align(0)];
    void lines(List<TLine> ls) {
      for (final l in ls) {
        b.addAll(bold(l.bold));
        b.addAll(text(l.text.trimRight()));
      }
      b.addAll(bold(false));
    }

    lines(t.lines);
    if (t.qr != null) b.addAll(qr(t.qr!, size: 5));
    lines(t.after);
    b.addAll(feed(4));
    return b;
  }

  /// Raster GS v 0 en bloques de máx. 255 filas.
  static List<int> raster(List<RasterPage> pages) {
    final b = <int>[...init, ...align(0)];
    const bpr = 48;
    for (final p in pages) {
      for (var y = 0; y < p.height; y += 255) {
        final h = (p.height - y) < 255 ? p.height - y : 255;
        b.addAll([0x1D, 0x76, 0x30, 0x00, bpr & 0xFF, 0, h & 0xFF, 0]);
        b.addAll(p.bits.sublist(y * bpr, (y + h) * bpr));
      }
    }
    b.addAll(feed(4));
    return b;
  }
}
