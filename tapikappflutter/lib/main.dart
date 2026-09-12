import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/agent_app.dart';
import 'app/controller_app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  final isController = Platform.isAndroid || Platform.isIOS;
  if (isController) {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  runApp(isController ? const ControllerApp() : const AgentApp());
}
