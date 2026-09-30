import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injection.dart';
import '../../../core/protocol/packet.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_slider.dart';
import '../../../core/widgets/connection_header.dart';
import '../../../services/input/pointer_pump.dart';
import '../../../services/transport/transport.dart';
import '../view_model/trackpad_cubit.dart';
import '../view_model/trackpad_state.dart';

class TrackpadPage extends StatelessWidget {
  const TrackpadPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AppProviders.trackpadCubit(context)..start(),
      child: const _TrackpadView(),
    );
  }
}

class _TrackpadView extends StatelessWidget {
  const _TrackpadView();

  static const double surfaceMinHeight = 200;
  static const double trackRowHeight = AppSpacing.lg;
  static const double sliderHitHeight = AppSpacing.x4l;
  static const double sliderLift = (sliderHitHeight - trackRowHeight) / 2;
  static const double bottomInset =
      AppSpacing.x4l + AppSpacing.xs - sliderLift * 2;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SafeArea(
      bottom: false,
      child: BlocBuilder<TrackpadCubit, TrackpadState>(
        builder: (context, state) {
          final connected = state.connection == TrackpadConnection.connected;
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xs + AppSpacing.x3s,
              AppSpacing.xl,
              bottomInset,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ConnectionHeader(
                            deviceName: state.deviceName,
                            status: switch (state.connection) {
                              TrackpadConnection.connected =>
                                ConnectionHeaderStatus.connected,
                              TrackpadConnection.connecting =>
                                ConnectionHeaderStatus.connecting,
                              TrackpadConnection.disconnected =>
                                ConnectionHeaderStatus.offline,
                            },
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Expanded(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minHeight: surfaceMinHeight,
                              ),
                              child: _GestureSurface(
                                enabled: connected,
                                sensitivity: state.sensitivity,
                                naturalScrolling: state.naturalScrolling,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: _ClickBar(
                                  label: 'Left click',
                                  enabled: connected,
                                  button: PointerButton.left,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: _ClickBar(
                                  label: 'Right click',
                                  enabled: connected,
                                  button: PointerButton.right,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(
                            height: AppSpacing.md + AppSpacing.x3s,
                          ),
                          Text(
                            'SENSITIVITY',
                            style: AppTextStyles.labelS.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                          Transform.translate(
                            offset: const Offset(0, -sliderLift),
                            child: SizedBox(
                              height: sliderHitHeight,
                              child: AppSlider(
                                value: state.sensitivity,
                                min: TrackpadCubit.minSensitivity,
                                max: TrackpadCubit.maxSensitivity,
                                label: 'Sensitivity',
                                semanticFormatter: (value) =>
                                    '${value.toStringAsFixed(1)}×',
                                onChanged: context
                                    .read<TrackpadCubit>()
                                    .setSensitivity,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _GestureSurface extends StatefulWidget {
  const _GestureSurface({
    required this.enabled,
    required this.sensitivity,
    required this.naturalScrolling,
  });

  static const double ringSize = AppSpacing.x3l + AppSpacing.x2s;
  static const double ringStroke = 1.5;
  static const double tapSlop = 14;
  static const Duration tapTimeout = Duration(milliseconds: 260);
  static const Duration holdDelay = Duration(milliseconds: 420);
  static const Duration staleFrame = Duration(milliseconds: 100);

  final bool enabled;
  final double sensitivity;
  final bool naturalScrolling;

  @override
  State<_GestureSurface> createState() => _GestureSurfaceState();
}

class _GestureSurfaceState extends State<_GestureSurface>
    with SingleTickerProviderStateMixin {
  final Map<int, Offset> _points = <int, Offset>{};

  late final Transport _transport = context.read<Transport>();
  late final PointerPump _pump = PointerPump(_transport);
  late final Ticker _ticker = createTicker(_onTick);

  Duration _lastTick = Duration.zero;
  Stopwatch? _stroke;
  Timer? _hold;
  double _travel = 0;
  int _maxFingers = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void deactivate() {
    _abandonStroke();
    super.deactivate();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _releaseDrag();
    _ticker.dispose();
    super.dispose();
  }

  void _abandonStroke() {
    _hold?.cancel();
    _hold = null;
    _releaseDrag();
    _points.clear();
    _stroke = null;
    _maxFingers = 0;
    _travel = 0;
    _pump.reset();
  }

  void _onTick(Duration elapsed) {
    final frame = _lastTick == Duration.zero
        ? PointerPump.nominalFrame
        : elapsed - _lastTick;
    _lastTick = elapsed;
    if (frame > _GestureSurface.staleFrame) {
      _pump.reset();
      return;
    }
    if (!widget.enabled) {
      _abandonStroke();
      return;
    }
    _pump.sensitivity = widget.sensitivity;
    _pump.naturalScrolling = widget.naturalScrolling;
    _pump.flush(frame);
  }

  void _onDown(PointerDownEvent event) {
    _points[event.pointer] = event.position;
    _maxFingers = math.max(_maxFingers, _points.length);
    if (_points.length > 1) {
      _hold?.cancel();
      _hold = null;
      return;
    }
    _stroke = Stopwatch()..start();
    _travel = 0;
    _hold = Timer(_GestureSurface.holdDelay, _startDrag);
  }

  void _onMove(PointerMoveEvent event) {
    final last = _points[event.pointer];
    if (last == null) return;
    _points[event.pointer] = event.position;
    final delta = event.position - last;
    _travel += delta.distance;
    if (_travel > _GestureSurface.tapSlop) {
      _hold?.cancel();
      _hold = null;
    }
    if (!widget.enabled) return;
    if (_maxFingers > 1) {
      final share = _points.length;
      _pump.addScroll(delta.dx / share, delta.dy / share);
      return;
    }
    _pump.addMove(delta.dx, delta.dy);
  }

  void _onRelease(PointerEvent event) {
    _points.remove(event.pointer);
    if (_points.isNotEmpty) return;
    _hold?.cancel();
    _hold = null;
    final held = _stroke?.elapsed ?? Duration.zero;
    final fingers = _maxFingers;
    final travel = _travel;
    _stroke = null;
    _maxFingers = 0;
    _travel = 0;
    if (_dragging) {
      _releaseDrag();
      return;
    }
    if (!widget.enabled) return;
    if (travel > _GestureSurface.tapSlop || held > _GestureSurface.tapTimeout) {
      return;
    }
    _click(fingers > 1 ? PointerButton.right : PointerButton.left);
  }

  void _startDrag() {
    _hold = null;
    if (!widget.enabled ||
        _dragging ||
        _points.length != 1 ||
        _travel > _GestureSurface.tapSlop) {
      return;
    }
    _dragging = true;
    _transport.send(const ButtonPacket(button: PointerButton.left, down: true));
  }

  void _releaseDrag() {
    if (!_dragging) return;
    _dragging = false;
    _transport.send(
      const ButtonPacket(button: PointerButton.left, down: false),
    );
  }

  void _click(PointerButton button) {
    _transport.send(ButtonPacket(button: button, down: true));
    _transport.send(ButtonPacket(button: button, down: false));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) {},
      onHorizontalDragStart: (_) {},
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onRelease,
        onPointerCancel: _onRelease,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: colors.borderDefault),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.borderStrong,
                      width: _GestureSurface.ringStroke,
                    ),
                  ),
                  child: const SizedBox.square(
                    dimension: _GestureSurface.ringSize,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Drag to move · Tap to click',
                  style: AppTextStyles.bodyS.copyWith(
                    color: colors.textTertiary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.x2s + AppSpacing.x3s),
                Text(
                  'Two fingers to scroll · Hold to drag',
                  style: AppTextStyles.caption.copyWith(
                    color: colors.textTertiary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClickBar extends StatelessWidget {
  const _ClickBar({
    required this.label,
    required this.enabled,
    required this.button,
  });

  static const double height = AppComponentSizes.buttonHeight;

  final String label;
  final bool enabled;
  final PointerButton button;

  void _click(BuildContext context) {
    final transport = context.read<Transport>();
    transport.send(ButtonPacket(button: button, down: true));
    transport.send(ButtonPacket(button: button, down: false));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Opacity(
      opacity: enabled ? 1 : AppOpacity.disabled,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: colors.borderDefault),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () => _click(context) : null,
          child: SizedBox(
            height: height,
            child: Center(
              child: Text(
                label,
                style: AppTextStyles.labelM.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
