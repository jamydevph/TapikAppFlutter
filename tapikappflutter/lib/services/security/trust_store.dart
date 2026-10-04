import 'package:shared_preferences/shared_preferences.dart';

class TrustStore {
  const TrustStore._();

  static const String key = 'agent.trusted.clients';

  static Future<Set<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(key) ?? const <String>[]).toSet();
  }

  static Future<void> remember(Set<String> clients) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, clients.toList());
  }
}
