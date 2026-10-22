import '../../../services/security/paired_phone.dart';

class PairedPhoneLabel {
  const PairedPhoneLabel._();

  static const String connectedNow = 'Connected now';
  static const String pairedEarlier = 'Phone paired earlier';
  static const String notSeenSinceUpdate = 'Not connected since this update';
  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static Map<String, String> titles(List<PairedPhone> phones, DateTime now) {
    final byDay = {for (final phone in phones) phone.id: _dayTitle(phone, now)};
    final days = <String, int>{};
    for (final title in byDay.values) {
      days[title] = (days[title] ?? 0) + 1;
    }
    final sharing = <String, List<String>>{};
    for (final phone in phones) {
      final title = byDay[phone.id]!;
      final paired = phone.pairedAt;
      final named = days[title]! > 1 && paired != null
          ? '$title, ${_time(paired)}'
          : title;
      (sharing[named] ??= <String>[]).add(phone.id);
    }
    final titles = <String, String>{};
    for (final MapEntry(key: title, value: ids) in sharing.entries) {
      ids.sort();
      for (var i = 0; i < ids.length; i++) {
        titles[ids[i]] = i == 0 ? title : '$title (${i + 1})';
      }
    }
    return titles;
  }

  static String status(
    PairedPhone phone, {
    required bool connected,
    required DateTime now,
  }) {
    if (connected) return connectedNow;
    final seen = phone.lastSeenAt;
    if (seen == null) return notSeenSinceUpdate;
    return 'Last connected ${_ago(seen, now)}';
  }

  static String _dayTitle(PairedPhone phone, DateTime now) {
    final paired = phone.pairedAt;
    if (paired == null) return pairedEarlier;
    return 'Phone paired ${_date(paired, now)}';
  }

  static String _ago(DateTime then, DateTime now) {
    final gap = now.difference(then);
    if (gap.inMinutes < 1) return 'just now';
    if (gap.inMinutes < 60) return '${gap.inMinutes} min ago';
    if (gap.inHours < 24) {
      return gap.inHours == 1 ? '1 hour ago' : '${gap.inHours} hours ago';
    }
    final days = _calendarDays(then, now);
    if (days <= 1) return 'yesterday';
    if (days < 7) return '$days days ago';
    return 'on ${_date(then, now)}';
  }

  static int _calendarDays(DateTime then, DateTime now) {
    final start = DateTime(then.year, then.month, then.day);
    final end = DateTime(now.year, now.month, now.day);
    return (end.difference(start).inHours / 24).round();
  }

  static String _date(DateTime day, DateTime now) {
    final date = '${day.day} ${_months[day.month - 1]}';
    return day.year == now.year ? date : '$date ${day.year}';
  }

  static String _time(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${time.hour < 12 ? 'AM' : 'PM'}';
  }
}
