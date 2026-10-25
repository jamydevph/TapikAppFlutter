import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/error/failure.dart';
import 'paired_phone.dart';

class TrustStore {
  const TrustStore._();

  static const String key = 'agent.trusted.phones';
  static const String legacyKey = 'agent.trusted.clients';
  static const String historyKey = 'agent.trusted.history';
  static const String separator = ' ';

  static Future<Map<String, String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(legacyKey)) await prefs.remove(legacyKey);
    final clients = <String, String>{};
    for (final entry in prefs.getStringList(key) ?? const <String>[]) {
      final parts = entry.split(separator);
      if (parts.length != 2 || parts.any((part) => part.isEmpty)) continue;
      clients[parts.first] = parts.last;
    }
    return clients;
  }

  static Future<void> remember(Map<String, String> clients) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setStringList(key, [
      for (final client in clients.entries)
        [client.key, client.value].join(separator),
    ]);
    if (!saved) {
      throw const DataFailure(
        'Tapikapp could not save the paired phones. Try again.',
      );
    }
  }

  static Future<List<PairedPhone>> loadHistory() async {
    final List<String> entries;
    try {
      final prefs = await SharedPreferences.getInstance();
      entries = prefs.getStringList(historyKey) ?? const <String>[];
    } catch (_) {
      return const <PairedPhone>[];
    }
    final phones = <PairedPhone>[];
    for (final entry in entries) {
      try {
        final phone = PairedPhone.fromJson(jsonDecode(entry));
        if (phone != null) phones.add(phone);
      } catch (_) {
        continue;
      }
    }
    return phones;
  }

  static Future<void> rememberHistory(List<PairedPhone> phones) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(historyKey, [
      for (final phone in phones) jsonEncode(phone.toJson()),
    ]);
  }
}
