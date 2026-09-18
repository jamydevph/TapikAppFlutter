import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failure.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/sources/local_prefs_source.dart';
import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  AuthCubit({AuthRepository? repository, LocalPrefsSource? prefs})
      : _repository = repository ?? AuthRepository(),
        _prefs = prefs ?? LocalPrefsSource(),
        super(const AuthInitial());

  static const int minPasswordLength = AuthRepository.minPasswordLength;

  final AuthRepository _repository;
  final LocalPrefsSource _prefs;

  Future<void> signIn({required String email, required String password}) async {
    emit(const AuthLoading());
    try {
      final user = await _repository.signIn(email: email, password: password);
      await _prefs.setLoggedIn(true);
      emit(Authenticated(user));
    } on AuthFailure catch (failure) {
      emit(AuthError(failure.message));
    }
  }

  Future<void> signUp({required String email, required String password}) async {
    emit(const AuthLoading());
    try {
      final user = await _repository.signUp(email: email, password: password);
      await _prefs.setLoggedIn(true);
      emit(Authenticated(user));
    } on AuthFailure catch (failure) {
      emit(AuthError(failure.message));
    }
  }

  Future<void> signOut() async {
    try {
      await _repository.signOut();
      await _prefs.setLoggedIn(false);
      emit(const Unauthenticated());
    } on AuthFailure catch (failure) {
      emit(AuthError(failure.message));
    }
  }
}
