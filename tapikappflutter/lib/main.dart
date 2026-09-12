import 'dart:io';

import 'package:flutter/material.dart';

import 'app/agent_app.dart';
import 'app/controller_app.dart';

void main() {
  runApp(_rootForPlatform());
}

Widget _rootForPlatform() {
  if (Platform.isAndroid || Platform.isIOS) {
    return const ControllerApp();
  }
  return const AgentApp();
}
