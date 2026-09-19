import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'pairing_state.dart';

class PairingCubit extends Cubit<PairingState> {
  PairingCubit({this.lifetime = defaultLifetime})
    : super(PairingEntering(code: '', secondsLeft: lifetime.inSeconds));

  static const Duration defaultLifetime = Duration(seconds: 60);
  static const int codeLength = 6;

  final Duration lifetime;
  Timer? _clock;
  DateTime? _deadline;

  bool get isComplete => state.code.length == codeLength;

  void start() {
    _clock?.cancel();
    _deadline = DateTime.now().add(lifetime);
    emit(PairingEntering(code: state.code, secondsLeft: lifetime.inSeconds));
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void updateCode(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final code = digits.length > codeLength
        ? digits.substring(0, codeLength)
        : digits;
    switch (state) {
      case PairingEntering(:final secondsLeft):
        emit(PairingEntering(code: code, secondsLeft: secondsLeft));
      case PairingExpired():
        break;
    }
  }

  void _tick() {
    switch (state) {
      case PairingEntering(:final code):
        final remaining = _deadline!.difference(DateTime.now());
        final secondsLeft = (remaining.inMilliseconds / 1000).ceil();
        if (secondsLeft <= 0) {
          _clock?.cancel();
          emit(PairingExpired(code: code));
        } else {
          emit(PairingEntering(code: code, secondsLeft: secondsLeft));
        }
      case PairingExpired():
        _clock?.cancel();
    }
  }

  @override
  Future<void> close() {
    _clock?.cancel();
    return super.close();
  }
}
