import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/agent_app.dart';
import 'app/controller_app.dart';
import 'features/settings/view_model/theme_cubit.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final isController = Platform.isAndroid || Platform.isIOS;
  if (!isController) {
    runApp(const AgentApp());
    return;
  }
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final themeCubit = ThemeCubit();
  await themeCubit.load();
  runApp(ControllerApp(themeCubit: themeCubit));
}
