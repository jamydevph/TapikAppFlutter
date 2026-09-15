import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_page.dart';

class KeyboardPage extends StatelessWidget {
  const KeyboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      title: 'Keyboard',
      message: 'Type here to send text to your laptop.',
    );
  }
}
