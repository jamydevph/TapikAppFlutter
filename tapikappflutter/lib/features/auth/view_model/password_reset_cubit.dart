import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failure.dart';
import '../../../data/repositories/auth_repository.dart';
import 'password_reset_state.dart';

class PasswordResetCubit extends Cubit<PasswordResetState> {
  PasswordResetCubit(this._repository) : super(const PasswordResetIdle());

  final AuthRepository _repository;

  Future<void> send(String email) async {
    emit(const PasswordResetSending());
    try {
      await _repository.sendPasswordReset(email);
      if (isClosed) return;
      emit(PasswordResetSent(email));
    } on AuthFailure catch (failure) {
      if (isClosed) return;
      emit(PasswordResetError(failure.message));
    }
  }
}
