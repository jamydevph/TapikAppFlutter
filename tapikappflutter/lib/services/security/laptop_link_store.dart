import 'package:shared_preferences/shared_preferences.dart';

import 'reconnect_secret.dart';

class LaptopLink {
  const LaptopLink({required this.clientId, this.secret});

  final String clientId;
  final String? secret;
}

class LaptopLinkStore {
  const LaptopLinkStore._();

  static const String idPrefix = 'agent.link.id.';
  static const String secretPrefix = 'agent.link.secret.';
  static const String legacyIdentityKey = 'controller.identity';

  static Future<LaptopLink> forDial(
    String agentId, {
    required bool pinned,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(legacyIdentityKey)) {
      await prefs.remove(legacyIdentityKey);
    }
    final stored = prefs.getString('$idPrefix$agentId');
    if (pinned && stored != null && stored.isNotEmpty) {
      return LaptopLink(
        clientId: stored,
        secret: prefs.getString('$secretPrefix$agentId'),
      );
    }
    final fresh = ReconnectSecret.newClientId();
    await prefs.remove('$secretPrefix$agentId');
    await prefs.setString('$idPrefix$agentId', fresh);
    return LaptopLink(clientId: fresh);
  }

  static Future<void> rememberSecret(
    String agentId, {
    required String clientId,
    required String secret,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('$idPrefix$agentId') != clientId) return;
    await prefs.setString('$secretPrefix$agentId', secret);
  }

  static Future<void> forget(String agentId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$secretPrefix$agentId');
    await prefs.remove('$idPrefix$agentId');
  }
}
