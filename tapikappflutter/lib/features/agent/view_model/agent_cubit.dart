import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failure.dart';
import '../../../services/discovery/discovery.dart';
import '../../../services/injector/injector.dart';
import '../../../services/security/laptop_id.dart';
import '../../../services/server/agent_server.dart';
import 'agent_state.dart';

class AgentCubit extends Cubit<AgentState> {
  AgentCubit({
    required AgentServer server,
    required Injector injector,
    required AgentAdvertiser advertiser,
    required String hostName,
    required String platformLabel,
    required bool isMacOS,
  }) : this._(
         server,
         injector,
         advertiser,
         AgentState(
           hostName: hostName,
           platformLabel: platformLabel,
           isMacOS: isMacOS,
           laptopId: LaptopId.of(server.certificate.fingerprint),
           phones: server.phones,
         ),
       );

  AgentCubit._(this._server, this._injector, this._advertiser, super.initial);

  static const Duration counterInterval = Duration(milliseconds: 250);

  final AgentServer _server;
  final Injector _injector;
  final AgentAdvertiser _advertiser;
  StreamSubscription<AgentServerState>? _link;
  Timer? _counter;
  String? _failedPhone;

  Future<void> start() async {
    await _link?.cancel();
    _link = _server.states.listen(_onServer);
    emit(state.copyWith(permission: _injector.refreshPermission()));
    try {
      await _server.start();
    } on Failure catch (failure) {
      emit(state.copyWith(error: () => failure.message));
      return;
    }
    try {
      await _advertiser.start();
    } on Failure catch (failure) {
      emit(state.copyWith(error: () => failure.message));
    }
  }

  Future<void> grantAccessibility() async {
    await _injector.requestPermission();
    emit(state.copyWith(permission: _injector.refreshPermission()));
  }

  void refreshPermission() {
    final permission = _injector.refreshPermission();
    if (permission != state.permission) {
      emit(state.copyWith(permission: permission));
    }
  }

  void setLaunchAtLogin(bool enabled) {
    if (enabled == state.launchAtLogin) return;
    emit(state.copyWith(launchAtLogin: enabled));
  }

  void openPairing() => _server.openPairing();

  void closePairing() => _server.closePairing();

  void disconnect() {
    if (!state.hasConnection) return;
    unawaited(_server.disconnectClient());
  }

  Future<void> forgetAllPhones() async {
    if (isClosed) return;
    _failedPhone = null;
    emit(state.copyWith(forgetFailed: false));
    try {
      await _server.forgetAllPhones();
    } catch (_) {
      return;
    }
  }

  Future<void> forgetPhone(String phoneId) async {
    if (isClosed) return;
    _failedPhone = null;
    emit(state.copyWith(forgetFailed: false));
    try {
      await _server.forgetPhone(phoneId);
    } catch (_) {
      if (isClosed) return;
      if (!_server.phones.any((phone) => phone.id == phoneId)) return;
      _failedPhone = phoneId;
      emit(state.copyWith(forgetFailed: true));
    }
  }

  void _onServer(AgentServerState server) {
    final failed = _failedPhone;
    if (failed != null && !server.phones.any((phone) => phone.id == failed)) {
      _failedPhone = null;
    }
    emit(
      state.copyWith(
        listening: server.listening,
        pairingCode: () => server.pairingCode,
        pairingOpenUntil: () => server.pairingOpenUntil,
        pairingStopped: server.pairingStopped,
        connectedPhone: () => server.client,
        connectedPhoneId: () => server.phoneId,
        phones: server.phones,
        forgetUnsaved: server.forgetUnsaved,
        forgetFailed: state.forgetFailed && _failedPhone != null,
        packetCount: server.hasClient ? _server.packetCount : 0,
        error: () => null,
      ),
    );
    if (server.hasClient) {
      refreshPermission();
      _counter ??= Timer.periodic(counterInterval, _tickCounter);
    } else {
      _injector.releaseAll();
      _counter?.cancel();
      _counter = null;
    }
  }

  void _tickCounter(Timer _) {
    final count = _server.packetCount;
    if (count != state.packetCount) {
      emit(state.copyWith(packetCount: count));
    }
  }

  @override
  Future<void> close() async {
    _counter?.cancel();
    await _link?.cancel();
    await _advertiser.stop();
    return super.close();
  }
}
