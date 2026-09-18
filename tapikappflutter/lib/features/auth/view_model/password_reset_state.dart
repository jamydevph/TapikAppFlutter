import 'package:equatable/equatable.dart';

sealed class PasswordResetState extends Equatable {
  const PasswordResetState();

  @override
  List<Object?> get props => [];
}

class PasswordResetIdle extends PasswordResetState {
  const PasswordResetIdle();
}

class PasswordResetSending extends PasswordResetState {
  const PasswordResetSending();
}

class PasswordResetSent extends PasswordResetState {
  const PasswordResetSent(this.email);

  final String email;

  @override
  List<Object?> get props => [email];
}

class PasswordResetError extends PasswordResetState {
  const PasswordResetError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
