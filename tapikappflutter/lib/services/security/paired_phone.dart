import 'package:equatable/equatable.dart';

class PairedPhone extends Equatable {
  const PairedPhone({required this.id, this.pairedAt, this.lastSeenAt});

  final String id;
  final DateTime? pairedAt;
  final DateTime? lastSeenAt;

  PairedPhone seenAt(DateTime time) {
    return PairedPhone(id: id, pairedAt: pairedAt, lastSeenAt: time);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    if (pairedAt case final paired?) 'paired': paired.millisecondsSinceEpoch,
    if (lastSeenAt case final seen?) 'seen': seen.millisecondsSinceEpoch,
  };

  static PairedPhone? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return PairedPhone(
      id: id,
      pairedAt: _time(json['paired']),
      lastSeenAt: _time(json['seen']),
    );
  }

  static const int _maxMilliseconds = 8640000000000000;

  static DateTime? _time(Object? value) {
    if (value is! int) return null;
    if (value < -_maxMilliseconds || value > _maxMilliseconds) return null;
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  @override
  List<Object?> get props => [id, pairedAt, lastSeenAt];
}
