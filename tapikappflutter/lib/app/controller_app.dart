import 'package:flutter/material.dart';

class ControllerApp extends StatelessWidget {
  const ControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Tapikapp',
      home: Scaffold(
        body: Center(child: Text('Controller')),
      ),
    );
  }
}
