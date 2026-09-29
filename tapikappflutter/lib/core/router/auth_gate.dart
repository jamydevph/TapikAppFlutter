import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/sources/local_prefs_source.dart';
import 'app_routes.dart';

class AuthGate extends ChangeNotifier {
  AuthGate({
    required AuthRepository repository,
    required LocalPrefsSource prefs,
    required bool loggedIn,
    Duration settleWindow = defaultSettleWindow,
  }) : this._(repository, prefs, loggedIn, settleWindow);

  AuthGate._(
    AuthRepository repository,
    this._prefs,
    this._flag,
    Duration settleWindow,
  ) {
    _session = repository.authStateChanges().listen(_onUser, onError: _onError);
    _settleTimer = Timer(settleWindow, _onSettled);
  }

  static const Duration defaultSettleWindow = Duration(milliseconds: 1200);

  static const Set<String> publicRoutes = {
    AppRoutes.login,
    AppRoutes.signup,
    AppRoutes.forgotPassword,
  };

  final LocalPrefsSource _prefs;

  StreamSubscription<UserModel?>? _session;
  Timer? _settleTimer;
  bool _flag;
  bool? _signedIn;
  UserModel? _user;
  bool _settled = false;
  bool _disposed = false;

  bool get isAuthenticated => _signedIn ?? _flag;

  String get initialRoute =>
      isAuthenticated ? AppRoutes.connect : AppRoutes.login;

  String? redirect(BuildContext context, GoRouterState state) {
    final location = state.matchedLocation;
    if (location == AppRoutes.splash) return null;
    final isPublic = publicRoutes.contains(location);
    if (!isAuthenticated) return isPublic ? null : AppRoutes.login;
    return isPublic ? AppRoutes.connect : null;
  }

  void _onUser(UserModel? user) {
    _user = user;
    if (user != null) {
      _settleTimer?.cancel();
      _settleTimer = null;
      _settled = true;
    }
    _reconcile();
  }

  void _onError(Object error) {
    _settled = true;
    _reconcile();
  }

  void _onSettled() {
    _settleTimer = null;
    _settled = true;
    _reconcile();
  }

  void _reconcile() {
    if (_disposed) return;
    final resolved = !_settled && _user == null ? null : _user != null;
    if (resolved == _signedIn) return;
    _signedIn = resolved;
    if (resolved != null && resolved != _flag) {
      _flag = resolved;
      unawaited(_prefs.setLoggedIn(resolved));
    }
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _settleTimer?.cancel();
    unawaited(_session?.cancel());
    super.dispose();
  }
}
