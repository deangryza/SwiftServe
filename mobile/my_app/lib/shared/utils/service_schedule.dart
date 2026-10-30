import 'package:flutter/material.dart' show TimeOfDay;

import '../models/service_request.dart';

/// SwiftServe's service locations use Philippine Standard Time (UTC+8).
/// These calendar components are independent of the viewing device's timezone.
DateTime serviceWallTime(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 8));

DateTime serviceCalendarDate(DateTime instant) {
  final wall = serviceWallTime(instant);
  return DateTime(wall.year, wall.month, wall.day);
}

DateTime serviceStartInstant(DateTime date, TimeOfDay time) => DateTime.utc(
  date.year,
  date.month,
  date.day,
  time.hour,
  time.minute,
).subtract(const Duration(hours: 8));

String serviceTimeLabel(TimeOfDay time) {
  final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
  return '$hour:${time.minute.toString().padLeft(2, '0')} '
      '${time.hour < 12 ? 'AM' : 'PM'}';
}

String? validateServiceSchedule({
  required DateTime? from,
  required DateTime? to,
  required TimeOfDay? time,
  required DateTime now,
}) {
  if (from == null || to == null) {
    return 'Please choose both FROM and TO dates.';
  }
  if (time == null) return 'Please choose a preferred start time.';
  final start = serviceStartInstant(from, time);
  if (serviceStartInstant(to, time).isBefore(start)) {
    return 'TO date must be on or after FROM date.';
  }
  if (!start.isAfter(now)) {
    return 'Choose a future service date and time (PHT).';
  }
  return null;
}

String serviceScheduleLabel(ServiceRequest request) {
  final start = request.scheduleFrom ?? request.schedule;
  if (start == null) return 'Flexible schedule';
  final from = serviceWallTime(start);
  final to = serviceWallTime(request.scheduleTo ?? start);
  String date(DateTime value) => '${value.month}/${value.day}/${value.year}';
  final sameDay =
      from.year == to.year && from.month == to.month && from.day == to.day;
  final dates = sameDay ? date(from) : '${date(from)} \u2013 ${date(to)}';
  final time = from.hour == 0 && from.minute == 0
      ? '12:00 AM / time not specified'
      : serviceTimeLabel(TimeOfDay(hour: from.hour, minute: from.minute));
  // Legacy date-only timestamps and explicitly chosen midnight are indistinguishable.
  return '$dates \u00b7 $time PHT';
}

/// A missing start or ambiguous legacy midnight must not be treated as an
/// explicitly scheduled expired request. Matches the backend cleanup policy.
bool serviceStartHasPassed(ServiceRequest request, {DateTime? now}) {
  final start = request.scheduleFrom;
  if (start == null) return false;
  final wall = serviceWallTime(start);
  if (wall.hour == 0 && wall.minute == 0) return false;
  return start.isBefore(now ?? DateTime.now());
}
