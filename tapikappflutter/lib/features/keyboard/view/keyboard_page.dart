import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/connection_header.dart';
import '../../../core/widgets/key_cap.dart';
import '../view_model/keyboard_cubit.dart';
import '../view_model/keyboard_state.dart';

class KeyboardPage extends StatelessWidget {
  const KeyboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => KeyboardCubit(),
      child: const _KeyboardView(),
    );
  }
}

class _KeyboardView extends StatefulWidget {
  const _KeyboardView();

  static const double inputHeight = AppSpacing.x4l;
  static const double keyGap = 5;
  static const double rowGap = 6;
  static const double rowInset = AppSpacing.x2s;
  static const double halfKeyInset = 17;
  static const String hint =
      'Modifiers stay held until tapped again. '
      'All keys are released if the connection drops.';

  @override
  State<_KeyboardView> createState() => _KeyboardViewState();
}

class _KeyboardViewState extends State<_KeyboardView> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SafeArea(
      bottom: false,
      child: BlocBuilder<KeyboardCubit, KeyboardState>(
        builder: (context, state) {
          final cubit = context.read<KeyboardCubit>();
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              0,
              AppSpacing.xs + AppSpacing.x3s,
              0,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ConnectionHeader(
                        deviceName: state.deviceName,
                        status: switch (state.connection) {
                          KeyboardConnection.connected =>
                            ConnectionHeaderStatus.connected,
                          KeyboardConnection.connecting =>
                            ConnectionHeaderStatus.connecting,
                          KeyboardConnection.disconnected =>
                            ConnectionHeaderStatus.offline,
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SizedBox(
                        height: _KeyboardView.inputHeight,
                        child: TextField(
                          controller: _text,
                          style: AppTextStyles.bodyL.copyWith(
                            color: colors.textPrimary,
                          ),
                          textInputAction: TextInputAction.send,
                          decoration: const InputDecoration(
                            hintText: 'Type here to send text…',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.sm,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _ShortcutRow(
                        children: [
                          for (final modifier in KeyModifier.values)
                            KeyCap(
                              label: _modifierLabel(modifier),
                              icon: _ModifierGlyph(modifier),
                              type: KeyCapType.modifier,
                              active: state.isHeld(modifier),
                              onTap: () => cubit.toggleModifier(modifier),
                            ),
                          const KeyCap(label: 'esc', type: KeyCapType.modifier),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const _ShortcutRow(
                        children: [
                          KeyCap(
                            label: 'Previous track',
                            icon: Icon(Icons.skip_previous_rounded),
                            type: KeyCapType.modifier,
                          ),
                          KeyCap(
                            label: 'Play or pause',
                            icon: Icon(Icons.play_arrow_rounded),
                            type: KeyCapType.modifier,
                          ),
                          KeyCap(
                            label: 'Next track',
                            icon: Icon(Icons.skip_next_rounded),
                            type: KeyCapType.modifier,
                          ),
                          KeyCap(
                            label: 'Volume down',
                            icon: Icon(Icons.volume_down_rounded),
                            type: KeyCapType.modifier,
                          ),
                          KeyCap(
                            label: 'Volume up',
                            icon: Icon(Icons.volume_up_rounded),
                            type: KeyCapType.modifier,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl + AppSpacing.x2s),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _KeyboardView.rowInset,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _LetterRow(letters: 'QWERTYUIOP'),
                      const SizedBox(height: _KeyboardView.rowGap),
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: _KeyboardView.halfKeyInset,
                        ),
                        child: _LetterRow(letters: 'ASDFGHJKL'),
                      ),
                      const SizedBox(height: _KeyboardView.rowGap),
                      _LetterRow(
                        letters: 'ZXCVBNM',
                        leading: KeyCap(
                          label: _modifierLabel(KeyModifier.shift),
                          icon: const _ModifierGlyph(KeyModifier.shift),
                          type: KeyCapType.modifier,
                          active: state.isHeld(KeyModifier.shift),
                          onTap: () => cubit.toggleModifier(KeyModifier.shift),
                        ),
                        trailing: const KeyCap(
                          label: 'Delete',
                          icon: Icon(Icons.backspace_outlined),
                          type: KeyCapType.accent,
                        ),
                      ),
                      const SizedBox(height: _KeyboardView.rowGap),
                      const _KeyRow(
                        gap: _KeyboardView.keyGap,
                        children: [
                          KeyCap(label: '123', type: KeyCapType.modifier),
                          KeyCap(
                            label: 'Switch layout',
                            icon: Icon(Icons.language_rounded),
                            type: KeyCapType.modifier,
                          ),
                          Expanded(
                            child: KeyCap(
                              label: 'space',
                              type: KeyCapType.wide,
                              width: double.infinity,
                            ),
                          ),
                          KeyCap(label: '.', type: KeyCapType.modifier),
                          KeyCap(
                            label: 'Return',
                            icon: Icon(Icons.keyboard_return_rounded),
                            type: KeyCapType.accent,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md + AppSpacing.x3s),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: Text(
                    _KeyboardView.hint,
                    style: AppTextStyles.caption.copyWith(
                      color: colors.textTertiary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _modifierLabel(KeyModifier modifier) {
    return switch (modifier) {
      KeyModifier.command => 'Command',
      KeyModifier.option => 'Option',
      KeyModifier.shift => 'Shift',
      KeyModifier.control => 'Control',
    };
  }
}

class _ModifierGlyph extends StatelessWidget {
  const _ModifierGlyph(this.modifier);

  final KeyModifier modifier;

  @override
  Widget build(BuildContext context) {
    return switch (modifier) {
      KeyModifier.command => const Icon(Icons.keyboard_command_key),
      KeyModifier.option => const Icon(Icons.keyboard_option_key),
      KeyModifier.control => const Icon(Icons.keyboard_control_key),
      KeyModifier.shift => const _ShiftGlyph(),
    };
  }
}

class _ShiftGlyph extends StatelessWidget {
  const _ShiftGlyph();

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = theme.size ?? KeyCap.iconSize;
    return CustomPaint(
      size: Size.square(size),
      painter: _ShiftPainter(
        color: theme.color ?? AppColors.of(context).textPrimary,
      ),
    );
  }
}

class _ShiftPainter extends CustomPainter {
  const _ShiftPainter({required this.color});

  static const double strokeWidth = 1.75;

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 20;
    final path = Path()
      ..moveTo(10 * unit, 2.5 * unit)
      ..lineTo(17.5 * unit, 10 * unit)
      ..lineTo(13.25 * unit, 10 * unit)
      ..lineTo(13.25 * unit, 17.5 * unit)
      ..lineTo(6.75 * unit, 17.5 * unit)
      ..lineTo(6.75 * unit, 10 * unit)
      ..lineTo(2.5 * unit, 10 * unit)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * unit
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ShiftPainter oldDelegate) => oldDelegate.color != color;
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: _KeyRow(gap: AppSpacing.xs, children: children),
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.gap, required this.children});

  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          children[i],
        ],
      ],
    );
  }
}

class _LetterRow extends StatelessWidget {
  const _LetterRow({required this.letters, this.leading, this.trailing});

  final String letters;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return _KeyRow(
      gap: _KeyboardView.keyGap,
      children: [
        ?leading,
        for (final letter in letters.split(''))
          Expanded(
            child: KeyCap(label: letter, width: double.infinity),
          ),
        ?trailing,
      ],
    );
  }
}
