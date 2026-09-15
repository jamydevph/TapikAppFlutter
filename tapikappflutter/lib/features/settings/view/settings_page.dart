import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme_mode.dart';
import '../../../core/widgets/placeholder_page.dart';
import '../view_model/theme_cubit.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PlaceholderPage(
      title: 'Settings',
      message: 'Sensitivity, scrolling, haptics and theme.',
      trailing: BlocBuilder<ThemeCubit, AppThemeMode>(
        builder: (context, mode) {
          return SegmentedButton<AppThemeMode>(
            segments: const [
              ButtonSegment(value: AppThemeMode.light, label: Text('Light')),
              ButtonSegment(value: AppThemeMode.dark, label: Text('Dark')),
              ButtonSegment(value: AppThemeMode.system, label: Text('System')),
            ],
            selected: {mode},
            onSelectionChanged: (selection) {
              context.read<ThemeCubit>().setMode(selection.first);
            },
          );
        },
      ),
    );
  }
}
