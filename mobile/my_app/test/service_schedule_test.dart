import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/models/service_request.dart';
import 'package:my_app/shared/utils/service_schedule.dart';

void main() {
  final today = DateTime(2026, 10, 29);
  final tomorrow = DateTime(2026, 10, 30);
  final now = DateTime.utc(2026, 10, 29, 6, 30); // 2:30 PM PHT.
  String? validate(DateTime? from, DateTime? to, TimeOfDay? time) =>
      validateServiceSchedule(from: from, to: to, time: time, now: now);

  test('requires both dates and a time', () {
    expect(validate(null, today, null), contains('FROM and TO'));
    expect(validate(today, null, null), contains('FROM and TO'));
    expect(validate(today, today, null), contains('start time'));
  });
  test('rejects past dates, past times today, and the current minute', () {
    expect(
      validate(
        DateTime(2026, 10, 28),
        today,
        const TimeOfDay(hour: 23, minute: 59),
      ),
      contains('future'),
    );
    for (final time in [
      const TimeOfDay(hour: 14, minute: 29),
      const TimeOfDay(hour: 14, minute: 30),
    ]) {
      expect(validate(today, today, time), contains('future'));
    }
    expect(
      validate(today, today, const TimeOfDay(hour: 14, minute: 31)),
      isNull,
    );
  });
  test('date changes revalidate the same time without resetting it', () {
    const time = TimeOfDay(hour: 9, minute: 15);
    expect(validate(tomorrow, tomorrow, time), isNull);
    expect(validate(today, tomorrow, time), contains('future'));
    expect(validate(tomorrow, today, time), contains('TO date'));
    expect(validate(tomorrow, tomorrow, time), isNull);
  });
  test(
    'future midnight is allowed and converts across UTC calendar boundary',
    () {
      const midnight = TimeOfDay(hour: 0, minute: 0);
      expect(validate(tomorrow, tomorrow, midnight), isNull);
      final instant = serviceStartInstant(tomorrow, midnight);
      expect(instant, DateTime.utc(2026, 10, 29, 16));
      expect(serviceCalendarDate(instant), tomorrow);
    },
  );
  test(
    'combined time survives Firestore timestamps and model deserialization',
    () {
      final instant = serviceStartInstant(
        tomorrow,
        const TimeOfDay(hour: 17, minute: 45),
      );
      final request = ServiceRequest.fromMap('job', {
        'schedule': Timestamp.fromDate(instant),
        'scheduleFrom': Timestamp.fromDate(instant),
        'scheduleTo': Timestamp.fromDate(instant),
      });
      expect(request.schedule!.isAtSameMomentAs(instant), isTrue);
      expect(request.scheduleFrom!.isAtSameMomentAs(instant), isTrue);
      expect(serviceScheduleLabel(request), '10/30/2026 \u00b7 5:45 PM PHT');
    },
  );
  test('legacy schedule-only midnight uses the approved ambiguous label', () {
    final request = ServiceRequest.fromMap('legacy', {
      'schedule': Timestamp.fromDate(DateTime.utc(2026, 10, 29, 16)),
    });
    expect(
      serviceScheduleLabel(request),
      '10/30/2026 \u00b7 12:00 AM / time not specified PHT',
    );
    expect(
      serviceScheduleLabel(ServiceRequest.fromMap('empty', {})),
      'Flexible schedule',
    );
  });
  test('date ranges include the preferred start time consistently in PHT', () {
    final request = ServiceRequest.fromMap('range', {
      'scheduleFrom': Timestamp.fromDate(DateTime.utc(2026, 10, 29, 1, 5)),
      'scheduleTo': Timestamp.fromDate(DateTime.utc(2026, 10, 31, 1, 5)),
    });
    expect(
      serviceScheduleLabel(request),
      '10/29/2026 \u2013 10/31/2026 \u00b7 9:05 AM PHT',
    );
    expect(serviceTimeLabel(const TimeOfDay(hour: 12, minute: 0)), '12:00 PM');
    expect(serviceTimeLabel(const TimeOfDay(hour: 0, minute: 7)), '12:07 AM');
  });
}
