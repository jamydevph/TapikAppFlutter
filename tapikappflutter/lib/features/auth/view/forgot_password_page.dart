import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_page.dart';

class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: PlaceholderPage(
        title: 'Forgot password',
        message: 'We’ll email you a link to reset it.',
      ),
    );
  }
}
