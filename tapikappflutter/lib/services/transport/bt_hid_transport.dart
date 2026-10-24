import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/error/failure.dart';
import '../../core/protocol/packet.dart';
import 'hid_reports.dart';
import 'transport.dart';

class BtHidHost {
  const BtHidHost({required this.address, required this.name});

  static final RegExp _macName = RegExp(
    r'\b(i?mac|macbook\w*)\b',
    caseSensitive: false,
  );

  final String address;
  final String name;

  String? get platform => platformFor(name);

  static String? platformFor(String? name) {
    if (name == null) return null;
    return _macName.hasMatch(name) ? 'macos' : null;
  }
}

class BtHidTransport implements Transport {
  BtHidTransport({MethodChannel? channel, HidReports? reports})
    : _channel = channel ?? const MethodChannel(channelName),
      _reports = reports ?? HidReports() {
    _channel.setMethodCallHandler(_onNative);
  }

  static const String channelName = 'tapikapp/bt_hid';
  static const String hidName = 'Tapikapp';
  static const Duration releaseTimeout = Duration(seconds: 3);
  static const Duration registerTimeout = Duration(seconds: 10);

  final MethodChannel _channel;
  final HidReports _reports;
  final StreamController<void> _hostsChanged =
      StreamController<void>.broadcast();
  final StreamController<TransportState> _states =
      StreamController<TransportState>.broadcast();
  final StreamController<Packet> _incoming =
      StreamController<Packet>.broadcast();
  final StreamController<Failure> _pairingErrors =
      StreamController<Failure>.broadcast();
  final StreamController<void> _codeRequests =
      StreamController<void>.broadcast();

  TransportState _state = TransportState.disconnected;
  TransportEndpoint? _endpoint;
  bool _disposed = false;
  bool _permissionBlocked = false;
  Completer<void>? _released;
  Future<void>? _releasing;
  int _generation = 0;

  @override
  TransportState get state => _state;

  @override
  TransportEndpoint? get endpoint => _endpoint;

  @override
  Stream<TransportState> get states => _states.stream;

  @override
  Stream<Packet> get incoming => _incoming.stream;

  @override
  Stream<Failure> get pairingErrors => _pairingErrors.stream;

  @override
  Stream<void> get codeRequests => _codeRequests.stream;

  @override
  String? get peerFingerprint => null;

  int get skippedCharacters => _reports.skippedCharacters;

  Stream<void> get hostsChanged => _hostsChanged.stream;

  bool get permissionBlocked => _permissionBlocked;

  Future<bool> isSupported() async {
    return await _invoke<bool>('isSupported') ?? false;
  }

  Future<bool> isEnabled() async {
    return await _invoke<bool>('isEnabled') ?? false;
  }

  Future<bool> hasPermission() async {
    return await _invoke<bool>('hasPermission') ?? false;
  }

  Future<void> requestPermission() => _invoke<void>('requestPermission');

  Future<bool> openBluetoothSettings() async {
    return await _invoke<bool>('openBluetoothSettings') ?? false;
  }

  Future<bool> openAppSettings() async {
    return await _invoke<bool>('openAppSettings') ?? false;
  }

  Future<List<BtHidHost>> bondedHosts() async {
    final raw = await _invoke<List<Object?>>('bondedHosts') ?? const [];
    return [
      for (final entry in raw)
        if (entry is Map)
          BtHidHost(address: '${entry['address']}', name: '${entry['name']}'),
    ];
  }

  @override
  Future<void> connect(TransportEndpoint endpoint) async {
    if (_disposed) {
      throw const TransportFailure('The connection was already closed.');
    }
    final releasing = _releasing;
    if (releasing != null) await releasing;
    final generation = ++_generation;
    _endpoint = endpoint;
    _emit(TransportState.connecting);
    try {
      final registered =
          await _channel
              .invokeMethod<bool>('register', {
                'name': hidName,
                'descriptor': Uint8List.fromList(HidReports.descriptor),
              })
              .timeout(registerTimeout) ??
          false;
      if (generation != _generation) {
        if (registered && _state == TransportState.disconnected) {
          await _invoke<void>('unregister');
        }
        return;
      }
      if (!registered) {
        throw const TransportFailure(
          'This phone could not start Bluetooth keyboard mode.',
        );
      }
      final accepted =
          await _channel.invokeMethod<bool>('connect', {
            'address': endpoint.host,
          }) ??
          false;
      if (generation != _generation) {
        if (accepted) await _invoke<void>('disconnect');
        return;
      }
      if (!accepted) {
        throw const TransportFailure(
          'That computer did not accept the Bluetooth connection.',
        );
      }
    } on PlatformException catch (error) {
      _failConnect(generation);
      throw TransportFailure(error.message ?? 'Bluetooth is not available.');
    } on TimeoutException {
      _failConnect(generation);
      throw const TransportFailure(
        'This phone could not start Bluetooth keyboard mode.',
      );
    } on Failure {
      _failConnect(generation);
      rethrow;
    }
  }

  void _failConnect(int generation) {
    if (generation == _generation) _emit(TransportState.disconnected);
  }

  @override
  void submitPairingCode(String code) {}

  @override
  void send(Packet packet) {
    if (_state != TransportState.connected) return;
    final reports = _reports.encode(packet);
    if (reports.isNotEmpty) _flush(reports);
  }

  @override
  Future<void> disconnect() async {
    _generation += 1;
    final linked = _state != TransportState.disconnected;
    if (_state == TransportState.connected) _flush(_reports.releaseAll());
    if (linked && (_released?.isCompleted ?? true)) {
      _released = Completer<void>();
    }
    final released = _released;
    await _invoke<void>('disconnect');
    _emit(TransportState.disconnected);
    if (released == null) return;
    await released.future.timeout(releaseTimeout, onTimeout: () {});
    if (_released == released) _released = null;
  }

  Future<void> release() {
    final pending = _releasing;
    if (pending != null) return pending;
    final releasing = _release();
    _releasing = releasing;
    return releasing.whenComplete(() {
      if (_releasing == releasing) _releasing = null;
    });
  }

  Future<void> _release() async {
    await disconnect();
    await _invoke<void>('unregister');
  }

  @override
  Future<void> forget() => release();

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disconnect();
    _channel.setMethodCallHandler(null);
    await _states.close();
    await _incoming.close();
    await _pairingErrors.close();
    await _codeRequests.close();
    await _hostsChanged.close();
  }

  void _flush(List<HidReport> reports) {
    unawaited(
      _invoke<bool>('send', {
        'reports': [
          for (final report in reports) [report.id, report.data],
        ],
      }),
    );
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      if (!_pairingErrors.isClosed) {
        _pairingErrors.add(
          TransportFailure(error.message ?? 'Bluetooth is not available.'),
        );
      }
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<Object?> _onNative(MethodCall call) async {
    switch (call.method) {
      case 'onState':
        _onNativeState(call.arguments);
      case 'onHostsChanged':
        _notifyHostsChanged();
      case 'onPermission':
        _permissionBlocked = call.arguments == 'blocked';
        _notifyHostsChanged();
    }
    return null;
  }

  void _onNativeState(Object? event) {
    if (event is! Map) return;
    final state = event['state'];
    final address = event['address'] as String?;
    final current = _endpoint?.host;
    final mine = address == null || current == null || address == current;
    switch (state) {
      case 'connected':
        if (!mine) {
          _endpoint = TransportEndpoint(
            host: address,
            label: event['name'] as String? ?? address,
            platform: BtHidHost.platformFor(event['name'] as String?),
            clientId: address,
          );
        }
        _emit(TransportState.connected);
      case 'connecting':
        if (mine) _emit(TransportState.connecting);
      case 'disconnected':
        final released = _released;
        if (released != null && !released.isCompleted) released.complete();
        if (!mine) return;
        if (_state == TransportState.connecting && !_pairingErrors.isClosed) {
          final name = _endpoint?.label ?? 'That computer';
          _pairingErrors.add(
            TransportFailure(
              '$name did not accept the connection. '
              'Check it is nearby with Bluetooth on.',
            ),
          );
        }
        _reports.releaseAll();
        _emit(TransportState.disconnected);
    }
  }

  void _notifyHostsChanged() {
    if (!_hostsChanged.isClosed) _hostsChanged.add(null);
  }

  void _emit(TransportState next) {
    if (_state == next || _states.isClosed) return;
    _state = next;
    _states.add(next);
  }
}
