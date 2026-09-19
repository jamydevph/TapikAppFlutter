import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_shell.dart';
import '../../features/auth/view/forgot_password_page.dart';
import '../../features/auth/view/login_page.dart';
import '../../features/auth/view/signup_page.dart';
import '../../features/auth/view/splash_page.dart';
import '../../features/connect/view/connect_page.dart';
import '../../features/connect/view/pairing_code_page.dart';
import '../../features/keyboard/view/keyboard_page.dart';
import '../../features/presenter/view/presenter_page.dart';
import '../../features/settings/view/settings_page.dart';
import '../../features/trackpad/view/trackpad_page.dart';
import 'app_routes.dart';

class AppRouter {
  AppRouter({GoRouterRedirect? redirect, Listenable? refreshListenable})
      : router = GoRouter(
          initialLocation: AppRoutes.splash,
          redirect: redirect,
          refreshListenable: refreshListenable,
          routes: [
            GoRoute(
              path: AppRoutes.splash,
              pageBuilder: (context, state) {
                return NoTransitionPage(
                  key: state.pageKey,
                  child: const SplashPage(),
                );
              },
            ),
            GoRoute(
              path: AppRoutes.login,
              pageBuilder: (context, state) {
                return NoTransitionPage(
                  key: state.pageKey,
                  child: const LoginPage(),
                );
              },
            ),
            GoRoute(
              path: AppRoutes.signup,
              builder: (context, state) => const SignupPage(),
            ),
            GoRoute(
              path: AppRoutes.forgotPassword,
              builder: (context, state) => ForgotPasswordPage(
                initialEmail: state.extra as String?,
              ),
            ),
            GoRoute(
              path: AppRoutes.pairing,
              builder: (context, state) => PairingCodePage(
                deviceName: state.extra as String?,
              ),
            ),
            StatefulShellRoute.indexedStack(
              pageBuilder: (context, state, navigationShell) {
                return NoTransitionPage(
                  key: state.pageKey,
                  child: AppShell(navigationShell: navigationShell),
                );
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
