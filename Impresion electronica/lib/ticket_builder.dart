import 'models.dart';

const int cols = 32;
final String sep = '-' * cols;

/// Word-wrap sin cortar palabras (palabras > ancho se parten).
List<String> wrap(String text, [int width = cols]) {
  final out = <String>[];
  var line = '';
  for (var w in text.trim().split(RegExp(r'\s+'))) {
    if (w.isEmpty) continue;
    while (w.length > width) {
      if (line.isNotEmpty) {
        out.add(line);
        line = '';
      }
      out.add(w.substring(0, width));
      w = w.substring(width);
    }
    if (line.isEmpty) {
      line = w;
    } else if (line.length + 1 + w.length <= width) {
      line += ' $w';
    } else {
      out.add(line);
      line = w;
    }
  }
  if (line.isNotEmpty) out.add(line);
  return out;
}

String center(String s) {
  if (s.length >= cols) return s;
  return ' ' * ((cols - s.length) ~/ 2) + s;
}

String lr(String l, String r) {
  final space = cols - l.length - r.length;
  if (space < 1) return '$l $r';
  return l + ' ' * space + r;
}

String _unit(String u) => const {
      'NIU': 'UND',
      'ZZ': 'SERV',
      'KGM': 'KG',
      'LTR': 'LT',
      'MTR': 'M',
      'BX': 'CAJA',
      'DZN': 'DOC',
    }[u] ??
    u;

String _num(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

String _docTypeName(String t) =>
    const {'1': 'DNI', '6': 'RUC', '4': 'CE', '7': 'PAS', '0': 'DOC'}[t] ?? 'DOC';

Ticket buildTicket(Invoice inv) {
  final l = <TLine>[];
  void c(String s, {bool bold = false}) {
    for (final x in wrap(s)) {
      l.add(TLine(center(x), bold: bold));
    }
  }

  void left(String s, {bool bold = false}) {
    for (final x in wrap(s)) {
      l.add(TLine(x, bold: bold));
    }
  }

  c(inv.issuer.name, bold: true);
  if (inv.issuer.tradeName.isNotEmpty && inv.issuer.tradeName != inv.issuer.name) {
    c(inv.issuer.tradeName);
  }
  c('RUC: ${inv.issuer.docNumber}');
  if (inv.issuer.address.isNotEmpty) c(inv.issuer.address);
  l.add(TLine(sep));
  c(inv.docName, bold: true);
  c('${inv.series}-${inv.number}', bold: true);
  l.add(TLine(sep));
  left('Fecha: ${inv.issueDate} ${inv.issueTime}'.trim());
  left('Moneda: ${inv.currency}');
  left('Cliente: ${inv.customer.name}');
  left('${_docTypeName(inv.customer.docType)}: ${inv.customer.docNumber}');
  l.add(TLine(sep));
  l.add(const TLine('CANT  DESCRIPCION', bold: true));
  l.add(TLine(sep));
  for (final it in inv.items) {
    left(it.description);
    l.add(TLine(lr('${_num(it.qty)} ${_unit(it.unit)} x ${it.unitPrice.toStringAsFixed(2)}',
        it.total.toStringAsFixed(2))));
  }
  l.add(TLine(sep));
  void tot(String label, double v, {bool bold = false}) =>
      l.add(TLine(lr(label, '${inv.symbol} ${v.toStringAsFixed(2)}'), bold: bold));
  if (inv.gravadas > 0) tot('Op. Gravadas:', inv.gravadas);
  if (inv.exoneradas > 0) tot('Op. Exoneradas:', inv.exoneradas);
  if (inv.inafectas > 0) tot('Op. Inafectas:', inv.inafectas);
  tot('IGV:', inv.igv);
  tot('IMPORTE TOTAL:', inv.total, bold: true);
  l.add(TLine(sep));

  final after = <TLine>[];
  if (inv.hash.isNotEmpty) {
    after.add(const TLine('Hash:'));
    for (final x in wrap(inv.hash)) {
      after.add(TLine(x));
    }
  }
  for (final x in wrap('Representación impresa del comprobante electrónico')) {
    after.add(TLine(center(x)));
  }
  return Ticket(l, inv.qrString, after);
}

Ticket buildTestTicket() {
  return Ticket([
    TLine('12345678901234567890123456789012'),
    TLine(sep),
    TLine(center('PRUEBA DE IMPRESION'), bold: true),
    TLine(center('ADVANCE ADV-7011N 48mm')),
    TLine(sep),
    TLine('Tildes: áéíóú ÁÉÍÓÚ Ññ ü'),
    TLine(lr('Total:', 'S/ 1234.50')),
    TLine(sep),
  ], 'PRUEBA|ADV-7011N|48MM|32COL|', [
    TLine(center('Calibracion OK')),
  ]);
}
