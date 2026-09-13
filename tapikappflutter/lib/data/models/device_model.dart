import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class DeviceModel extends Equatable {
  const DeviceModel({
    required this.id,
    required this.name,
    required this.platform,
    required this.certFingerprint,
    this.lastSeenAt,
    this.trustedAt,
  });

  final String id;
  final String name;
  final String platform;
  final String certFingerprint;
  final DateTime? lastSeenAt;
  final DateTime? trustedAt;

  factory DeviceModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return DeviceModel(
      id: doc.id,
      name: data['name'] as String? ?? '',
      platform: data['platform'] as String? ?? '',
      certFingerprint: data['certFingerprint'] as String? ?? '',
      lastSeenAt: (data['lastSeenAt'] as Timestamp?)?.toDate(),
      trustedAt: (data['trustedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'platform': platform,
      'certFingerprint': certFingerprint,
    };
  }

  @override
  List<Object?> get props => [id, name, platform, certFingerprint, lastSeenAt, trustedAt];
}
