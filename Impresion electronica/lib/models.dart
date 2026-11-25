import 'dart:typed_data';

class Party {
  String docType = '';
  String docNumber = '';
  String name = '';
  String tradeName = '';
  String address = '';
}

class InvoiceItem {
  double qty = 0;
  String unit = '';
  String description = '';
  double unitPrice = 0;
  double total = 0;
}

class Invoice {
  Party issuer = Party();
  Party customer = Party();
  String docType = ''; // 01, 03, 07, 08
  String series = '';
  String number = '';
  String issueDate = '';
  String issueTime = '';
  String currency = 'PEN';
  List<InvoiceItem> items = [];
  double gravadas = 0, exoneradas = 0, inafectas = 0, igv = 0, total = 0;
  String hash = '';

  String get docName {
    switch (docType) {
      case '01':
        return 'FACTURA ELECTRÓNICA';
      case '03':
        return 'BOLETA DE VENTA ELECTRÓNICA';
      case '07':
        return 'NOTA DE CRÉDITO ELECTRÓNICA';
      case '08':
        return 'NOTA DE DÉBITO ELECTRÓNICA';
      default:
        return 'COMPROBANTE ELECTRÓNICO';
    }
  }

  String get symbol => currency == 'USD' ? 'US\$' : (currency == 'PEN' ? 'S/' : currency);

  /// Cadena oficial QR SUNAT.
  String get qrString => '${issuer.docNumber}|$docType|$series|$number|'
      '${igv.toStringAsFixed(2)}|${total.toStringAsFixed(2)}|$issueDate|'
      '${customer.docType}|${customer.docNumber}|$hash|';
}

/// Línea ya formateada a 32 columnas.
class TLine {
  final String text;
  final bool bold;
  const TLine(this.text, {this.bold = false});
}

class Ticket {
  final List<TLine> lines;
  final String? qr;
  final List<TLine> after; // líneas tras el QR
  Ticket(this.lines, this.qr, [this.after = const []]);
}

/// Página PDF convertida a 1 bit (384 px de ancho).
class RasterPage {
  final int width;
  final int height;
  final Uint8List bits; // 48 bytes por fila, bit 1 = negro
  final Uint8List previewPng;
  RasterPage(this.width, this.height, this.bits, this.previewPng);
}
