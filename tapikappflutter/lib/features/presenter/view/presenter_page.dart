import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_page.dart';

class PresenterPage extends StatelessWidget {
  const PresenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      title: 'Present',
      message: 'Next, previous and black screen for your slides.',
    );
  }
}
