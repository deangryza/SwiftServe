const _months = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool isSameMessageDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String messageClockLabel(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '$hour:$minute $period';
}

String messageDateSeparatorLabel(DateTime value, {DateTime? now}) {
  final local = value.toLocal();
  final localNow = (now ?? DateTime.now()).toLocal();
  final difference = _dateOnly(localNow).difference(_dateOnly(local)).inDays;

  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  return '${_months[local.month - 1]} ${local.day}, ${local.year}';
}

String messageTimestampLabel(DateTime value, {DateTime? now}) {
  final date = messageDateSeparatorLabel(value, now: now);
  return '$date, ${messageClockLabel(value)}';
}
