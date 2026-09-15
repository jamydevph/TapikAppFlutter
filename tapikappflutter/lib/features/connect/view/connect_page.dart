import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_page.dart';

class ConnectPage extends StatelessWidget {
  const ConnectPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      title: 'Your laptops',
      message: 'Laptops on this network will appear here.',
    );
  }
}
