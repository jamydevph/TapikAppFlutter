import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/agent_app.dart';
import 'app/controller_app.dart';
import 'features/agent/view/agent_window.dart';
import 'features/settings/view_model/theme_cubit.dart';
import 'firebase_options.dart';
import 'services/desktop/desktop_shell.dart';
import 'services/server/agent_server.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final isController = Platform.isAndroid || Platform.isIOS;
  if (!isController) {
    final server = AgentServer();
    final shell = DesktopShell(
      contentSize: AgentWindow.windowSize,
      onQuit: server.dispose,
    );
    await shell.initialize();
    runApp(
      AgentApp(
        server: server,
        hostName: _hostName(),
        platformLabel: _desktopPlatformLabel(),
        isMacOS: Platform.isMacOS,
      ),
    );
    await shell.installTray();
    return;
  }
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final themeCubit = ThemeCubit();
  await themeCubit.load();
  runApp(ControllerApp(themeCubit: themeCubit));
}

String _hostName() {
  const localSuffix = '.local';
  final name = Platform.localHostname;
  return name.endsWith(localSuffix)
      ? name.substring(0, name.length - localSuffix.length)
      : name;
}

String _desktopPlatformLabel() {
  if (Platform.isMacOS) return 'macOS';
  if (Platform.isWindows) return 'Windows';
  return 'Linux';
}
