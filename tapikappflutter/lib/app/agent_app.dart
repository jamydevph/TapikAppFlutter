import 'package:flutter/material.dart';

class AgentApp extends StatelessWidget {
  const AgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Tapikapp Agent',
      home: Scaffold(
        body: Center(child: Text('Agent')),
      ),
    );
  }
}
