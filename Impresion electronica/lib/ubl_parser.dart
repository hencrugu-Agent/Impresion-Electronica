import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'models.dart';

/// Extrae el XML de un ZIP en memoria ignorando el CDR (R-*.xml).
String xmlFromZip(Uint8List zipBytes) {
  final archive = ZipDecoder().decodeBytes(zipBytes);
  for (final f in archive) {
    if (!f.isFile) continue;
    final base = f.name.split('/').last.split('\\').last;
    final lower = base.toLowerCase();
    if (lower.endsWith('.xml') && !lower.startsWith('r-')) {
      return utf8.decode(f.content as List<int>, allowMalformed: true);
    }
  }
  throw Exception('El ZIP no contiene un XML de comprobante.');
}

Iterable<XmlElement> _kids(XmlElement e, String n) =>
    e.childElements.where((c) => c.name.local == n);
XmlElement? _kid(XmlElement? e, String n) {
  if (e == null) return null;
  for (final c in e.childElements) {
    if (c.name.local == n) return c;
  }
  return null;
}

XmlElement? _desc(XmlElement? e, String n) {
  if (e == null) return null;
  for (final c in e.descendantElements) {
    if (c.name.local == n) return c;
  }
  return null;
}

String _t(XmlElement? e) => e?.innerText.trim() ?? '';
double _d(XmlElement? e) => double.tryParse(_t(e)) ?? 0;

XmlElement? _path(XmlElement? e, List<String> names) {
  var cur = e;
  for (final n in names) {
    cur = _kid(cur, n);
    if (cur == null) return null;
  }
  return cur;
}

Party _party(XmlElement? wrapper) {
  final p = Party();
  final party = _kid(wrapper, 'Party');
  final idEl = _path(party, ['PartyIdentification', 'ID']);
  p.docNumber = _t(idEl);
  p.docType = idEl?.getAttribute('schemeID') ?? '';
  final legal = _kid(party, 'PartyLegalEntity');
  p.name = _t(_kid(legal, 'RegistrationName'));
  p.tradeName = _t(_path(party, ['PartyName', 'Name']));
  if (p.name.isEmpty) p.name = p.tradeName;
  final addr = _kid(legal, 'RegistrationAddress');
  if (addr != null) {
    final parts = <String>[
      _t(_path(addr, ['AddressLine', 'Line'])),
      _t(_kid(addr, 'StreetName')),
      _t(_kid(addr, 'CitySubdivisionName')),
      _t(_kid(addr, 'CityName')),
      _t(_kid(addr, 'CountrySubentity')),
      _t(_kid(addr, 'District')),
    ].where((s) => s.isNotEmpty).toList();
    p.address = parts.join(' - ');
  }
  return p;
}

Invoice parseUbl(String xmlText) {
  final doc = XmlDocument.parse(xmlText.replaceFirst('\uFEFF', ''));
  final root = doc.rootElement;
  final kind = root.name.local;
  final inv = Invoice();

  final lineName = {
    'Invoice': 'InvoiceLine',
    'CreditNote': 'CreditNoteLine',
    'DebitNote': 'DebitNoteLine',
  }[kind];
  if (lineName == null) {
    throw Exception('XML no es un comprobante UBL (raíz: $kind).');
  }

  inv.docType = kind == 'CreditNote'
      ? '07'
      : kind == 'DebitNote'
          ? '08'
          : (_t(_kid(root, 'InvoiceTypeCode')).isEmpty
              ? '01'
              : _t(_kid(root, 'InvoiceTypeCode')));

  final fullId = _t(_kid(root, 'ID'));
  final idx = fullId.indexOf('-');
  inv.series = idx > 0 ? fullId.substring(0, idx) : fullId;
  inv.number = idx > 0 ? fullId.substring(idx + 1) : '';
  inv.issueDate = _t(_kid(root, 'IssueDate'));
  inv.issueTime = _t(_kid(root, 'IssueTime'));
  final cur = _t(_kid(root, 'DocumentCurrencyCode'));
  if (cur.isNotEmpty) inv.currency = cur;

  inv.issuer = _party(_kid(root, 'AccountingSupplierParty'));
  inv.customer = _party(_kid(root, 'AccountingCustomerParty'));
  if (inv.customer.docType.isEmpty) inv.customer.docType = '-';
  if (inv.customer.docNumber.isEmpty) inv.customer.docNumber = '-';

  for (final l in _kids(root, lineName)) {
    final it = InvoiceItem();
    final q = l.childElements.firstWhere(
        (c) => const ['InvoicedQuantity', 'CreditedQuantity', 'DebitedQuantity']
            .contains(c.name.local),
        orElse: () => XmlElement(XmlName('x')));
    it.qty = _d(q);
    it.unit = q.getAttribute('unitCode') ?? '';
    it.description = _t(_path(l, ['Item', 'Description'])).replaceAll(RegExp(r'\s+'), ' ');
    final withTax = _path(l, ['PricingReference', 'AlternativeConditionPrice', 'PriceAmount']);
    it.unitPrice = withTax != null ? _d(withTax) : _d(_path(l, ['Price', 'PriceAmount']));
    final ext = _d(_kid(l, 'LineExtensionAmount'));
    final tax = _d(_path(l, ['TaxTotal', 'TaxAmount']));
    it.total = ext + tax;
    if (it.total == 0 && it.unitPrice > 0) it.total = it.unitPrice * it.qty;
    inv.items.add(it);
  }

  // Totales a nivel documento
  final taxTotal = _kid(root, 'TaxTotal');
  inv.igv = _d(_kid(taxTotal, 'TaxAmount'));
  for (final tt in _kids(root, 'TaxTotal')) {
    for (final st in _kids(tt, 'TaxSubtotal')) {
      final id = _t(_path(st, ['TaxCategory', 'TaxScheme', 'ID']));
      final base = _d(_kid(st, 'TaxableAmount'));
      if (id == '1000') inv.gravadas += base;
      if (id == '9997') inv.exoneradas += base;
      if (id == '9998') inv.inafectas += base;
    }
  }
  inv.total = _d(_path(root, ['LegalMonetaryTotal', 'PayableAmount']));
  inv.hash = _t(_desc(root, 'DigestValue'));
  return inv;
}
