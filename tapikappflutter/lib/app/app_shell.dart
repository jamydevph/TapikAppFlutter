import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/app_tab_bar.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

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
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: AppTabBar(
        items: tabs,
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
