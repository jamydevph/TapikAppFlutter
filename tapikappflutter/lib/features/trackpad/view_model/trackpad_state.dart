import 'package:equatable/equatable.dart';

enum TrackpadConnection { disconnected, connecting, connected }

class TrackpadState extends Equatable {
  const TrackpadState({
    this.connection = TrackpadConnection.disconnected,
    this.deviceName,
    this.sensitivity = 1.0,
    this.naturalScrolling = true,
  });

  final TrackpadConnection connection;
  final String? deviceName;
  final double sensitivity;
  final bool naturalScrolling;

  TrackpadState copyWith({
    TrackpadConnection? connection,
    String? deviceName,
    double? sensitivity,
    bool? naturalScrolling,
  }) {
    return TrackpadState(
      connection: connection ?? this.connection,
      deviceName: deviceName ?? this.deviceName,
      sensitivity: sensitivity ?? this.sensitivity,
      naturalScrolling: naturalScrolling ?? this.naturalScrolling,
    );
  }

  @override
  List<Object?> get props => [
    connection,
    deviceName,
    sensitivity,
    naturalScrolling,
  ];
}
