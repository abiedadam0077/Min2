import 'package:flutter/widgets.dart';

import '../i18n/i18n.dart';

String formatBytes(int? bytes) {
  if (bytes == null || bytes <= 0) {
    return '0 B';
  }
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String formatDuration(Duration duration) {
  final days = duration.inDays;
  final hours = duration.inHours % 24;
  final minutes = duration.inMinutes % 60;
  if (days > 0) {
    return '${days}d ${hours}h';
  }
  if (hours > 0) {
    return '${hours}h ${minutes}m';
  }
  return '${minutes}m';
}

String formatRelative(BuildContext context, DateTime? time) {
  if (time == null) {
    return context.tr('time.never');
  }
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) {
    return context.tr('time.justNow');
  }
  if (diff.inMinutes < 60) {
    return context.tr('time.minutesAgo', args: {'n': diff.inMinutes});
  }
  if (diff.inHours < 24) {
    return context.tr('time.hoursAgo', args: {'n': diff.inHours});
  }
  return context.tr('time.daysAgo', args: {'n': diff.inDays});
}

String formatDate(DateTime? time) {
  if (time == null) {
    return '-';
  }
  final local = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
