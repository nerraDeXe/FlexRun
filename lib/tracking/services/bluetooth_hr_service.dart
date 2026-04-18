import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothHRService {
  static final BluetoothHRService _instance = BluetoothHRService._internal();

  factory BluetoothHRService() {
    return _instance;
  }

  BluetoothHRService._internal();

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _hrCharacteristic;
  StreamSubscription? _hrSubscription;

  final _hrValueStream = StreamController<int>.broadcast();

  /// Stream of heart rate values
  Stream<int> get hrValueStream => _hrValueStream.stream;

  /// Currently connected device
  BluetoothDevice? get connectedDevice => _connectedDevice;

  /// Whether a device is currently connected
  bool get isConnected =>
      _connectedDevice != null && _connectedDevice!.isConnected;

  /// Request Bluetooth permissions
  Future<bool> requestPermissions() async {
    final permissions = [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ];

    final results = await permissions.request();
    return results.values.every((status) => status.isGranted);
  }

  /// Scan for available Bluetooth devices
  Stream<List<ScanResult>> scanForDevices() async* {
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
      yield* FlutterBluePlus.scanResults;
    } finally {
      await FlutterBluePlus.stopScan();
    }
  }

  /// Connect to a specific device
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      _connectedDevice = device;

      // Discover services and find HR characteristic
      final services = await device.discoverServices();
      for (final service in services) {
        for (final characteristic in service.characteristics) {
          // Heart Rate Measurement characteristic UUID: 0x2A37
          if (characteristic.uuid.toString().toUpperCase() ==
              '00002A37-0000-1000-8000-00805F9B34FB') {
            _hrCharacteristic = characteristic;
            _startListeningToHR();
            return true;
          }
        }
      }

      // If no HR characteristic found, try the service UUID
      for (final service in services) {
        // Heart Rate Service UUID: 0x180D
        if (service.uuid.toString().toUpperCase() ==
            '0000180D-0000-1000-8000-00805F9B34FB') {
          for (final characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toUpperCase() ==
                '00002A37-0000-1000-8000-00805F9B34FB') {
              _hrCharacteristic = characteristic;
              _startListeningToHR();
              return true;
            }
          }
        }
      }

      if (kDebugMode) {
        print('Heart Rate characteristic not found on device');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Error connecting to device: $e');
      }
      await _disconnect();
      return false;
    }
  }

  /// Start listening to HR data
  void _startListeningToHR() {
    if (_hrCharacteristic == null) return;

    _hrSubscription?.cancel();
    _hrSubscription = _hrCharacteristic!.onValueReceived.listen((value) {
      final hr = _parseHRValue(value);
      if (hr > 0) {
        _hrValueStream.add(hr);
      }
    });

    // Request notifications
    _hrCharacteristic?.setNotifyValue(true).catchError((_) {
      return false;
    });
  }

  /// Parse Heart Rate value from BLE characteristic
  int _parseHRValue(List<int> value) {
    if (value.isEmpty) return 0;

    // Heart Rate Measurement format (GATT spec):
    // Byte 0: Flags
    // Byte 1: Heart Rate (8-bit or 16-bit depending on flags)
    final flags = value[0];
    final is16Bit = (flags & 0x01) != 0;

    if (value.length < 2) return 0;

    if (is16Bit && value.length >= 3) {
      return (value[2] << 8) | value[1];
    } else {
      return value[1];
    }
  }

  /// Disconnect from current device
  Future<void> disconnect() async {
    await _disconnect();
  }

  Future<void> _disconnect() async {
    _hrSubscription?.cancel();
    _hrSubscription = null;
    _hrCharacteristic = null;

    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (e) {
        if (kDebugMode) {
          print('Error disconnecting: $e');
        }
      }
    }
    _connectedDevice = null;
  }

  /// Cleanup
  Future<void> dispose() async {
    await disconnect();
    await _hrValueStream.close();
  }
}
