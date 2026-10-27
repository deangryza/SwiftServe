import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Tests supply the platform implementation used by the geocoding plugin.
// ignore: depend_on_referenced_packages
import 'package:geocoding_platform_interface/geocoding_platform_interface.dart'
    as geocoding;
import 'package:my_app/features/client/presentation/screens/post_request_screen.dart';
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/widgets/job_location_picker.dart';

Future<void> pumpPostForm(WidgetTester tester) async {
  // Use a real font for the map attribution instead of fixed-width Ahem.
  await tester.runAsync(() async {
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
    final bytes = await File(
      '${artifacts.path}/material_fonts/roboto-regular.ttf',
    ).readAsBytes();
    await (FontLoader(
      'PostFormTestFont',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'PostFormTestFont'),
      home: PostRequestScreen(
        initialCategory: 'Cleaning',
        categoryNames: Stream.value(['Cleaning']),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    geocoding.GeocodingPlatformFactory.instance = _GeocodingFactory();
  });

  testWidgets('submit explains validation and reveals an off-screen error', (
    tester,
  ) async {
    await pumpPostForm(tester);
    final submit = find.byKey(const ValueKey('post-job-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(
      find.text('Please complete the highlighted fields.'),
      findsOneWidget,
    );
    expect(find.text('Enter a job title').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('location selection survives scrolling away and back', (
    tester,
  ) async {
    await pumpPostForm(tester);
    const selection = JobLocationSelection(
      position: JobCoordinate(latitude: 14.84, longitude: 120.81),
      exactAddress: '123 Example Street',
      areaLabel: 'Malolos',
    );
    final picker = find.byType(JobLocationPicker);
    await tester.ensureVisible(picker);
    tester.widget<JobLocationPicker>(picker).onChanged(selection);
    await tester.pump();

    final location = find.byKey(const ValueKey('post-job-location'));
    final original = tester.state<FormFieldState<JobLocationSelection>>(
      location,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('post-job-submit')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('post-job-title')));
    await tester.pump();
    await tester.ensureVisible(location);
    await tester.pump();

    final after = tester.state<FormFieldState<JobLocationSelection>>(location);
    expect(identical(original, after), isTrue);
    expect(after.value, same(selection));
    expect(after.validate(), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('completed fields let submission reach the schedule check', (
    tester,
  ) async {
    await pumpPostForm(tester);
    for (final entry in {
      'post-job-title': 'Clean the kitchen',
      'post-job-budget': '200',
      'post-job-description': 'Please clean the kitchen floor.',
    }.entries) {
      final field = find.byKey(ValueKey(entry.key));
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
    }
    tester.testTextInput.hide();
    final picker = find.byType(JobLocationPicker);
    tester
        .widget<JobLocationPicker>(picker)
        .onChanged(
          const JobLocationSelection(
            position: JobCoordinate(latitude: 14.84, longitude: 120.81),
            exactAddress: '123 Example Street',
            areaLabel: 'Malolos',
          ),
        );
    await tester.pumpAndSettle();
    final submit = find.byKey(const ValueKey('post-job-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text('Please choose both FROM and TO dates.'), findsOneWidget);
    expect(find.text('Please complete the highlighted fields.'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _GeocodingFactory extends geocoding.GeocodingPlatformFactory {
  @override
  geocoding.Geocoding createGeocoding(
    geocoding.GeocodingCreationParams params,
  ) => _Geocoding();
}

class _Geocoding extends Fake implements geocoding.Geocoding {}
