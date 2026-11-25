import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BtDevice {
  final String name;
  final String mac;
  BtDevice(this.name, this.mac);
  String get macAdress => mac;
}

/// Bluetooth Classic SPP vía MethodChannel nativo (RFCOMM 00001101-...).
class PrinterService {
  static const _ch = MethodChannel('app/bt');
  static const _kMac = 'last_mac';
  static const _kName = 'last_name';

  Future<bool> ensurePermissions() async {
    final res = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
    return res[Permission.bluetoothConnect]?.isGranted ?? false;
  }

  Future<List<BtDevice>> paired() async {
    final list = await _ch.invokeListMethod<Map>('paired') ?? [];
    return list
        .map((m) => BtDevice(m['name'] as String, m['mac'] as String))
        .toList();
  }

  Future<bool> isConnected() async =>
      (await _ch.invokeMethod<bool>('isConnected')) ?? false;

  Future<bool> connect(String mac, String name) async {
    try {
      final ok = await _ch.invokeMethod<bool>('connect', {'mac': mac}) ?? false;
      if (ok) {
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_kMac, mac);
        await sp.setString(_kName, name);
      }
      return ok;
    } on PlatformException {
      return false;
    }
  }

  Future<void> disconnect() => _ch.invokeMethod('disconnect');

  Future<(String, String)?> last() async {
    final sp = await SharedPreferences.getInstance();
    final m = sp.getString(_kMac);
    if (m == null) return null;
    return (m, sp.getString(_kName) ?? m);
  }

  Future<void> send(List<int> data) async {
    const chunk = 512;
    for (var i = 0; i < data.length; i += chunk) {
      final end = i + chunk > data.length ? data.length : i + chunk;
      await _ch.invokeMethod(
          'write', {'data': Uint8List.fromList(data.sublist(i, end))});
      await Future.delayed(const Duration(milliseconds: 30));
    }
  }
}
