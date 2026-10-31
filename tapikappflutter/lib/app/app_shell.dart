import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/di/injection.dart';
import '../core/widgets/app_tab_bar.dart';
import '../features/connect/view/connection_banner.dart';
import '../features/connect/view_model/connect_cubit.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  static const int connectTab = 0;
  static const List<AppTabItem> tabs = [
    AppTabItem(label: 'Connect', icon: Icons.devices_outlined),
    AppTabItem(label: 'Trackpad', icon: Icons.highlight_alt_outlined),
    AppTabItem(label: 'Keyboard', icon: Icons.keyboard_outlined),
    AppTabItem(label: 'Present', icon: Icons.desktop_windows_outlined),
    AppTabItem(label: 'Settings', icon: Icons.tune),
  ];

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AppProviders.connectCubit(context)..start(),
      child: _LinkLifecycle(
        child: Scaffold(
          body: MediaQuery.withClampedTextScaling(
            maxScaleFactor: AppTabBar.maxTextScale,
            child: Stack(
              children: [
                navigationShell,
                ConnectionBanner(
                  onConnect: () => navigationShell.goBranch(connectTab),
                ),
              ],
            ),
          ),
          bottomNavigationBar: AppTabBar(
            items: tabs,
            currentIndex: navigationShell.currentIndex,
            onTap: (index) => navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkLifecycle extends StatefulWidget {
  const _LinkLifecycle({required this.child});

  final Widget child;

  @override
  State<_LinkLifecycle> createState() => _LinkLifecycleState();
}

class _LinkLifecycleState extends State<_LinkLifecycle>
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
    final cubit = context.read<ConnectCubit>();
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        cubit.appPaused();
      case AppLifecycleState.resumed:
        cubit.appResumed();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        return;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
