import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/di/injection.dart';
import '../core/router/app_router.dart';
import '../core/router/auth_gate.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_theme_mode.dart';
import '../core/theme/app_tokens.dart';
import '../features/settings/view_model/theme_cubit.dart';
import '../services/transport/transport.dart';

class ControllerApp extends StatefulWidget {
  const ControllerApp({
    super.key,
    required this.themeCubit,
    required this.authGate,
  });

  final ThemeCubit themeCubit;
  final AuthGate authGate;

  @override
  State<ControllerApp> createState() => _ControllerAppState();
}

class _ControllerAppState extends State<ControllerApp> {
  late final AppRouter _router = AppRouter(authGate: widget.authGate);

  @override
  void dispose() {
    _router.dispose();
    widget.authGate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppProviders(
      themeCubit: widget.themeCubit,
      child: BlocBuilder<ThemeCubit, AppThemeMode>(
        builder: (context, mode) {
          return MaterialApp.router(
            title: AppBrand.name,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: mode.material,
            routerConfig: _router.router,
            builder: (context, child) =>
                _LifecycleGuard(child: child ?? const SizedBox.shrink()),
          );
        },
      ),
    );
  }
}

class _LifecycleGuard extends StatefulWidget {
  const _LifecycleGuard({required this.child});

  final Widget child;

  @override
  State<_LifecycleGuard> createState() => _LifecycleGuardState();
}

class _LifecycleGuardState extends State<_LifecycleGuard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        final transport = context.read<Transport>();
        if (transport.state != TransportState.disconnected) {
          unawaited(transport.disconnect());
        }
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        return;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
