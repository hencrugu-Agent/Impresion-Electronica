import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'escpos.dart';
import 'models.dart';
import 'pdf_raster.dart';
import 'printer_service.dart';
import 'ticket_builder.dart';
import 'ubl_parser.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Impresión Térmica',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const Home(),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  static const _share = MethodChannel('app/share');
  final _svc = PrinterService();
  List<BtDevice> _devices = [];
  BtDevice? _selected;
  bool _connected = false;
  bool _busy = false;
  String _fileName = '';
  Ticket? _ticket;
  List<RasterPage>? _pages;

  @override
  void initState() {
    super.initState();
    _share.setMethodCallHandler((c) async {
      if (c.method == 'onFile') _loadPath(c.arguments as String);
    });
    _init();
  }

  Future<void> _init() async {
    final ok = await _svc.ensurePermissions();
    if (!ok) {
      _msg('Se requieren permisos de Bluetooth para imprimir.');
    } else {
      await _refreshDevices();
      final last = await _svc.last();
      if (last != null) {
        final match = _devices.where((d) => d.macAdress == last.$1);
        if (match.isNotEmpty) {
          setState(() => _selected = match.first);
          await _connect();
        }
      }
    }
    final initial = await _share.invokeMethod<String>('getInitial');
    if (initial != null) _loadPath(initial);
  }

  void _msg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _refreshDevices() async {
    try {
      final d = await _svc.paired();
      setState(() => _devices = d);
    } catch (e) {
      _msg('No se pudo listar impresoras: $e');
    }
  }

  Future<bool> _connect() async {
    final d = _selected;
    if (d == null) {
      _msg('Seleccione una impresora vinculada.');
      return false;
    }
    setState(() => _busy = true);
    final ok = await _svc.connect(d.macAdress, d.name);
    setState(() {
      _connected = ok;
      _busy = false;
    });
    if (!ok) _msg('No se pudo conectar. ¿Está encendida y vinculada?');
    return ok;
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xml', 'zip', 'pdf'],
    );
    final path = r?.files.single.path;
    if (path != null) _loadPath(path);
  }

  Future<void> _loadPath(String path) async {
    setState(() => _busy = true);
    try {
      final bytes = Uint8List.fromList(await File(path).readAsBytes());
      final name = path.split(RegExp(r'[\\/]')).last;
      final ext = name.toLowerCase().split('.').last;
      Ticket? t;
      List<RasterPage>? pages;
      if (ext == 'pdf') {
        pages = await pdfToRaster(bytes);
        if (pages.isEmpty) throw Exception('El PDF no tiene contenido.');
      } else if (ext == 'zip') {
        t = buildTicket(parseUbl(xmlFromZip(bytes)));
      } else {
        t = buildTicket(parseUbl(utf8.decode(bytes, allowMalformed: true)));
      }
      setState(() {
        _fileName = name;
        _ticket = t;
        _pages = pages;
      });
    } catch (e) {
      _msg('Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _print(List<int> data) async {
    if (!await _svc.isConnected()) {
      if (!await _connect()) return;
    }
    setState(() => _busy = true);
    try {
      await _svc.send(data);
      _msg('Enviado a la impresora.');
    } catch (e) {
      _msg('Error de impresión: $e');
      setState(() => _connected = false);
    } finally {
      setState(() => _busy = false);
    }
  }

  void _printCurrent() {
    if (_ticket != null) {
      _print(EscPos.ticket(_ticket!));
    } else if (_pages != null) {
      _print(EscPos.raster(_pages!));
    } else {
      _msg('Abra un archivo primero.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Impresión ADV-7011N')),
      body: SafeArea(
        child: Column(children: [
          if (_busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  Row(children: [
                    Icon(Icons.bluetooth,
                        color: _connected ? Colors.green : Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        hint: const Text('Impresora vinculada'),
                        value: _selected?.macAdress,
                        items: _devices
                            .map((d) => DropdownMenuItem(
                                value: d.macAdress,
                                child: Text('${d.name} (${d.macAdress})',
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => setState(() {
                          _selected =
                              _devices.firstWhere((d) => d.macAdress == v);
                          _connected = false;
                        }),
                      ),
                    ),
                    IconButton(
                        onPressed: _refreshDevices,
                        icon: const Icon(Icons.refresh)),
                  ]),
                  Row(children: [
                    Expanded(
                        child: Text(
                            _connected ? 'Conectada' : 'Desconectada',
                            style: TextStyle(
                                color: _connected ? Colors.green : Colors.red))),
                    FilledButton.tonal(
                        onPressed: _busy ? null : _connect,
                        child: const Text('Conectar')),
                  ]),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: double.infinity,
              height: 64,
              child: FilledButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.folder_open, size: 28),
                label: const Text('Abrir XML / ZIP / PDF',
                    style: TextStyle(fontSize: 18)),
              ),
            ),
          ),
          if (_fileName.isNotEmpty)
            Padding(
                padding: const EdgeInsets.all(6),
                child: Text(_fileName, style: TextStyle(color: cs.outline))),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              color: Colors.grey.shade300,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: Center(child: _preview()),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(children: [
              Expanded(
                  child: FilledButton.icon(
                      onPressed: _busy ? null : _printCurrent,
                      icon: const Icon(Icons.print),
                      label: const Text('Imprimir Ticket'))),
              const SizedBox(width: 8),
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed:
                          _busy ? null : () => _print(EscPos.ticket(buildTestTicket())),
                      icon: const Icon(Icons.tune),
                      label: const Text('Imprimir Prueba (48mm)'))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _paper(Widget child) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
            width: 384, color: Colors.white, child: child), // 384 px = 48 mm
      );

  Widget _preview() {
    const style = TextStyle(
        fontFamily: 'monospace', fontSize: 20, height: 1.2, color: Colors.black);
    if (_pages != null) {
      return _paper(Column(
          children: _pages!
              .map((p) => Image.memory(p.previewPng,
                  width: 384, filterQuality: FilterQuality.none))
              .toList()));
    }
    final t = _ticket ?? buildTestTicket();
    Widget lines(List<TLine> ls) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: ls
            .map((l) => Text(l.text,
                softWrap: false,
                style: style.copyWith(
                    fontWeight: l.bold ? FontWeight.bold : FontWeight.normal)))
            .toList());
    return _paper(Column(children: [
      lines(t.lines),
      if (t.qr != null)
        Padding(
          padding: const EdgeInsets.all(8),
          child: QrImageView(
              data: t.qr!,
              size: 200,
              errorCorrectionLevel: QrErrorCorrectLevel.M),
        ),
      lines(t.after),
    ]));
  }
}
