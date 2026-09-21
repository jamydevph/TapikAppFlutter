import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/app_tokens.dart';

class DesktopShell with TrayListener, WindowListener {
  DesktopShell({required this.contentSize, this.onQuit});

  static const String showKey = 'show';
  static const String quitKey = 'quit';
  static const String trayIconPng = 'assets/branding/tray_icon.png';
  static const String trayIconIco = 'assets/branding/tray_icon.ico';
  static const Duration firstFrameTimeout = Duration(seconds: 2);

  final Size contentSize;
  final Future<void> Function()? onQuit;

  Future<void> initialize() async {
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    final options = WindowOptions(
      size: contentSize,
      center: true,
      title: AppBrand.name,
    );
    await windowManager.waitUntilReadyToShow(options, _present);
  }

  Future<void> installTray() async {
    trayManager.addListener(this);
    await trayManager.setIcon(
      Platform.isWindows ? trayIconIco : trayIconPng,
      isTemplate: true,
    );
    await trayManager.setToolTip(AppBrand.name);
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: showKey, label: 'Show ${AppBrand.name}'),
          MenuItem.separator(),
          MenuItem(key: quitKey, label: 'Quit ${AppBrand.name}'),
        ],
      ),
    );
  }

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> quit() async {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await onQuit?.call();
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  Future<void> _present() async {
    final titleBar = await windowManager.getTitleBarHeight();
    final frame = Size(contentSize.width, contentSize.height + titleBar);
    await windowManager.setMinimumSize(frame);
    await windowManager.setMaximumSize(frame);
    await windowManager.setSize(frame);
    await windowManager.center();
    if (Platform.isMacOS) {
      await windowManager.setResizable(false);
    } else {
      await windowManager.setMaximizable(false);
    }
    await windowManager.setPreventClose(true);
    await WidgetsBinding.instance.waitUntilFirstFrameRasterized.timeout(
      firstFrameTimeout,
      onTimeout: () {},
    );
    await showWindow();
  }

  @override
  void onWindowClose() {
    windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case showKey:
        scheduleMicrotask(showWindow);
      case quitKey:
        scheduleMicrotask(quit);
    }
  }
}
