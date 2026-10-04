import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/agent_app.dart';
import 'app/controller_app.dart';
import 'core/router/auth_gate.dart';
import 'data/repositories/auth_repository.dart';
import 'data/sources/local_prefs_source.dart';
import 'features/agent/view/agent_window.dart';
import 'features/settings/view_model/theme_cubit.dart';
import 'firebase_options.dart';
import 'services/desktop/desktop_shell.dart';
import 'services/discovery/agent_identity.dart';
import 'services/discovery/bonsoir_discovery.dart';
import 'services/injector/macos_injector.dart';
import 'services/security/certificate_store.dart';
import 'services/security/pairing_guard.dart';
import 'services/security/trust_store.dart';
import 'services/server/agent_server.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final isController = Platform.isAndroid || Platform.isIOS;
  if (!isController) {
    final certificate = await CertificateStore.load(_hostName());
    final server = AgentServer(
      certificate: certificate,
      guard: PairingGuard(trustedClients: await TrustStore.load()),
      rememberClients: TrustStore.remember,
    );
    final injector = MacosInjector.open();
    final identity = await AgentIdentity.load();
    final advertiser = BonsoirAdvertiser(
      id: identity.id,
      name: _hostName(),
      platform: _desktopPlatformLabel(),
    );
    final input = server.packets.listen(injector.handle);
    final shell = DesktopShell(
      contentSize: AgentWindow.windowSize,
      onQuit: () async {
        injector.releaseAll();
        await input.cancel();
        injector.dispose();
        await advertiser.dispose();
        await server.dispose();
      },
    );
    await shell.initialize();
    runApp(
      AgentApp(
        server: server,
        injector: injector,
        advertiser: advertiser,
        hostName: _hostName(),
        platformLabel: _desktopPlatformLabel(),
        isMacOS: Platform.isMacOS,
      ),
    );
    await shell.installTray();
    return;
  }
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final prefs = LocalPrefsSource();
  final themeCubit = ThemeCubit();
  await themeCubit.load();
  final authGate = AuthGate(
    repository: AuthRepository(),
    prefs: prefs,
    loggedIn: await prefs.isLoggedIn(),
  );
  runApp(ControllerApp(themeCubit: themeCubit, authGate: authGate));
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
