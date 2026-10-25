import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failure.dart';
import '../../../data/models/device_model.dart';
import '../../../data/repositories/device_repository.dart';
import '../../../services/discovery/discovery.dart';
import '../../../services/security/fingerprint_store.dart';
import '../../../services/security/laptop_id.dart';
import '../../../services/security/laptop_link_store.dart';
import '../../../services/security/laptop_name.dart';
import '../../../services/transport/bt_hid_transport.dart';
import '../../../services/transport/transport.dart';
import '../../../services/transport/transport_switch.dart';
import 'connect_state.dart';

class ConnectCubit extends Cubit<ConnectState> {
  ConnectCubit(this._devices, this._browser, TransportSwitch transports)
    : _transports = transports,
      _transport = transports.network,
      _bluetooth = transports.bluetooth,
      super(const ConnectLoading());

  static const Duration reconnectStep = Duration(seconds: 1);
  static const Duration maxReconnectDelay = Duration(seconds: 30);
  static const int maxReconnectAttempts = 8;
  static const Duration bluetoothConnectTimeout = Duration(seconds: 20);
  static const String bluetoothPlatform = 'Bluetooth';

  final DeviceRepository _devices;
  final AgentBrowser _browser;
  final TransportSwitch _transports;
  final Transport _transport;
  final BtHidTransport? _bluetooth;

  StreamSubscription<List<DeviceModel>>? _registry;
  StreamSubscription<List<DiscoveredAgent>>? _discovery;
  StreamSubscription<Failure>? _discoveryErrors;
  StreamSubscription<TransportState>? _transportStates;
  StreamSubscription<Failure>? _pairingErrors;
  StreamSubscription<void>? _codeRequests;
  StreamSubscription<TransportState>? _bluetoothStates;
  StreamSubscription<void>? _bluetoothChanges;
  StreamSubscription<Failure>? _bluetoothErrors;

  BluetoothAccess? _bluetoothAccess;
  List<BtHidHost> _bluetoothHosts = const [];
  ConnectDevice? _bluetoothTarget;
  String? _bluetoothConnectedAddress;
  bool _bluetoothAwaitingHost = false;
  Timer? _bluetoothTimeout;
  String? _bluetoothError;
  int _bluetoothRefreshes = 0;
  int _bluetoothAttempts = 0;

  List<DeviceModel> _trusted = const [];
  final Completer<void> _registryReady = Completer<void>();
  List<DiscoveredAgent> _agents = const [];
  DiscoveredAgent? _connectedAgent;
  DiscoveredAgent? _pairingAgent;
  bool _needsCode = false;
  bool _codeRequested = false;
  String? _codeAgentId;
  String? _codeFingerprint;
  String? _codeTrustingId;
  int _dials = 0;
  final Set<String> _revokedIds = <String>{};
  final Set<String> _rejectedFingerprints = <String>{};
  String? _reconnectId;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  bool _userDisconnected = false;
  String? _connectingId;
  String? _connectionError;
  String? _registryError;

  Future<void> start() async {
    _transportStates ??= _transport.states.listen(_onTransportState);
    _pairingErrors ??= _transport.pairingErrors.listen(_onPairingError);
    _codeRequests ??= _transport.codeRequests.listen(_onCodeRequested);
    _discoveryErrors ??= _browser.errors.listen(_onDiscoveryError);
    final bluetooth = _bluetooth;
    if (bluetooth != null) {
      _bluetoothStates ??= bluetooth.states.listen(_onBluetoothState);
      _bluetoothChanges ??= bluetooth.hostsChanged.listen(
        (_) => unawaited(refreshBluetooth()),
      );
      _bluetoothErrors ??= bluetooth.pairingErrors.listen(_onBluetoothError);
      if (_transports.active == bluetooth &&
          bluetooth.state == TransportState.connected) {
        _bluetoothConnectedAddress = bluetooth.endpoint?.host;
      }
      unawaited(refreshBluetooth());
    }
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
    if (!agent.isCompatible) {
      _connectionError = _versionMessage(agent);
      _publish();
      return;
    }
    _cancelReconnect();
    _userDisconnected = false;
    _connectingId = agent.id;
    _publish();
    await _leaveBluetooth();
    await _dial(agent, manual: true);
  }

  Future<void> refreshBluetooth() async {
    final bluetooth = _bluetooth;
    if (bluetooth == null || isClosed) return;
    final refresh = ++_bluetoothRefreshes;
    final supported = await bluetooth.isSupported();
    final permitted = supported && await bluetooth.hasPermission();
    final enabled = supported && await bluetooth.isEnabled();
    final hosts = permitted && enabled
        ? await bluetooth.bondedHosts()
        : const <BtHidHost>[];
    if (isClosed || refresh != _bluetoothRefreshes) return;
    _bluetoothAccess = _accessFor(
      supported: supported,
      permitted: permitted,
      enabled: enabled,
      blocked: bluetooth.permissionBlocked,
    );
    _bluetoothHosts = hosts;
    _publish();
  }

  static BluetoothAccess? _accessFor({
    required bool supported,
    required bool permitted,
    required bool enabled,
    required bool blocked,
  }) {
    if (!supported) return null;
    if (!permitted) {
      return blocked
          ? BluetoothAccess.blocked
          : BluetoothAccess.needsPermission;
    }
    if (!enabled) return BluetoothAccess.off;
    return BluetoothAccess.ready;
  }

  Future<void> allowBluetooth() async {
    final bluetooth = _bluetooth;
    if (bluetooth == null) return;
    if (_bluetoothAccess == BluetoothAccess.blocked) {
      await bluetooth.openAppSettings();
    } else {
      await bluetooth.requestPermission();
    }
  }

  Future<void> openBluetoothSettings() async {
    await _bluetooth?.openBluetoothSettings();
  }

  Future<void> connectBluetooth(ConnectDevice computer) async {
    final bluetooth = _bluetooth;
    if (bluetooth == null || _bluetoothTarget != null) return;
    final attempt = ++_bluetoothAttempts;
    _bluetoothTarget = computer;
    _bluetoothError = null;
    _bluetoothAwaitingHost = false;
    _bluetoothTimeout?.cancel();
    _bluetoothTimeout = Timer(bluetoothConnectTimeout, _onBluetoothTimeout);
    _publish();
    if (bluetooth.state != TransportState.disconnected) {
      await bluetooth.disconnect();
    }
    await _hangUp(forget: false);
    if (!_isLiveAttempt(attempt)) return;
    _transports.use(bluetooth);
    try {
      await bluetooth.connect(
        TransportEndpoint(
          host: computer.id,
          label: computer.name,
          platform: BtHidHost.platformFor(computer.name),
          clientId: computer.id,
        ),
      );
      if (!_isLiveAttempt(attempt) ||
          bluetooth.state == TransportState.connected) {
        return;
      }
      if (bluetooth.state == TransportState.disconnected) {
        _failBluetoothAttempt(null);
        return;
      }
      _bluetoothAwaitingHost = true;
    } on Failure catch (failure) {
      if (_isLiveAttempt(attempt)) _failBluetoothAttempt(failure.message);
    } catch (_) {
      if (_isLiveAttempt(attempt)) {
        _failBluetoothAttempt(
          'Could not connect to ${computer.name} over Bluetooth.',
        );
      }
    }
  }

  bool _isLiveAttempt(int attempt) =>
      attempt == _bluetoothAttempts && _bluetoothTarget != null;

  Future<void> disconnectBluetooth() async {
    final bluetooth = _bluetooth;
    if (bluetooth == null) return;
    _bluetoothError = null;
    if (_bluetoothTarget != null) _endBluetoothAttempt();
    _transports.use(_transport);
    await bluetooth.release();
  }

  Future<void> _leaveBluetooth() async {
    final bluetooth = _bluetooth;
    if (bluetooth == null) return;
    _bluetoothError = null;
    if (_bluetoothTarget != null) _endBluetoothAttempt();
    _transports.use(_transport);
    await bluetooth.release();
  }

  void _endBluetoothAttempt() {
    _bluetoothTimeout?.cancel();
    _bluetoothTimeout = null;
    _bluetoothTarget = null;
    _bluetoothAwaitingHost = false;
    _publish();
  }

  void _failBluetoothAttempt(String? message) {
    if (message != null) _bluetoothError = message;
    _endBluetoothAttempt();
    final bluetooth = _bluetooth;
    if (bluetooth == null) return;
    _transports.use(_transport);
    unawaited(bluetooth.release());
  }

  void _onBluetoothTimeout() {
    final target = _bluetoothTarget;
    if (target == null) return;
    _failBluetoothAttempt(
      '${target.name} did not answer. '
      'Check it is nearby with Bluetooth on, then try again.',
    );
  }

  void _onBluetoothState(TransportState state) {
    final bluetooth = _bluetooth;
    if (bluetooth == null) return;
    switch (state) {
      case TransportState.connected:
        if (_transports.active != bluetooth) {
          unawaited(bluetooth.disconnect());
          return;
        }
        _bluetoothTimeout?.cancel();
        _bluetoothTimeout = null;
        _bluetoothTarget = null;
        _bluetoothAwaitingHost = false;
        _bluetoothError = null;
        _bluetoothConnectedAddress = bluetooth.endpoint?.host;
      case TransportState.disconnected:
        _bluetoothConnectedAddress = null;
        if (_bluetoothAwaitingHost) {
          _endBluetoothAttempt();
          return;
        }
      case TransportState.connecting:
      case TransportState.pairing:
        break;
    }
    _publish();
  }

  void _onBluetoothError(Failure failure) {
    if (_bluetoothTarget != null) {
      _failBluetoothAttempt(failure.message);
      return;
    }
    _bluetoothError = failure.message;
    _publish();
  }

  Future<void> _dial(DiscoveredAgent agent, {required bool manual}) async {
    if (!agent.isCompatible) {
      if (!manual) _cancelReconnect();
      _connectionError = _versionMessage(agent);
      _publish();
      return;
    }
    _dials += 1;
    _connectingId = agent.id;
    _codeRequested = false;
    if (manual) _connectionError = null;
    _publish();
    try {
      final pinned = await FingerprintStore.load(agent.id);
      final link = await LaptopLinkStore.forDial(
        agent.id,
        pinned: pinned != null,
      );
      if (_userDisconnected) return;
      await _transport.connect(
        TransportEndpoint(
          clientId: link.clientId,
          secret: link.secret,
          host: agent.host,
          label: LaptopName.shown(agent.name),
          platform: agent.platform,
          fingerprint: pinned,
          tcpPort: agent.tcpPort,
          udpPort: agent.udpPort,
        ),
      );
      _pairingAgent = _transport.state == TransportState.disconnected
          ? null
          : agent;
    } on Failure catch (failure) {
      if (manual && !_userDisconnected) {
        _connectionError = failure.message;
      }
      _pairingAgent = null;
      _connectedAgent = null;
    } catch (error) {
      if (manual && !_userDisconnected) {
        _connectionError =
            'Could not connect to ${LaptopName.shown(agent.name)}.';
      }
      _pairingAgent = null;
      _connectedAgent = null;
    } finally {
      _connectingId = null;
      _publish();
    }
  }

  Future<void> disconnect() => _hangUp(forget: false);

  Future<void> _hangUp({required bool forget}) async {
    _userDisconnected = true;
    _cancelReconnect();
    final dial = _dials;
    if (forget) {
      await _transport.forget();
    } else {
      await _transport.disconnect();
    }
    if (dial != _dials) return;
    _connectedAgent = null;
    _pairingAgent = null;
    _needsCode = false;
    _publish();
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectId = null;
    _reconnectAttempt = 0;
  }

  void _scheduleReconnect() {
    if (isClosed || _reconnectId == null) return;
    if (_reconnectAttempt >= maxReconnectAttempts) {
      _cancelReconnect();
      _connectionError =
          'That laptop stopped responding. Tap it again when it is back.';
      _publish();
      return;
    }
    final steps = 1 << _reconnectAttempt;
    var delay = reconnectStep * steps;
    if (delay > maxReconnectDelay) delay = maxReconnectDelay;
    _reconnectAttempt += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => unawaited(_attemptReconnect()));
  }

  Future<void> _attemptReconnect() async {
    final id = _reconnectId;
    if (id == null || isClosed || _connectingId != null) return;
    final agent = _agentFor(id);
    if (agent == null || _isAmbiguous(id)) {
      _scheduleReconnect();
      return;
    }
    await _dial(agent, manual: false);
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

  Future<void> rejectLaptop(String? laptopId) async {
    final agentId = _codeAgentId;
    final fingerprint = _codeFingerprint;
    _codeAgentId = null;
    _codeFingerprint = null;
    _needsCode = false;
    await disconnect();
    if (agentId == null ||
        fingerprint == null ||
        laptopId == null ||
        LaptopId.of(fingerprint) != laptopId) {
      return;
    }
    _rejectedFingerprints.add(fingerprint);
    if (await FingerprintStore.load(agentId) == fingerprint) {
      await FingerprintStore.forget(agentId);
    }
    if (_registeredFingerprint(agentId) == fingerprint) {
      unawaited(_revokeQuietly(agentId));
    }
  }

  Future<void> _revokeQuietly(String agentId) async {
    try {
      await _devices.revokeDevice(agentId);
    } on Failure {
      return;
    }
  }

  void dismissConnectionError() {
    if (_connectionError == null) return;
    _connectionError = null;
    _publish();
  }

  void _onRegistry(List<DeviceModel> registry) {
    final revoked = _revokedIn(registry)..remove(_pairingWithCodeId);
    _trusted = registry;
    if (!_registryReady.isCompleted) _registryReady.complete();
    _revokedIds
      ..addAll(revoked)
      ..removeAll({for (final device in registry) device.id});
    _registryError = null;
    unawaited(_inheritFingerprints(registry));
    _publish();
    if (revoked.isNotEmpty) unawaited(_forgetRevoked(revoked));
  }

  String? get _pairingWithCodeId {
    if (_codeTrustingId != null) return _codeTrustingId;
    return _codeRequested ? _pairingAgent?.id ?? _connectingId : null;
  }

  Set<String> _revokedIn(List<DeviceModel> registry) {
    final remaining = {for (final device in registry) device.id};
    return {
      for (final device in _trusted)
        if (!remaining.contains(device.id)) device.id,
    };
  }

  Future<void> _forgetRevoked(Set<String> revoked) async {
    final active = {
      _connectedAgent?.id,
      _reconnectId,
      _connectingId,
      _pairingAgent?.id,
    };
    if (active.any(revoked.contains)) {
      await _hangUp(forget: true);
    }
    for (final id in revoked) {
      await FingerprintStore.forget(id);
    }
  }

  Future<void> _inheritFingerprints(List<DeviceModel> registry) async {
    for (final device in registry) {
      if (device.certFingerprint.isEmpty) continue;
      final local = await FingerprintStore.load(device.id);
      if (local != null || !_stillTrusts(device)) continue;
      if (_rejectedFingerprints.contains(device.certFingerprint)) continue;
      await FingerprintStore.remember(device.id, device.certFingerprint);
    }
  }

  bool _stillTrusts(DeviceModel device) {
    return _trusted.any(
      (trusted) =>
          trusted.id == device.id &&
          trusted.certFingerprint == device.certFingerprint,
    );
  }

  Future<void> _trustAgent(DiscoveredAgent agent) async {
    final fingerprint = _transport.peerFingerprint;
    if (fingerprint == null || fingerprint.isEmpty) return;
    final secret = _transport.issuedSecret;
    final clientId = _transport.endpoint?.clientId;
    final dial = _dials;
    final withCode = _codeRequested;
    if (_revokedIds.contains(agent.id) && !withCode) return;
    _revokedIds.remove(agent.id);
    if (withCode) _codeTrustingId = agent.id;
    try {
      await FingerprintStore.remember(agent.id, fingerprint);
      if (secret != null && clientId != null) {
        await LaptopLinkStore.rememberSecret(
          agent.id,
          clientId: clientId,
          secret: secret,
        );
      }
    } finally {
      if (_codeTrustingId == agent.id) _codeTrustingId = null;
    }
    if (!withCode && !_registryReady.isCompleted) await _registryReady.future;
    if (!withCode && dial != _dials) return;
    if (_revokedIds.contains(agent.id) && !withCode) {
      await FingerprintStore.forget(agent.id);
      return;
    }
    final known = _registeredFingerprint(agent.id);
    if (known == null && !withCode) {
      _revokedIds.add(agent.id);
      await _forgetRevoked({agent.id});
      return;
    }
    if (known != fingerprint && !withCode) return;
    try {
      if (known == fingerprint) {
        await _devices.touchLastSeen(agent.id);
      } else {
        await _devices.registerDevice(
          DeviceModel(
            id: agent.id,
            name: LaptopName.shown(agent.name),
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
        if (!_userDisconnected && _reconnectId != null) _scheduleReconnect();
      case TransportState.connected:
        _needsCode = false;
        final paired = _pairingAgent;
        _pairingAgent = null;
        _reconnectId = paired?.id ?? _reconnectId;
        _reconnectAttempt = 0;
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _syncConnected();
        if (paired != null) unawaited(_trustAgent(paired));
      case TransportState.connecting:
      case TransportState.pairing:
        _syncConnected();
    }
    _publish();
  }

  void _onCodeRequested(void _) {
    if (_transport.peerFingerprint == null) return;
    _cancelReconnect();
    _askForCode();
    _codeRequested = true;
    _publish();
  }

  void _onPairingError(Failure failure) {
    _connectionError = failure.message;
    final refused = !_codeRequested && failure is! TransportFailure;
    if (failure is VersionFailure || refused) _cancelReconnect();
    _publish();
  }

  static String _versionMessage(DiscoveredAgent agent) {
    final laptop = LaptopName.shown(agent.name);
    return agent.isNewer
        ? '$laptop runs a newer Tapikapp. Update Tapikapp on this phone.'
        : 'Update Tapikapp on $laptop, then try again.';
  }

  void _askForCode() {
    _needsCode = true;
    _codeAgentId = _pairingAgent?.id;
    _codeFingerprint = _transport.peerFingerprint;
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
          name: LaptopName.shown(agent.name),
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
            name: LaptopName.shown(device.name),
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
        pairingLaptop: switch (_pairingAgent) {
          final agent? => LaptopName.plain(agent.name),
          null => null,
        },
        pairingLaptopId: _needsCode ? LaptopId.of(_codeFingerprint) : null,
        connectionError: _connectionError,
        registryError: _registryError,
        bluetooth: _bluetoothSection(),
      ),
    );
  }

  BluetoothSection? _bluetoothSection() {
    final access = _bluetoothAccess;
    if (access == null) return null;
    return BluetoothSection(
      access: access,
      computers: [
        for (final host in _bluetoothHosts)
          ConnectDevice(
            id: host.address,
            name: host.name,
            platform: bluetoothPlatform,
            status: _bluetoothStatusFor(host.address),
          ),
      ],
      error: _bluetoothError,
    );
  }

  ConnectDeviceStatus _bluetoothStatusFor(String address) {
    if (address == _bluetoothConnectedAddress) {
      return ConnectDeviceStatus.connected;
    }
    if (address == _bluetoothTarget?.id) return ConnectDeviceStatus.connecting;
    return ConnectDeviceStatus.available;
  }

  ConnectDeviceStatus _statusFor(DiscoveredAgent agent, Set<String> trusted) {
    if (agent.id == _connectedAgent?.id) return ConnectDeviceStatus.connected;
    if (agent.id == _connectingId || agent.id == _pairingAgent?.id) {
      return ConnectDeviceStatus.connecting;
    }
    if (!agent.isCompatible) {
      return agent.isNewer
          ? ConnectDeviceStatus.outdatedPhone
          : ConnectDeviceStatus.incompatible;
    }
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
    _bluetoothStates?.cancel();
    _bluetoothChanges?.cancel();
    _bluetoothErrors?.cancel();
    _bluetoothTimeout?.cancel();
    _reconnectTimer?.cancel();
    unawaited(_browser.stop());
    return super.close();
  }
}
