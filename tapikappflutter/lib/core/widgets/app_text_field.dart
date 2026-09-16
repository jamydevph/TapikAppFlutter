import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hintText,
    this.helperText,
    this.errorText,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.obscureText = false,
    this.autocorrect = true,
    this.enabled = true,
  });

  static const double gap = AppSpacing.xs;

  final String label;
  final TextEditingController? controller;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final bool autocorrect;
  final bool enabled;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    super.dispose();
  }

  void _onFocusChange() => setState(() {});

  String? _validate(String? value) {
    return widget.validator?.call(widget.controller?.text ?? value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final decorationTheme = Theme.of(context).inputDecorationTheme;
    return FormField<String>(
      validator: _validate,
      enabled: widget.enabled,
      builder: (field) {
        final error = widget.errorText ?? field.errorText;
        final message = error ?? widget.helperText;
        final focused = _focusNode.hasFocus;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.label, style: decorationTheme.labelStyle),
            const SizedBox(height: AppTextField.gap),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: focused && error == null
                    ? AppShadows.glowPrimary
                    : null,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppComponentSizes.textFieldHeight,
                ),
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  enabled: widget.enabled,
                  obscureText: widget.obscureText,
                  autocorrect: widget.autocorrect,
                  enableSuggestions: !widget.obscureText,
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textInputAction,
                  autofillHints: widget.autofillHints,
                  style: AppTextStyles.bodyL.copyWith(
                    color: colors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    enabledBorder: error != null
                        ? decorationTheme.errorBorder
                        : null,
                    focusedBorder: error != null
                        ? decorationTheme.focusedErrorBorder
                        : null,
                  ),
                  onChanged: (value) {
                    field.didChange(value);
                    widget.onChanged?.call(value);
                  },
                  onSubmitted: widget.onSubmitted,
                ),
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: AppTextField.gap),
              Text(
                message,
                style: error != null
                    ? decorationTheme.errorStyle
                    : decorationTheme.helperStyle,
              ),
            ],
          ],
        );
      },
    );
  }
}
