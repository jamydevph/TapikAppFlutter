import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/validation/validators.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_checkbox.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../view_model/auth_cubit.dart';
import '../view_model/auth_state.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _agreed = false;
  String? _authError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (!_agreed) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _authError = null);
    context.read<AuthCubit>().signUp(
      email: _email.text.trim(),
      password: _password.text,
    );
  }

  void _clearAuthError(String _) {
    if (_authError != null) setState(() => _authError = null);
  }

  void _backToSignIn() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.login);
    }
  }

  String? _validatePassword(String? value) {
    return Validators.required(value, 'Create a password.') ??
        Validators.minLength(
          value,
          AuthCubit.minPasswordLength,
          'Use at least ${AuthCubit.minPasswordLength} characters.',
        );
  }

  String? _validateConfirm(String? value) {
    return Validators.required(value, 'Repeat your password.') ??
        (value != _password.text ? 'Passwords do not match.' : null);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthCubit, AuthState>(
      listenWhen: (_, _) => ModalRoute.of(context)?.isCurrent ?? true,
      listener: (context, state) {
        switch (state) {
          case Authenticated():
            TextInput.finishAutofillContext();
            context.go(AppRoutes.connect);
          case AuthError(:final message):
            setState(() => _authError = message);
          default:
            break;
        }
      },
      builder: (context, state) {
        final loading = state is AuthLoading;
        return PopScope(
          canPop: !loading,
          child: Scaffold(
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
                      child: IntrinsicHeight(
                        child: _buildForm(context, loading),
                      ),
                    ),
                  );
                },
              ),
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
        onDisposeAction: AutofillContextAction.cancel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: AppBackButton(onPressed: loading ? null : _backToSignIn),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('Create your account', style: AppTextStyles.displayL),
            const SizedBox(height: AppSpacing.xs - AppSpacing.x3s),
            Text(
              'Sign in on any phone and your laptops are already there.',
              style: AppTextStyles.bodyM.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Email address',
              controller: _email,
              hintText: 'you@example.com',
              helperText: 'We’ll never share your email.',
              errorText: _authError,
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
              hintText: 'Create a password',
              helperText: 'At least ${AuthCubit.minPasswordLength} characters.',
              obscureText: true,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              enabled: !loading,
              validator: _validatePassword,
              onChanged: _clearAuthError,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              label: 'Confirm password',
              controller: _confirm,
              hintText: 'Repeat your password',
              helperText: 'We’ll never share your email.',
              obscureText: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              enabled: !loading,
              validator: _validateConfirm,
              onChanged: _clearAuthError,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.md - AppSpacing.x2s),
            AppCheckbox(
              value: _agreed,
              onChanged: loading
                  ? null
                  : (value) => setState(() => _agreed = value),
              label: Text(
                'I agree to the Terms and Privacy Policy',
                style: AppTextStyles.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppPrimaryButton(
              label: 'Create account',
              onPressed: _agreed ? _submit : null,
              loading: loading,
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
                    'Already have an account?',
                    style: AppTextStyles.labelM.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs - AppSpacing.x3s),
                  InkWell(
                    onTap: loading ? null : _backToSignIn,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.x2s,
                      ),
                      child: Text(
                        'Sign in',
                        style: AppTextStyles.labelM.copyWith(
                          color: loading ? colors.textTertiary : colors.accent,
                        ),
                      ),
                    ),
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
