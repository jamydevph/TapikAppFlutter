import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_page.dart';

class TrackpadPage extends StatelessWidget {
  const TrackpadPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      title: 'Trackpad',
      message: 'Drag to move, tap to click.',
    );
  }
}
