import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failure.dart';
import '../../../services/injector/injector.dart';
import '../../../services/server/agent_server.dart';
import 'agent_state.dart';

class AgentCubit extends Cubit<AgentState> {
  AgentCubit({
    required AgentServer server,
    required Injector injector,
    required String hostName,
    required String platformLabel,
    required bool isMacOS,
  }) : this._(
         server,
         injector,
         AgentState(
           hostName: hostName,
           platformLabel: platformLabel,
           isMacOS: isMacOS,
         ),
       );

  AgentCubit._(this._server, this._injector, super.initial);

  static const Duration counterInterval = Duration(milliseconds: 250);

  final AgentServer _server;
  final Injector _injector;
  StreamSubscription<AgentServerState>? _link;
  Timer? _counter;

  Future<void> start() async {
    await _link?.cancel();
    _link = _server.states.listen(_onServer);
    emit(state.copyWith(permission: _injector.refreshPermission()));
    try {
      await _server.start();
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

  void disconnect() {
    if (!state.hasConnection) return;
    unawaited(_server.disconnectClient());
  }

  void _onServer(AgentServerState server) {
    emit(
      state.copyWith(
        listening: server.listening,
        connectedPhone: () => server.client,
        packetCount: server.hasClient ? _server.packetCount : 0,
        error: () => null,
      ),
    );
    if (server.hasClient) {
      refreshPermission();
      _counter ??= Timer.periodic(counterInterval, _tickCounter);
    } else {
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
    return super.close();
  }
}
