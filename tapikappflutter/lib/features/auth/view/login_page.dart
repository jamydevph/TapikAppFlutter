import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/validation/validators.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/logo_mark.dart';
import '../view_model/auth_cubit.dart';
import '../view_model/auth_state.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _authError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _authError = null);
    context.read<AuthCubit>().signIn(
      email: _email.text.trim(),
      password: _password.text,
    );
  }

  void _clearAuthError(String _) {
    if (_authError != null) setState(() => _authError = null);
  }

  void _forgotPassword() {
    final email = _email.text.trim();
    context.push(AppRoutes.forgotPassword, extra: email.isEmpty ? null : email);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthCubit, AuthState>(
      listenWhen: (_, _) => ModalRoute.of(context)?.isCurrent ?? true,
      listener: (context, state) {
        switch (state) {
          case Authenticated():
            context.go(AppRoutes.connect);
          case AuthError(:final message):
            setState(() => _authError = message);
          default:
            break;
        }
      },
      builder: (context, state) {
        final loading = state is AuthLoading;
        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(child: _buildForm(context, loading)),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildForm(BuildContext context, bool loading) {
    final colors = AppColors.of(context);
    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.x3l + AppSpacing.x2s),
            const Align(
              alignment: Alignment.centerLeft,
              child: LogoMark(
                size: AppComponentSizes.logoMarkCompact,
                glow: false,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Welcome back', style: AppTextStyles.displayL),
            const SizedBox(height: AppSpacing.xs - AppSpacing.x3s),
            Text(
              'Sign in to sync your paired laptops across devices.',
              style: AppTextStyles.bodyM.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppTextField(
              label: 'Email address',
              controller: _email,
              hintText: 'you@example.com',
              helperText: 'We’ll never share your email.',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              autocorrect: false,
              enabled: !loading,
              validator: Validators.email,
              onChanged: _clearAuthError,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              label: 'Password',
              controller: _password,
              helperText: 'At least ${AuthCubit.minPasswordLength} characters.',
              errorText: _authError,
              obscureText: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              enabled: !loading,
              validator: (value) =>
                  Validators.required(value, 'Enter your password.'),
              onChanged: _clearAuthError,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.xs - AppSpacing.x2s),
            Align(
              alignment: Alignment.centerRight,
              child: _LinkText(
                'Forgot password?',
                onTap: loading ? null : _forgotPassword,
              ),
            ),
            const SizedBox(height: AppSpacing.x2l - AppSpacing.x3s),
            AppPrimaryButton(
              label: 'Sign in',
              onPressed: _submit,
              loading: loading,
            ),
            const SizedBox(height: AppSpacing.lg + AppSpacing.x3s),
            Text(
              'Tapikapp never sends your keystrokes to the cloud — '
              'only which laptops you trust.',
              style: AppTextStyles.caption.copyWith(color: colors.textTertiary),
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            const SizedBox(height: AppSpacing.xl),
            Padding(
              padding: const EdgeInsets.only(
                bottom: AppSpacing.x2l - AppSpacing.x2s,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'New here?',
                    style: AppTextStyles.labelM.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs - AppSpacing.x3s),
                  _LinkText(
                    'Create an account',
                    onTap: loading
                        ? null
                        : () => context.push(AppRoutes.signup),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkText extends StatelessWidget {
  const _LinkText(this.text, {required this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2s),
        child: Text(
          text,
          style: AppTextStyles.labelM.copyWith(
            color: onTap == null ? colors.textTertiary : colors.accent,
          ),
        ),
      ),
    );
  }
}
