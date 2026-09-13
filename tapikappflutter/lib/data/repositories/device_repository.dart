import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/error/failure.dart';
import '../models/device_model.dart';
import '../sources/firebase_auth_source.dart';
import '../sources/firestore_source.dart';

class DeviceRepository {
  DeviceRepository({FirebaseAuthSource? auth, FirestoreSource? firestore})
      : _auth = auth ?? FirebaseAuthSource(),
        _firestore = firestore ?? FirestoreSource();

  final FirebaseAuthSource _auth;
  final FirestoreSource _firestore;

  String _requireUid() {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthFailure('You need to be signed in.');
    }
    return user.uid;
  }

  Future<void> registerDevice(DeviceModel device) {
    return _guard(
      () => _firestore.setDevice(_requireUid(), device.id, device.toMap()),
    );
  }

  Future<void> touchLastSeen(String deviceId) {
    return _guard(() => _firestore.touchDevice(_requireUid(), deviceId));
  }

  Future<List<DeviceModel>> loadTrusted() {
    return _guard(() async {
      final snapshot = await _firestore.getDevices(_requireUid());
      return snapshot.docs
          .map((doc) => DeviceModel.fromFirestore(doc))
          .toList();
    });
  }

  Future<Set<String>> trustedFingerprints() async {
    final devices = await loadTrusted();
    return devices.map((device) => device.certFingerprint).toSet();
  }

  Stream<List<DeviceModel>> watchDevices() {
    return _firestore.watchDevices(_requireUid()).map(
          (snapshot) => snapshot.docs
              .map((doc) => DeviceModel.fromFirestore(doc))
              .toList(),
        );
  }

  Future<void> revokeDevice(String deviceId) {
    return _guard(() => _firestore.deleteDevice(_requireUid(), deviceId));
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on AuthFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw DataFailure(_messageForCode(error.code));
    } catch (_) {
      throw const DataFailure('Something went wrong. Please try again.');
    }
  }

  String _messageForCode(String code) {
    switch (code) {
      case 'permission-denied':
        return 'You do not have permission to access this data.';
      case 'unavailable':
        return 'The service is unavailable. Check your connection and try again.';
      case 'not-found':
        return 'That device could not be found.';
      case 'deadline-exceeded':
        return 'The request timed out. Please try again.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
