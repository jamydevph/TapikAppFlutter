class RelativeTime {
  const RelativeTime._();

  static String ago(DateTime moment, {DateTime? now}) {
    final elapsed = (now ?? DateTime.now()).difference(moment);
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inHours < 1) return _plural(elapsed.inMinutes, 'minute');
    if (elapsed.inDays < 1) return _plural(elapsed.inHours, 'hour');
    if (elapsed.inDays < 7) return _plural(elapsed.inDays, 'day');
    if (elapsed.inDays < 30) return _plural(elapsed.inDays ~/ 7, 'week');
    if (elapsed.inDays < 365) {
      return _plural((elapsed.inDays ~/ 30).clamp(1, 11), 'month');
    }
    return _plural(elapsed.inDays ~/ 365, 'year');
  }

  static String _plural(int count, String unit) {
    return '$count $unit${count == 1 ? '' : 's'} ago';
  }
}
