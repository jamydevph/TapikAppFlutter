import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_page.dart';

class SignupPage extends StatelessWidget {
  const SignupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: PlaceholderPage(
        title: 'Create your account',
        message: 'Sign in on any phone and your laptops are already there.',
      ),
    );
  }
}
