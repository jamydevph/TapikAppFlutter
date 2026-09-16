import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class DotsLoader extends StatefulWidget {
  const DotsLoader({
    super.key,
    this.dotCount = 3,
    this.dotSize = 7,
    this.gap = 10,
    this.interval = const Duration(milliseconds: 400),
  });

  final int dotCount;
  final double dotSize;
  final double gap;
  final Duration interval;

  @override
  State<DotsLoader> createState() => _DotsLoaderState();
}

class _DotsLoaderState extends State<DotsLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.interval * widget.dotCount,
  )..repeat();

  @override
  void didUpdateWidget(DotsLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.interval != oldWidget.interval || widget.dotCount != oldWidget.dotCount) {
      _controller
        ..duration = widget.interval * widget.dotCount
        ..repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      label: 'Loading',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final active = (_controller.value * widget.dotCount).floor() % widget.dotCount;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.dotCount; i++) ...[
                if (i > 0) SizedBox(width: widget.gap),
                _Dot(
                  size: widget.dotSize,
                  color: i == active ? colors.primary : colors.borderStrong,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
