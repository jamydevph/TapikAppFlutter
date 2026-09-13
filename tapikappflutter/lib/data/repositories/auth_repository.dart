import 'package:firebase_auth/firebase_auth.dart';

import '../../core/error/failure.dart';
import '../models/user_model.dart';
import '../sources/firebase_auth_source.dart';
import '../sources/firestore_source.dart';

class AuthRepository {
  AuthRepository({FirebaseAuthSource? source, FirestoreSource? firestore})
      : _source = source ?? FirebaseAuthSource(),
        _firestore = firestore ?? FirestoreSource();

  final FirebaseAuthSource _source;
  final FirestoreSource _firestore;

  Stream<UserModel?> authStateChanges() {
    return _source.authStateChanges().map(
          (user) => user == null ? null : UserModel.fromFirebaseUser(user),
        );
  }

  UserModel? get currentUser {
    final user = _source.currentUser;
    return user == null ? null : UserModel.fromFirebaseUser(user);
  }

  Future<UserModel> signUp({required String email, required String password}) {
    return _guard(() async {
      final user = UserModel.fromFirebaseUser(
        await _source.signUp(email: email, password: password),
      );
      await _firestore.writeUserProfile(user);
      return user;
    });
  }

  Future<UserModel> signIn({required String email, required String password}) {
    return _guard(
      () async => UserModel.fromFirebaseUser(
        await _source.signIn(email: email, password: password),
      ),
    );
  }

  Future<void> signOut() => _guard(_source.signOut);

  Future<void> sendPasswordReset(String email) =>
      _guard(() => _source.sendPasswordReset(email));

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_messageForCode(error.code));
    } catch (_) {
      throw const AuthFailure('Something went wrong. Please try again.');
    }
  }

  String _messageForCode(String code) {
    switch (code) {
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'weak-password':
        return 'That password is too weak (use at least 6 characters).';
      case 'operation-not-allowed':
        return 'Email and password sign-in is not enabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
