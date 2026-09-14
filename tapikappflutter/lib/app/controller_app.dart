import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_theme_mode.dart';
import '../core/theme/app_tokens.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/logo_mark.dart';
import '../features/settings/view_model/theme_cubit.dart';

class ControllerApp extends StatelessWidget {
  const ControllerApp({super.key, required this.themeCubit});

  final ThemeCubit themeCubit;

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: themeCubit,
      child: BlocBuilder<ThemeCubit, AppThemeMode>(
        builder: (context, mode) {
          return MaterialApp(
            title: AppBrand.name,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: mode.material,
            home: const _ThemePlaceholder(),
          );
        },
      ),
    );
  }
}

class _ThemePlaceholder extends StatelessWidget {
  const _ThemePlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const LogoMark(),
              const SizedBox(height: AppSpacing.xl),
              Text(AppBrand.name, style: AppTextStyles.displayL),
              const SizedBox(height: AppSpacing.xs),
              Text(
                AppBrand.tagline,
                style: AppTextStyles.bodyM.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.x3l),
              BlocBuilder<ThemeCubit, AppThemeMode>(
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
            ],
          ),
        ),
      ),
    );
  }
}
