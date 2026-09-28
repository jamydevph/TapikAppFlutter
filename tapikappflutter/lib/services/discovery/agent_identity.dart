import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class AgentIdentity {
  const AgentIdentity(this.id);

  static const String storageKey = 'agent.identity';
  static const int byteLength = 16;

  final String id;

  static Future<AgentIdentity> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(storageKey);
    if (stored != null && stored.isNotEmpty) return AgentIdentity(stored);
    final generated = _generate();
    await prefs.setString(storageKey, generated);
    return AgentIdentity(generated);
  }

  static String _generate() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < byteLength; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
