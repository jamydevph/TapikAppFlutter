import 'package:shared_preferences/shared_preferences.dart';

import '../../core/error/failure.dart';

class TrustStore {
  const TrustStore._();

  static const String key = 'agent.trusted.clients';

  static Future<Set<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(key) ?? const <String>[]).toSet();
  }

  static Future<void> remember(Set<String> clients) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setStringList(key, clients.toList());
    if (!saved) {
      throw const DataFailure(
        'Tapikapp could not save the paired phones. Try again.',
      );
    }
  }
}
