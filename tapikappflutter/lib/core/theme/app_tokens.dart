import 'package:flutter/material.dart';

class AppSpacing {
  const AppSpacing._();

  static const double x3s = 2;
  static const double x2s = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double x2l = 32;
  static const double x3l = 40;
  static const double x4l = 48;
  static const double x5l = 64;
}

class AppRadius {
  const AppRadius._();

  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double x2l = 28;
  static const double full = 999;
}

class AppShadows {
  const AppShadows._();

  static const List<BoxShadow> card = [
    BoxShadow(offset: Offset(0, 2), blurRadius: 8, color: Color(0x73000000)),
  ];

  static const List<BoxShadow> raised = [
    BoxShadow(offset: Offset(0, 4), blurRadius: 16, color: Color(0x80000000)),
  ];

  static const List<BoxShadow> sheet = [
    BoxShadow(offset: Offset(0, 8), blurRadius: 28, color: Color(0x8C000000)),
  ];

  static const List<BoxShadow> glowPrimary = [
    BoxShadow(offset: Offset(0, 6), blurRadius: 20, color: Color(0x667C5CFF)),
  ];

  static const List<BoxShadow> glowSuccess = [
    BoxShadow(blurRadius: 12, color: Color(0x59A3E635)),
  ];
}

class AppComponentSizes {
  const AppComponentSizes._();

  static const double buttonHeight = 52;
  static const double logoMark = 88;
}

class AppBrand {
  const AppBrand._();

  static const String name = 'Tapikapp';
  static const String tagline = 'Your phone, your laptop’s keyboard';
}
