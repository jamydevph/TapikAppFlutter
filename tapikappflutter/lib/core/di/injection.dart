import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/device_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/sources/local_prefs_source.dart';
import '../../features/auth/view_model/auth_cubit.dart';
import '../../features/auth/view_model/password_reset_cubit.dart';
import '../../features/connect/view_model/connect_cubit.dart';
import '../../features/settings/view_model/theme_cubit.dart';

class AppProviders extends StatelessWidget {
  const AppProviders({
    super.key,
    required this.themeCubit,
    required this.child,
  });

  final ThemeCubit themeCubit;
  final Widget child;

  static PasswordResetCubit passwordResetCubit(BuildContext context) {
    return PasswordResetCubit(context.read<AuthRepository>());
  }

  static ConnectCubit connectCubit(BuildContext context) {
    return ConnectCubit(context.read<DeviceRepository>());
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => LocalPrefsSource()),
        RepositoryProvider(create: (_) => AuthRepository()),
        RepositoryProvider(create: (_) => DeviceRepository()),
        RepositoryProvider(
          create: (_) => SettingsRepository(),
          dispose: (repository) => repository.dispose(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: themeCubit),
          BlocProvider(
            create: (context) => AuthCubit(
              repository: context.read<AuthRepository>(),
              prefs: context.read<LocalPrefsSource>(),
            ),
          ),
        ],
        child: child,
      ),
    );
  }
}
