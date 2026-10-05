import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failure.dart';
import '../../../data/models/device_model.dart';
import '../../../data/repositories/device_repository.dart';
import '../../../services/discovery/discovery.dart';
import '../../../services/security/controller_identity.dart';
import '../../../services/security/fingerprint_store.dart';
import '../../../services/transport/transport.dart';
import 'connect_state.dart';

class ConnectCubit extends Cubit<ConnectState> {
  ConnectCubit(this._devices, this._browser, this._transport)
    : super(const ConnectLoading());

  final DeviceRepository _devices;
  final AgentBrowser _browser;
  final Transport _transport;

  StreamSubscription<List<DeviceModel>>? _registry;
  StreamSubscription<List<DiscoveredAgent>>? _discovery;
  StreamSubscription<Failure>? _discoveryErrors;
  StreamSubscription<TransportState>? _transportStates;
  StreamSubscription<Failure>? _pairingErrors;
  StreamSubscription<void>? _codeRequests;

  List<DeviceModel> _trusted = const [];
  List<DiscoveredAgent> _agents = const [];
  DiscoveredAgent? _connectedAgent;
  DiscoveredAgent? _pairingAgent;
  bool _needsCode = false;
  String? _connectingId;
  String? _connectionError;
  String? _registryError;

  Future<void> start() async {
    _transportStates ??= _transport.states.listen(_onTransportState);
    _pairingErrors ??= _transport.pairingErrors.listen(_onPairingError);
    _codeRequests ??= _transport.codeRequests.listen(_onCodeRequested);
    _discoveryErrors ??= _browser.errors.listen(_onDiscoveryError);
    await _registry?.cancel();
    try {
      _registry = _devices.watchDevices().listen(
        _onRegistry,
        onError: _onRegistryError,
      );
    } on Failure catch (failure) {
      _registryError = failure.message;
    }
    _discovery ??= _browser.agents.listen(_onAgents);
    _agents = _browser.current;
    _syncConnected();
    _publish();
    try {
      await _browser.start();
    } on Failure catch (failure) {
      _onDiscoveryError(failure);
    }
  }

  Future<void> connect(ConnectDevice device) async {
    if (_connectingId != null) return;
    if (_isAmbiguous(device.id)) {
      _connectionError =
          'Two laptops on this network are claiming the same name. '
          'Disconnect one and try again.';
      _publish();
      return;
    }
    final agent = _agentFor(device.id);
    if (agent == null) return;
    _connectingId = device.id;
    _connectionError = null;
    _publish();
    try {
      final identity = await ControllerIdentity.load();
      final pinned = await FingerprintStore.load(agent.id);
      await _transport.connect(
        TransportEndpoint(
          clientId: identity.id,
          host: agent.host,
          label: agent.name,
          platform: agent.platform,
          fingerprint: pinned,
          tcpPort: agent.tcpPort,
          udpPort: agent.udpPort,
        ),
      );
      _pairingAgent = agent;
    } on Failure catch (failure) {
      _connectionError = failure.message;
      _pairingAgent = null;
      _connectedAgent = null;
    } catch (error) {
      _connectionError = 'Could not connect to ${device.name}.';
      _pairingAgent = null;
      _connectedAgent = null;
    } finally {
      _connectingId = null;
      _publish();
    }
  }

  Future<void> disconnect() async {
    await _transport.disconnect();
    _connectedAgent = null;
    _pairingAgent = null;
    _needsCode = false;
    _publish();
  }

  void submitPairingCode(String code) {
    if (!_needsCode) return;
    _needsCode = false;
    _connectionError = null;
    _transport.submitPairingCode(code);
    _publish();
  }

  Future<void> cancelPairing() async {
    if (!_needsCode) return;
    _needsCode = false;
    await disconnect();
  }

  void dismissConnectionError() {
    if (_connectionError == null) return;
    _connectionError = null;
    _publish();
  }

  void _onRegistry(List<DeviceModel> registry) {
    _trusted = registry;
    _registryError = null;
    unawaited(_inheritFingerprints(registry));
    _publish();
  }

  Future<void> _inheritFingerprints(List<DeviceModel> registry) async {
    for (final device in registry) {
      if (device.certFingerprint.isEmpty) continue;
      final local = await FingerprintStore.load(device.id);
      if (local == null) {
        await FingerprintStore.remember(device.id, device.certFingerprint);
      }
    }
  }

  Future<void> _trustAgent(DiscoveredAgent agent) async {
    final fingerprint = _transport.peerFingerprint;
    if (fingerprint == null || fingerprint.isEmpty) return;
    await FingerprintStore.remember(agent.id, fingerprint);
    final known = _registeredFingerprint(agent.id);
    try {
      if (known == fingerprint) {
        await _devices.touchLastSeen(agent.id);
      } else {
        await _devices.registerDevice(
          DeviceModel(
            id: agent.id,
            name: agent.name,
            platform: agent.platform,
            certFingerprint: fingerprint,
          ),
        );
      }
    } on Failure {
      return;
    }
  }

  String? _registeredFingerprint(String id) {
    for (final device in _trusted) {
      if (device.id == id) return device.certFingerprint;
    }
    return null;
  }

  void _onAgents(List<DiscoveredAgent> agents) {
    _agents = agents;
    _syncConnected();
    _publish();
  }

  void _onTransportState(TransportState state) {
    switch (state) {
      case TransportState.disconnected:
        _needsCode = false;
        _pairingAgent = null;
        _connectedAgent = null;
      case TransportState.connected:
        _needsCode = false;
        final paired = _pairingAgent;
        _pairingAgent = null;
        _syncConnected();
        if (paired != null) unawaited(_trustAgent(paired));
      case TransportState.connecting:
      case TransportState.pairing:
        _syncConnected();
    }
    _publish();
  }

  void _onCodeRequested(void _) {
    _needsCode = true;
    _publish();
  }

  void _onPairingError(Failure failure) {
    _connectionError = failure.message;
    if (_transport.state == TransportState.pairing) _needsCode = true;
    _publish();
  }

  void _onDiscoveryError(Failure failure) {
    _connectionError = failure.message;
    _publish();
  }

  void _onRegistryError(Object error) {
    _registryError = error is Failure
        ? error.message
        : 'Your saved laptops could not be loaded.';
    _publish();
  }

  void _syncConnected() {
    if (_transport.state != TransportState.connected) {
      _connectedAgent = null;
      return;
    }
    final endpoint = _transport.endpoint;
    if (endpoint == null) return;
    for (final agent in _agents) {
      if (agent.tcpPort == endpoint.tcpPort &&
          agent.hosts.contains(endpoint.host)) {
        _connectedAgent = agent;
        return;
      }
    }
  }

  bool _isAmbiguous(String id) {
    var seen = 0;
    for (final agent in _agents) {
      if (agent.id == id) seen += 1;
    }
    return seen > 1;
  }

  DiscoveredAgent? _agentFor(String id) {
    for (final agent in _agents) {
      if (agent.id == id) return agent;
    }
    final connected = _connectedAgent;
    return connected != null && connected.id == id ? connected : null;
  }

  void _publish() {
    if (isClosed) return;
    final trustedIds = {for (final device in _trusted) device.id};
    final visible = <DiscoveredAgent>[..._agents];
    final connected = _connectedAgent ?? _pairingAgent;
    if (connected != null && !visible.any((a) => a.id == connected.id)) {
      visible.insert(0, connected);
    }
    final discoveredIds = {for (final agent in visible) agent.id};
    final nearby = [
      for (final agent in visible)
        ConnectDevice(
          id: agent.id,
          name: agent.name,
          platform: agent.platform,
          status: _statusFor(agent, trustedIds),
          address: agent.host,
        ),
    ];
    final offline = [
      for (final device in _trusted)
        if (!discoveredIds.contains(device.id))
          ConnectDevice(
            id: device.id,
            name: device.name,
            platform: device.platform,
            status: ConnectDeviceStatus.offline,
            lastSeenAt: device.lastSeenAt,
          ),
    ]..sort(_byLastSeen);
    emit(
      ConnectReady(
        nearby: nearby,
        offline: offline,
        needsPairingCode: _needsCode,
        pairingLaptop: _pairingAgent?.name,
        connectionError: _connectionError,
        registryError: _registryError,
      ),
    );
  }

  ConnectDeviceStatus _statusFor(DiscoveredAgent agent, Set<String> trusted) {
    if (agent.id == _connectedAgent?.id) return ConnectDeviceStatus.connected;
    if (agent.id == _connectingId || agent.id == _pairingAgent?.id) {
      return ConnectDeviceStatus.connecting;
    }
    if (!agent.isCompatible) return ConnectDeviceStatus.incompatible;
    return trusted.contains(agent.id)
        ? ConnectDeviceStatus.available
        : ConnectDeviceStatus.untrusted;
  }

  static int _byLastSeen(ConnectDevice a, ConnectDevice b) {
    final left = a.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final right = b.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return right.compareTo(left);
  }

  @override
  Future<void> close() {
    _registry?.cancel();
    _discovery?.cancel();
    _discoveryErrors?.cancel();
    _transportStates?.cancel();
    _pairingErrors?.cancel();
    _codeRequests?.cancel();
    unawaited(_browser.stop());
    return super.close();
  }
}
