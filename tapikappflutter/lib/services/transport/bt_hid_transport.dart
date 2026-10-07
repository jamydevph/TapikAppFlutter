import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/error/failure.dart';
import '../../core/protocol/packet.dart';
import 'hid_reports.dart';
import 'transport.dart';

class BtHidHost {
  const BtHidHost({required this.address, required this.name});

  final String address;
  final String name;
}

class BtHidTransport implements Transport {
  BtHidTransport({MethodChannel? channel, HidReports? reports})
    : _channel = channel ?? const MethodChannel(channelName),
      _reports = reports ?? HidReports() {
    _channel.setMethodCallHandler(_onNative);
  }

  static const String channelName = 'tapikapp/bt_hid';

  final MethodChannel _channel;
  final HidReports _reports;
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

  Future<bool> isSupported() async {
    return await _invoke<bool>('isSupported') ?? false;
  }

  Future<bool> hasPermission() async {
    return await _invoke<bool>('hasPermission') ?? false;
  }

  Future<void> requestPermission() => _invoke<void>('requestPermission');

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
    _endpoint = endpoint;
    _emit(TransportState.connecting);
    try {
      final registered =
          await _channel.invokeMethod<bool>('register', {
            'name': endpoint.label ?? 'Tapikapp',
            'descriptor': Uint8List.fromList(HidReports.descriptor),
          }) ??
          false;
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
      if (!accepted) {
        throw const TransportFailure(
          'That computer did not accept the Bluetooth connection.',
        );
      }
    } on PlatformException catch (error) {
      _emit(TransportState.disconnected);
      throw TransportFailure(error.message ?? 'Bluetooth is not available.');
    } on Failure {
      _emit(TransportState.disconnected);
      rethrow;
    }
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
    if (_state == TransportState.connected) _flush(_reports.releaseAll());
    await _invoke<void>('disconnect');
    _emit(TransportState.disconnected);
  }

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
    if (call.method != 'onState') return null;
    switch (call.arguments) {
      case 'connected':
        _emit(TransportState.connected);
      case 'connecting':
        _emit(TransportState.connecting);
      case 'disconnected':
        _reports.releaseAll();
        _emit(TransportState.disconnected);
    }
    return null;
  }

  void _emit(TransportState next) {
    if (_state == next || _states.isClosed) return;
    _state = next;
    _states.add(next);
  }
}
