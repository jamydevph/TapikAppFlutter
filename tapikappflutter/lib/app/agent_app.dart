import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class AgentApp extends StatelessWidget {
  const AgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tapikapp Agent',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const Scaffold(
        body: Center(child: Text('Agent')),
      ),
    );
  }
}
