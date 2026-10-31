import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/client/presentation/screens/post_request_screen.dart';
import 'package:my_app/shared/models/service_request.dart';
import 'package:my_app/shared/utils/service_schedule.dart';

final futureDate = serviceCalendarDate(
  DateTime.now(),
).add(const Duration(days: 2));
ServiceRequest existing({
  TimeOfDay time = const TimeOfDay(hour: 15, minute: 20),
}) => ServiceRequest(
  id: 'job',
  clientId: 'client',
  clientName: 'Client',
  title: 'Online tutoring',
  category: 'Other',
  location: 'Online',
  description: 'Help with homework',
  budget: 200,
  status: ServiceRequestStatus.pending,
  modality: JobModality.online,
  scheduleFrom: serviceStartInstant(futureDate, time),
  scheduleTo: serviceStartInstant(futureDate, time),
);

Future<void> pumpForm(WidgetTester tester, {ServiceRequest? request}) async {
  // Ahem's fixed-width glyphs can overflow unrelated work-type controls.
  await tester.runAsync(() async {
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
    final bytes = await File(
      '${artifacts.path}/material_fonts/roboto-regular.ttf',
    ).readAsBytes();
    await (FontLoader(
      'ScheduleTestFont',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'ScheduleTestFont'),
      home: PostRequestScreen(
        existing: request ?? existing(),
        categoryNames: Stream.value(['Other']),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openPicker(WidgetTester tester, String key) async {
  final field = find.byKey(ValueKey(key));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('native date selections still require a time before submission', (
    tester,
  ) async {
    await pumpForm(
      tester,
      request: ServiceRequest.fromMap('job', {
        'title': 'Tutoring',
        'category': 'Other',
        'budget': 200,
        'description': 'Help with homework',
        'modality': 'online',
      }),
    );
    for (final key in ['post-job-from-date', 'post-job-to-date']) {
      await openPicker(tester, key);
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }
    final submit = find.byKey(const ValueKey('post-job-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Please choose a preferred start time.'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('date range shares a row with full-width time below at 320px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpForm(tester);
    final date = find.byKey(const ValueKey('post-job-from-date'));
    final to = find.byKey(const ValueKey('post-job-to-date'));
    final time = find.byKey(const ValueKey('post-job-time'));
    await tester.ensureVisible(time);
    await tester.pump();
    expect(tester.getTopLeft(date).dy, tester.getTopLeft(to).dy);
    expect(tester.getTopLeft(to).dx, greaterThan(tester.getTopLeft(date).dx));
    expect(
      tester.getTopLeft(time).dy,
      greaterThan(tester.getBottomLeft(date).dy),
    );
    expect(tester.getSize(time).width, greaterThan(tester.getSize(date).width));
    expect(find.text('3:20 PM'), findsOneWidget);
  });

  testWidgets(
    'native time picker selection updates the field, cancellation preserves it',
    (tester) async {
      await pumpForm(tester);
      await openPicker(tester, 'post-job-time');
      expect(find.byType(TimePickerDialog), findsOneWidget);
      // Switch the native picker to text entry and select a new hour/minute.
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final inputs = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(inputs.at(0), '4');
      await tester.enterText(inputs.at(1), '45');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('4:45 PM'), findsOneWidget);
      await openPicker(tester, 'post-job-time');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('4:45 PM'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changing FROM to today revalidates a past time without clearing it',
    (tester) async {
      await pumpForm(
        tester,
        request: existing(time: const TimeOfDay(hour: 0, minute: 0)),
      );
      await openPicker(tester, 'post-job-from-date');
      final today = serviceCalendarDate(DateTime.now());
      await tester.tap(find.text('${today.day}').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('12:00 AM'), findsOneWidget);
      expect(
        find.text('Choose a future service date and time (PHT).'),
        findsOneWidget,
      );
      await openPicker(tester, 'post-job-from-date');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose a future service date and time (PHT).'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
