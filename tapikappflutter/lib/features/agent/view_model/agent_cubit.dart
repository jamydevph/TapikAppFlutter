import 'package:flutter_bloc/flutter_bloc.dart';

import 'agent_state.dart';

class AgentCubit extends Cubit<AgentState> {
  AgentCubit({
    required String hostName,
    required String platformLabel,
    required bool isMacOS,
  }) : super(
         AgentState(
           hostName: hostName,
           platformLabel: platformLabel,
           isMacOS: isMacOS,
         ),
       );

  void setLaunchAtLogin(bool enabled) {
    if (enabled == state.launchAtLogin) return;
    emit(state.copyWith(launchAtLogin: enabled));
  }

  void disconnect() {
    if (!state.hasConnection) return;
    emit(state.copyWith(connectedPhone: () => null));
  }
}
