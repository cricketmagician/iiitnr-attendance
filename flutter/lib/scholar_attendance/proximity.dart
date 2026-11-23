/// Guard desk Bluetooth beacon.
///
/// The guard phone broadcasts a Bluetooth LE advertisement whose 128-bit service UUID
/// is a short-lived token signed by the server. A scholar's phone must hear it while
/// marking. A video call can carry the QR picture but not this radio signal, so a
/// scholar who is not near the gate cannot mark.
///
/// A service UUID (not manufacturer data) is used because iPhones can only advertise
/// service UUIDs and a name. Both Android and iPhone can send and receive it.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// First four bytes of every beacon UUID: "IINR".
const _marker = [0x49, 0x49, 0x4e, 0x52];

enum BeaconState { idle, starting, on, bluetoothOff, noPermission, unsupported, failed }

String beaconStateText(BeaconState s) => switch (s) {
      BeaconState.on => 'Bluetooth signal on',
      BeaconState.starting || BeaconState.idle => 'Starting Bluetooth signal',
      BeaconState.bluetoothOff => 'Turn on Bluetooth on this phone',
      BeaconState.noPermission => 'Allow Bluetooth for this app',
      BeaconState.unsupported => 'This device cannot send the Bluetooth signal',
      BeaconState.failed => 'Bluetooth signal stopped',
    };

Future<int> _androidSdk() async =>
    Platform.isAndroid ? (await DeviceInfoPlugin().androidInfo).version.sdkInt : 0;

/// Ask for what Bluetooth needs on Android. iPhone shows its own prompt the first time.
Future<bool> _androidPermissions({required bool advertise}) async {
  if (kIsWeb || !Platform.isAndroid) return true;
  final sdk = await _androidSdk();
  final wanted = <Permission>[
    if (sdk >= 31) ...[Permission.bluetoothScan, Permission.bluetoothConnect],
    if (sdk >= 31 && advertise) Permission.bluetoothAdvertise,
    if (sdk < 31) Permission.locationWhenInUse,
  ];
  if (wanted.isEmpty) return true;
  final res = await wanted.request();
  return res.values.every((s) => s.isGranted || s.isLimited);
}

// ---------------------------------------------------------------- guard side

/// Broadcasts the beacon from the guard phone and switches to each new token.
class GateBeacon {
  final _peripheral = FlutterBlePeripheral();
  String? _current;
  BeaconState state = BeaconState.idle;
  bool _permitted = false;
  bool _working = false;

  /// Start or update the broadcast. Returns the state to show to the guard.
  Future<BeaconState> advertise(String uuid) async {
    if (kIsWeb) return state = BeaconState.unsupported;
    if (_working) return state; // a permission prompt or restart is still running
    _working = true;
    try {
      if (!_permitted) {
        _permitted = await _androidPermissions(advertise: true);
        if (!_permitted) return state = BeaconState.noPermission;
      }
      if (uuid == _current && state == BeaconState.on && await _peripheral.isAdvertising) return state;
      if (await _peripheral.isAdvertising) await _peripheral.stop();
      final r = await _peripheral.start(
        advertiseData: AdvertiseData(serviceUuid: uuid),
        // Legacy advertising (every phone can hear it), never time out, medium range (about a room).
        advertiseSettings: AdvertiseSettings(
          advertiseSet: false,
          timeout: 0,
          connectable: false,
          advertiseMode: AdvertiseMode.advertiseModeLowLatency,
          txPowerLevel: AdvertiseTxPower.advertiseTxPowerMedium,
        ),
      );
      _current = uuid;
      state = switch (r) {
        BluetoothPeripheralState.ready || BluetoothPeripheralState.granted => BeaconState.on,
        BluetoothPeripheralState.turnedOff => BeaconState.bluetoothOff,
        BluetoothPeripheralState.denied ||
        BluetoothPeripheralState.permanentlyDenied ||
        BluetoothPeripheralState.restricted =>
          BeaconState.noPermission,
        BluetoothPeripheralState.unsupported => BeaconState.unsupported,
        _ => BeaconState.on,
      };
    } catch (_) {
      final on = await FlutterBluePlus.adapterState.first.catchError((_) => BluetoothAdapterState.unknown);
      state = on == BluetoothAdapterState.off ? BeaconState.bluetoothOff : BeaconState.failed;
    } finally {
      _working = false;
    }
    return state;
  }

  Future<void> stop() async {
    try {
      if (!kIsWeb && await _peripheral.isAdvertising) await _peripheral.stop();
    } catch (_) {}
    _current = null;
    state = BeaconState.idle;
  }
}

// ---------------------------------------------------------------- scholar side

class BeaconHit {
  final String uuid;
  final int rssi;
  final DateTime seenAt;
  const BeaconHit(this.uuid, this.rssi, this.seenAt);
}

enum ScanProblem { none, bluetoothOff, noPermission, unsupported }

/// Listens for the guard beacon while the scholar scans the QR and takes the selfie.
class GateScanner {
  BeaconHit? best;
  ScanProblem problem = ScanProblem.none;
  StreamSubscription<List<ScanResult>>? _sub;

  static bool _isGate(Guid g) {
    final b = g.bytes;
    return b.length == 16 && b[0] == _marker[0] && b[1] == _marker[1] && b[2] == _marker[2] && b[3] == _marker[3];
  }

  /// Start listening. Safe to call when Bluetooth is off or not allowed: [problem] says why.
  Future<void> start() async {
    if (kIsWeb) {
      problem = ScanProblem.unsupported;
      return;
    }
    try {
      if (!await FlutterBluePlus.isSupported) {
        problem = ScanProblem.unsupported;
        return;
      }
      if (!await _androidPermissions(advertise: false)) {
        problem = ScanProblem.noPermission;
        return;
      }
      if (Platform.isAndroid && FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        try {
          await FlutterBluePlus.turnOn(timeout: 15); // Android shows a system "Turn on Bluetooth?" prompt
        } catch (_) {}
      }
      final adapter = await FlutterBluePlus.adapterState
          .where((s) => s != BluetoothAdapterState.unknown)
          .first
          .timeout(const Duration(seconds: 3), onTimeout: () => BluetoothAdapterState.unknown);
      if (adapter == BluetoothAdapterState.unauthorized) {
        problem = ScanProblem.noPermission;
        return;
      }
      if (adapter != BluetoothAdapterState.on) {
        problem = ScanProblem.bluetoothOff;
        return;
      }
      problem = ScanProblem.none;
      _sub = FlutterBluePlus.onScanResults.listen((results) {
        for (final r in results) {
          for (final g in r.advertisementData.serviceUuids) {
            if (!_isGate(g)) continue;
            // Prefer the newest token; among equals, the strongest signal.
            final hit = BeaconHit(g.str128, r.rssi, r.timeStamp);
            final b = best;
            if (b == null || hit.uuid != b.uuid || hit.rssi > b.rssi) best = hit;
          }
        }
      });
      await FlutterBluePlus.startScan(continuousUpdates: true, androidScanMode: AndroidScanMode.lowLatency);
    } catch (_) {
      problem = ScanProblem.bluetoothOff;
    }
  }

  /// The beacon heard recently, waiting up to [wait] if none yet.
  Future<BeaconHit?> latest({Duration wait = const Duration(seconds: 5)}) async {
    final end = DateTime.now().add(wait);
    while (problem == ScanProblem.none && DateTime.now().isBefore(end)) {
      final b = best;
      if (b != null && DateTime.now().difference(b.seenAt) < const Duration(seconds: 40)) return b;
      await Future.delayed(const Duration(milliseconds: 250));
    }
    final b = best;
    return b != null && DateTime.now().difference(b.seenAt) < const Duration(seconds: 40) ? b : null;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      if (!kIsWeb) await FlutterBluePlus.stopScan();
    } catch (_) {}
  }
}
