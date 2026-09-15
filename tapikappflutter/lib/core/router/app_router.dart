import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_shell.dart';
import '../../features/connect/view/connect_page.dart';
import '../../features/keyboard/view/keyboard_page.dart';
import '../../features/presenter/view/presenter_page.dart';
import '../../features/settings/view/settings_page.dart';
import '../../features/trackpad/view/trackpad_page.dart';
import 'app_routes.dart';

class AppRouter {
  AppRouter({GoRouterRedirect? redirect, Listenable? refreshListenable})
      : router = GoRouter(
          initialLocation: AppRoutes.connect,
          redirect: redirect,
          refreshListenable: refreshListenable,
          routes: [
            StatefulShellRoute.indexedStack(
              builder: (context, state, navigationShell) {
                return AppShell(navigationShell: navigationShell);
              },
              branches: [
                _branch(AppRoutes.connect, const ConnectPage()),
                _branch(AppRoutes.trackpad, const TrackpadPage()),
                _branch(AppRoutes.keyboard, const KeyboardPage()),
                _branch(AppRoutes.present, const PresenterPage()),
                _branch(AppRoutes.settings, const SettingsPage()),
              ],
            ),
          ],
        );

  final GoRouter router;

  void dispose() => router.dispose();

  static StatefulShellBranch _branch(String path, Widget page) {
    return StatefulShellBranch(
      routes: [
        GoRoute(
          path: path,
          pageBuilder: (context, state) => NoTransitionPage(child: page),
        ),
      ],
    );
  }
}
