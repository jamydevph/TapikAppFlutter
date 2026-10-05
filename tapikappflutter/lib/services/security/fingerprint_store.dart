import 'package:shared_preferences/shared_preferences.dart';

class FingerprintStore {
  const FingerprintStore._();

  static const String prefix = 'agent.fingerprint.';

  static String _keyFor(String agentId) => '$prefix$agentId';

  static Future<String?> load(String agentId) async {
    if (agentId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_keyFor(agentId));
    return stored == null || stored.isEmpty ? null : stored;
  }

  static Future<void> remember(String agentId, String fingerprint) async {
    if (agentId.isEmpty || fingerprint.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(agentId), fingerprint);
  }

  static Future<void> forget(String agentId) async {
    if (agentId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFor(agentId));
  }
}
