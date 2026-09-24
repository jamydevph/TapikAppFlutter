import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/app_tokens.dart';
import '../features/agent/view/agent_window.dart';
import '../features/agent/view_model/agent_cubit.dart';
import '../services/server/agent_server.dart';

class AgentApp extends StatelessWidget {
  const AgentApp({
    super.key,
    required this.server,
    required this.hostName,
    required this.platformLabel,
    required this.isMacOS,
  });

  final AgentServer server;
  final String hostName;
  final String platformLabel;
  final bool isMacOS;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AgentCubit(
        server: server,
        hostName: hostName,
        platformLabel: platformLabel,
        isMacOS: isMacOS,
      )..start(),
      child: MaterialApp(
        title: '${AppBrand.name} Agent',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const AgentWindow(),
      ),
    );
  }
}
