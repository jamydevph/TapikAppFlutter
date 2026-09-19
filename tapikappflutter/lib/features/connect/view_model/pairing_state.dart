import 'package:equatable/equatable.dart';

sealed class PairingState extends Equatable {
  const PairingState({required this.code});

  final String code;

  @override
  List<Object?> get props => [code];
}

class PairingEntering extends PairingState {
  const PairingEntering({required super.code, required this.secondsLeft});

  final int secondsLeft;

  @override
  List<Object?> get props => [code, secondsLeft];
}

class PairingExpired extends PairingState {
  const PairingExpired({required super.code});
}
