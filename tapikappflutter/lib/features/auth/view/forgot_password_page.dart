import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/validation/validators.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../view_model/password_reset_cubit.dart';
import '../view_model/password_reset_state.dart';

class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: AppProviders.passwordResetCubit,
      child: _ForgotPasswordView(initialEmail: initialEmail),
    );
  }
}

class _ForgotPasswordView extends StatefulWidget {
  const _ForgotPasswordView({this.initialEmail});

  final String? initialEmail;

  @override
  State<_ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<_ForgotPasswordView> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  String? _sentTo;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _send() {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _error = null);
    context.read<PasswordResetCubit>().send(_email.text.trim());
  }

  void _resend() {
    setState(() => _error = null);
    context.read<PasswordResetCubit>().send(_sentTo!);
  }

  void _clearError(String _) {
    if (_error != null) setState(() => _error = null);
  }

  void _backToSignIn() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PasswordResetCubit, PasswordResetState>(
      listener: (context, state) {
        switch (state) {
          case PasswordResetSent(:final email):
            setState(() => _sentTo = email);
          case PasswordResetError(:final message):
            setState(() => _error = message);
          default:
            break;
        }
      },
      builder: (context, state) {
        final sending = state is PasswordResetSending;
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
                    child: IntrinsicHeight(
                      child: _sentTo == null
                          ? _buildForm(context, sending)
                          : _buildSent(context, sending, _sentTo!),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildHeader(
    BuildContext context, {
    required bool sending,
    required String title,
    required InlineSpan subtitle,
  }) {
    final colors = AppColors.of(context);
    return [
      const SizedBox(height: AppSpacing.xs),
      Align(
        alignment: Alignment.centerLeft,
        child: AppBackButton(
          circled: true,
          onPressed: sending ? null : _backToSignIn,
        ),
      ),
      Text(title, style: AppTextStyles.displayL),
      const SizedBox(height: AppSpacing.xs - AppSpacing.x3s),
      Text.rich(
        subtitle,
        style: AppTextStyles.bodyM.copyWith(color: colors.textSecondary),
      ),
      const SizedBox(height: AppSpacing.x2l + AppSpacing.x2s),
    ];
  }

  Widget _buildForm(BuildContext context, bool sending) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._buildHeader(
            context,
            sending: sending,
            title: 'Reset your password',
            subtitle: const TextSpan(
              text:
                  'Enter your email and we will send a link to set a new one.',
            ),
          ),
          AppTextField(
            label: 'Email address',
            controller: _email,
            hintText: 'you@example.com',
            helperText: 'We’ll never share your email.',
            errorText: _error,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            autocorrect: false,
            enabled: !sending,
            validator: Validators.email,
            onChanged: _clearError,
            onSubmitted: (_) => _send(),
          ),
          const SizedBox(height: AppSpacing.md),
          AppPrimaryButton(
            label: 'Send reset link',
            onPressed: _send,
            loading: sending,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: sending ? null : _backToSignIn,
            child: const Text('Back to sign in'),
          ),
          const SizedBox(height: AppSpacing.x4l + AppSpacing.x2s),
          const _Reassurance(),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildSent(BuildContext context, bool sending, String email) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._buildHeader(
          context,
          sending: sending,
          title: 'Check your email',
          subtitle: TextSpan(
            children: [
              const TextSpan(text: 'If an account exists for '),
              TextSpan(
                text: email,
                style: TextStyle(color: colors.textPrimary),
              ),
              const TextSpan(
                text: ', a link to set a new password is on its way.',
              ),
            ],
          ),
        ),
        AppPrimaryButton(
          label: 'Back to sign in',
          onPressed: sending ? null : _backToSignIn,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: sending ? null : _resend,
          child: sending
              ? SizedBox.square(
                  dimension: AppPrimaryButton.spinnerSize,
                  child: CircularProgressIndicator(
                    strokeWidth: AppPrimaryButton.spinnerStroke,
                    color: colors.textTertiary,
                  ),
                )
              : const Text('Resend link'),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            _error!,
            style: AppTextStyles.caption.copyWith(color: colors.textDanger),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: AppSpacing.x4l + AppSpacing.x2s),
        const _Reassurance(),
        const Spacer(),
      ],
    );
  }
}

class _Reassurance extends StatelessWidget {
  const _Reassurance();

  static const double tileSize = AppSpacing.x4l;
  static const Size glyphSize = Size(16, 10);
  static const double glyphStroke = 1.6;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: colors.borderDefault),
          ),
          child: SizedBox.square(
            dimension: tileSize,
            child: Center(
              child: CustomPaint(
                size: glyphSize,
                painter: _EnvelopePainter(
                  color: colors.accent,
                  strokeWidth: glyphStroke,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'The link expires in 30 minutes. Check spam if it does not arrive.',
            style: AppTextStyles.bodyS.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _EnvelopePainter extends CustomPainter {
  const _EnvelopePainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final radius = Radius.circular(strokeWidth);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      paint,
    );
    final flap = Path()
      ..moveTo(0, strokeWidth / 2)
      ..lineTo(size.width / 2, size.height * 0.6)
      ..lineTo(size.width, strokeWidth / 2);
    canvas.drawPath(flap, paint);
  }

  @override
  bool shouldRepaint(_EnvelopePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}
