import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

enum AppThemeMode { light, dark, system }

class SettingsModel extends Equatable {
  const SettingsModel({
    this.sensitivity = defaultSensitivity,
    this.naturalScrolling = true,
    this.hapticFeedback = true,
    this.themeMode = AppThemeMode.system,
  });

  static const double minSensitivity = 0.5;
  static const double maxSensitivity = 3.0;
  static const double defaultSensitivity = 1.0;
  static const SettingsModel defaults = SettingsModel();

  final double sensitivity;
  final bool naturalScrolling;
  final bool hapticFeedback;
  final AppThemeMode themeMode;

  factory SettingsModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return SettingsModel.fromMap(doc.data() ?? const <String, dynamic>{});
  }

  factory SettingsModel.fromMap(Map<String, dynamic> data) {
    return SettingsModel(
      sensitivity: _clampSensitivity(
        (data['sensitivity'] as num?)?.toDouble() ?? defaultSensitivity,
      ),
      naturalScrolling: data['naturalScrolling'] as bool? ?? true,
      hapticFeedback: data['hapticFeedback'] as bool? ?? true,
      themeMode: _themeModeFrom(data['themeMode'] as String?),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sensitivity': sensitivity,
      'naturalScrolling': naturalScrolling,
      'hapticFeedback': hapticFeedback,
      'themeMode': themeMode.name,
    };
  }

  SettingsModel copyWith({
    double? sensitivity,
    bool? naturalScrolling,
    bool? hapticFeedback,
    AppThemeMode? themeMode,
  }) {
    return SettingsModel(
      sensitivity: _clampSensitivity(sensitivity ?? this.sensitivity),
      naturalScrolling: naturalScrolling ?? this.naturalScrolling,
      hapticFeedback: hapticFeedback ?? this.hapticFeedback,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  static double _clampSensitivity(double value) {
    return value.clamp(minSensitivity, maxSensitivity).toDouble();
  }

  static AppThemeMode _themeModeFrom(String? value) {
    return AppThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => AppThemeMode.system,
    );
  }

  @override
  List<Object?> get props => [sensitivity, naturalScrolling, hapticFeedback, themeMode];
}
