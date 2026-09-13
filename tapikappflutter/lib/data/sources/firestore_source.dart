import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';

class FirestoreSource {
  FirestoreSource({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<void> writeUserProfile(UserModel user) {
    return _firestore.collection('users').doc(user.uid).set({
      'email': user.email,
      'displayName': user.displayName ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  CollectionReference<Map<String, dynamic>> _devices(String uid) {
    return _firestore.collection('users').doc(uid).collection('devices');
  }

  Future<void> setDevice(String uid, String deviceId, Map<String, dynamic> data) {
    return _devices(uid).doc(deviceId).set({
      ...data,
      'trustedAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> touchDevice(String uid, String deviceId) {
    return _devices(uid).doc(deviceId).update({
      'lastSeenAt': FieldValue.serverTimestamp(),
    });
  }

  Future<QuerySnapshot<Map<String, dynamic>>> getDevices(String uid) {
    return _devices(uid).get();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchDevices(String uid) {
    return _devices(uid).snapshots();
  }

  Future<void> deleteDevice(String uid, String deviceId) {
    return _devices(uid).doc(deviceId).delete();
  }
}
