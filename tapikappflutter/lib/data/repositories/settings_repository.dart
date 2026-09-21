import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/error/failure.dart';
import '../models/settings_model.dart';
import '../sources/firebase_auth_source.dart';
import '../sources/firestore_source.dart';

class SettingsRepository {
  SettingsRepository({
    FirebaseAuthSource? auth,
    FirestoreSource? firestore,
    this.debounce = const Duration(milliseconds: 500),
    this.flushTimeout = const Duration(seconds: 5),
  })  : _auth = auth ?? FirebaseAuthSource(),
        _firestore = firestore ?? FirestoreSource();

  final FirebaseAuthSource _auth;
  final FirestoreSource _firestore;
  final Duration debounce;
  final Duration flushTimeout;

  final StreamController<SettingsModel> _changes =
      StreamController<SettingsModel>.broadcast();
  final StreamController<Failure> _saveFailures =
      StreamController<Failure>.broadcast();
  final Map<String, dynamic> _pending = <String, dynamic>{};
  final Map<String, int> _pendingStamps = <String, int>{};

  SettingsModel _current = SettingsModel.defaults;
  bool _loaded = false;
  String? _uid;
  Timer? _debounceTimer;
  int _generation = 0;
  Future<void>? _inFlight;
  int _inFlightGeneration = -1;

  SettingsModel get current => _current;

  bool get loaded => _loaded;

  bool get hasPendingWrite => _pending.isNotEmpty;

  Stream<Failure> get saveFailures => _saveFailures.stream;

  String _requireUid() {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthFailure('You need to be signed in.');
    }
    if (_uid != user.uid) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _pending.clear();
      _pendingStamps.clear();
      _current = SettingsModel.defaults;
      _loaded = false;
      _uid = user.uid;
    }
    return user.uid;
  }

  Future<SettingsModel> load() {
    return _guard(() async {
      final snapshot = await _firestore.getSettings(_requireUid());
      _adoptRemote(SettingsModel.fromFirestore(snapshot));
      return _current;
    });
  }

  Stream<SettingsModel> watch() {
    late final StreamController<SettingsModel> controller;
    StreamSubscription<SettingsModel>? local;
    StreamSubscription<SettingsModel>? remote;

    controller = StreamController<SettingsModel>(
      onListen: () {
        final String uid;
        try {
          uid = _requireUid();
        } on AuthFailure catch (failure) {
          controller.addError(failure);
          controller.close();
          return;
        }
        controller.add(_current);
        local = _changes.stream.listen(controller.add);
        remote = _firestore
            .watchSettings(uid)
            .map(SettingsModel.fromFirestore)
            .listen(
              _adoptRemote,
              onError: (Object error) => controller.addError(_toFailure(error)),
            );
      },
      onCancel: () async {
        await local?.cancel();
        await remote?.cancel();
      },
    );
    return controller.stream;
  }

  void update(SettingsModel settings) {
    _requireUid();
    final next = settings.toMap();
    final previous = _current.toMap();
    final diff = <String, dynamic>{
      for (final entry in next.entries)
        if (entry.value != previous[entry.key]) entry.key: entry.value,
    };
    if (diff.isEmpty) {
      return;
    }
    _pending.addAll(diff);
    _current = settings;
    _generation++;
    for (final key in diff.keys) {
      _pendingStamps[key] = _generation;
    }
    _emit(settings);
    _scheduleFlush();
  }

  Future<void> flush() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    final uid = _uid;
    if (_pending.isEmpty || uid == null) {
      return Future<void>.value();
    }
    final inFlight = _inFlight;
    if (inFlight != null && _inFlightGeneration == _generation) {
      return inFlight;
    }
    final generation = _generation;
    final data = Map<String, dynamic>.of(_pending);
    final stamps = Map<String, int>.of(_pendingStamps);
    final future = _guard(() async {
      if (_auth.currentUser?.uid != uid) {
        throw const AuthFailure('You need to be signed in.');
      }
      await _write(uid, data);
      if (_uid != uid) {
        return;
      }
      for (final key in data.keys) {
        if (_pendingStamps[key] == stamps[key]) {
          _pending.remove(key);
          _pendingStamps.remove(key);
        }
      }
    }).whenComplete(() {
      if (_inFlightGeneration == generation) {
        _inFlight = null;
        _inFlightGeneration = -1;
      }
    });
    _inFlight = future;
    _inFlightGeneration = generation;
    return future;
  }

  Future<void> dispose() async {
    unawaited(flush().catchError((Object _) {}));
    await _changes.close();
    await _saveFailures.close();
  }

  Future<void> _write(String uid, Map<String, dynamic> data) async {
    var timedOut = false;
    final write = _firestore.setSettings(uid, data);
    unawaited(
      write.catchError((Object error) {
        if (timedOut && !_saveFailures.isClosed) {
          _saveFailures.add(_toFailure(error));
        }
      }),
    );
    await write.timeout(flushTimeout, onTimeout: () {
      timedOut = true;
    });
  }

  void _adoptRemote(SettingsModel remote) {
    final merged = SettingsModel.fromMap({...remote.toMap(), ..._pending});
    final firstLoad = !_loaded;
    _loaded = true;
    if (merged == _current && !firstLoad) {
      return;
    }
    _current = merged;
    _emit(merged);
  }

  void _emit(SettingsModel settings) {
    if (!_changes.isClosed) {
      _changes.add(settings);
    }
  }

  void _scheduleFlush() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      _debounceTimer = null;
      unawaited(
        flush().catchError((Object error) {
          if (error is Failure && !_saveFailures.isClosed) {
            _saveFailures.add(error);
          }
        }),
      );
    });
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on AuthFailure {
      rethrow;
    } catch (error) {
      throw _toFailure(error);
    }
  }

  Failure _toFailure(Object error) {
    if (error is Failure) {
      return error;
    }
    if (error is FirebaseException) {
      return DataFailure(_messageForCode(error.code));
    }
    return const DataFailure('Something went wrong. Please try again.');
  }

  String _messageForCode(String code) {
    switch (code) {
      case 'permission-denied':
        return 'You do not have permission to access this data.';
      case 'unavailable':
        return 'The service is unavailable. Check your connection and try again.';
      case 'deadline-exceeded':
        return 'The request timed out. Please try again.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
