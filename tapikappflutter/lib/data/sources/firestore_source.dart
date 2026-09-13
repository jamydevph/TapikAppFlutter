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
}
