import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_primary_button.dart';
import '../view_model/pairing_cubit.dart';
import '../view_model/pairing_state.dart';

class PairingCodePage extends StatelessWidget {
  const PairingCodePage({super.key, this.deviceName});

  final String? deviceName;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PairingCubit()..start(),
      child: _PairingView(deviceName: deviceName),
    );
  }
}

class _PairingView extends StatefulWidget {
  const _PairingView({this.deviceName});

  final String? deviceName;

  @override
  State<_PairingView> createState() => _PairingViewState();
}

class _PairingViewState extends State<_PairingView> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _editableKey = GlobalKey<EditableTextState>();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _close([String? code]) {
    if (context.canPop()) {
      context.pop(code);
    } else {
      context.go(AppRoutes.connect);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final laptop = widget.deviceName ?? 'the laptop';
    return BlocConsumer<PairingCubit, PairingState>(
      listener: (context, state) {
        if (state is PairingExpired) _focusNode.unfocus();
      },
      builder: (context, state) {
        final cubit = context.read<PairingCubit>();
        final expired = state is PairingExpired;
        final complete = cubit.isComplete;
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: AppSpacing.x2s),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: AppBackButton(onPressed: _close),
                          ),
                          const SizedBox(height: AppSpacing.x2s),
                          Text(
                            'Enter the pairing code',
                            style: AppTextStyles.displayL,
                          ),
                          const SizedBox(
                            height: AppSpacing.xs - AppSpacing.x3s,
                          ),
                          Text(
                            'It is showing on $laptop right now.',
                            style: AppTextStyles.bodyM.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(
                            height:
                                AppSpacing.x4l + AppSpacing.xs + AppSpacing.x3s,
                          ),
                          _CodeInput(
                            controller: _controller,
                            focusNode: _focusNode,
                            editableKey: _editableKey,
                            code: state.code,
                            enabled: !expired,
                            onChanged: cubit.updateCode,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            switch (state) {
                              PairingEntering(:final secondsLeft) =>
                                'Code expires in $secondsLeft '
                                    'second${secondsLeft == 1 ? '' : 's'}.',
                              PairingExpired() => 'This code has expired. Ask the laptop for a new one.',
                            },
                            style: AppTextStyles.caption.copyWith(
                              color: expired
                                  ? colors.textDanger
                                  : colors.textWarning,
                            ),
                          ),
                          const SizedBox(
                            height: AppSpacing.xl + AppSpacing.x3s,
                          ),
                          const _LockNote(),
                          const Spacer(),
                          const SizedBox(height: AppSpacing.xl),
                          AppPrimaryButton(
                            label: 'Pair laptop',
                            onPressed: complete && !expired
                                ? () => _close(state.code)
                                : null,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextButton(
                            onPressed: _close,
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(
                            height:
                                AppSpacing.x4l + AppSpacing.xs - AppSpacing.x3s,
                          ),
                        ],
                      ),
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
}

class _CodeInput extends StatelessWidget {
  const _CodeInput({
    required this.controller,
    required this.focusNode,
    required this.editableKey,
    required this.code,
    required this.enabled,
    required this.onChanged,
  });

  static const double boxWidth = 50;
  static const double boxHeight = 60;
  static const double gap = AppSpacing.xs;
  static const double focusedBorder = 1.5;

  final TextEditingController controller;
  final FocusNode focusNode;
  final GlobalKey<EditableTextState> editableKey;
  final String code;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final activeIndex = code.length < PairingCubit.codeLength
        ? code.length
        : PairingCubit.codeLength - 1;
    return Stack(
      children: [
        Opacity(
          opacity: 0,
          child: SizedBox(
            height: 1,
            child: EditableText(
              key: editableKey,
              controller: controller,
              focusNode: focusNode,
              readOnly: !enabled,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(PairingCubit.codeLength),
              ],
              autocorrect: false,
              enableSuggestions: false,
              showCursor: false,
              style: const TextStyle(color: Colors.transparent),
              cursorColor: Colors.transparent,
              backgroundCursorColor: Colors.transparent,
              onChanged: onChanged,
            ),
          ),
        ),
        Semantics(
          textField: true,
          label: 'Pairing code',
          value: code,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled
                ? () => editableKey.currentState?.requestKeyboard()
                : null,
            child: ExcludeSemantics(
              child: Row(
                children: [
                  for (var i = 0; i < PairingCubit.codeLength; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    Flexible(
                      child: ListenableBuilder(
                        listenable: focusNode,
                        builder: (context, _) => _CodeBox(
                          digit: i < code.length ? code[i] : null,
                          focused:
                              enabled && focusNode.hasFocus && i == activeIndex,
                          enabled: enabled,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({
    required this.digit,
    required this.focused,
    required this.enabled,
  });

  static const Size caretSize = Size(2, 28);

  final String? digit;
  final bool focused;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Opacity(
      opacity: enabled ? 1 : AppOpacity.disabled,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: focused ? colors.borderFocus : colors.borderDefault,
            width: focused ? _CodeInput.focusedBorder : 1,
          ),
          boxShadow: focused ? AppShadows.glowPrimary : null,
        ),
        child: SizedBox(
          width: _CodeInput.boxWidth,
          height: _CodeInput.boxHeight,
          child: Center(
            child: digit != null
                ? Text(
                    digit!,
                    style: AppTextStyles.headingXl.copyWith(
                      color: colors.textPrimary,
                    ),
                  )
                : focused
                ? const _Caret()
                : null,
          ),
        ),
      ),
    );
  }
}

class _Caret extends StatefulWidget {
  const _Caret();

  static const Duration blink = Duration(milliseconds: 500);

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _Caret.blink,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return FadeTransition(
      opacity: _controller,
      child: SizedBox.fromSize(
        size: _CodeBox.caretSize,
        child: ColoredBox(color: colors.primary),
      ),
    );
  }
}

class _LockNote extends StatelessWidget {
  const _LockNote();

  static const double iconSize = AppSpacing.md + AppSpacing.x3s;
  static const Size glyphSize = Size(8, 12.5);
  static const double glyphStroke = 1.5;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox.square(
          dimension: iconSize,
          child: Center(
            child: CustomPaint(
              size: glyphSize,
              painter: _PadlockPainter(
                color: colors.textTertiary,
                strokeWidth: glyphStroke,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs + AppSpacing.x3s),
        Expanded(
          child: Text(
            'Typing the code proves you are physically at the laptop. '
            'It is never sent to the cloud.',
            style: AppTextStyles.bodyS.copyWith(color: colors.textTertiary),
          ),
        ),
      ],
    );
  }
}

class _PadlockPainter extends CustomPainter {
  const _PadlockPainter({required this.color, required this.strokeWidth});

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
    final inset = strokeWidth / 2;
    final bodyTop = size.height * 0.45;
    final body = Rect.fromLTRB(
      inset,
      bodyTop,
      size.width - inset,
      size.height - inset,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, Radius.circular(strokeWidth)),
      paint,
    );
    final shackleInset = size.width * 0.2;
    final shackle = Rect.fromLTRB(
      shackleInset,
      inset,
      size.width - shackleInset,
      bodyTop + (bodyTop - inset),
    );
    final path = Path()
      ..moveTo(shackle.left, bodyTop)
      ..lineTo(shackle.left, shackle.center.dy)
      ..arcTo(
        Rect.fromLTWH(shackle.left, shackle.top, shackle.width, shackle.width),
        math.pi,
        math.pi,
        false,
      )
      ..lineTo(shackle.right, bodyTop);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PadlockPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}
