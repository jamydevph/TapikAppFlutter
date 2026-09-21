import 'package:equatable/equatable.dart';

enum PresenterConnection { disconnected, connecting, connected }

class PresenterState extends Equatable {
  const PresenterState({
    this.connection = PresenterConnection.disconnected,
    this.deviceName,
    this.screenBlanked = false,
  });

  final PresenterConnection connection;
  final String? deviceName;
  final bool screenBlanked;

  PresenterState copyWith({
    PresenterConnection? connection,
    String? deviceName,
    bool? screenBlanked,
  }) {
    return PresenterState(
      connection: connection ?? this.connection,
      deviceName: deviceName ?? this.deviceName,
      screenBlanked: screenBlanked ?? this.screenBlanked,
    );
  }

  @override
  List<Object?> get props => [connection, deviceName, screenBlanked];
}
