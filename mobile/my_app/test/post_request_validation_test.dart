import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Tests supply the platform implementation used by the geocoding plugin.
// ignore: depend_on_referenced_packages
import 'package:geocoding_platform_interface/geocoding_platform_interface.dart'
    as geocoding;
import 'package:my_app/features/client/presentation/screens/post_request_screen.dart';
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/theme/app_theme.dart';
import 'package:my_app/shared/utils/errand_location_validation.dart';
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
    await (FontLoader(
      'Roboto',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    final icons = await File(
      '${artifacts.path}/material_fonts/materialicons-regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light.copyWith(
        textTheme: AppTheme.light.textTheme.apply(
          fontFamily: 'PostFormTestFont',
        ),
      ),
      home: RepaintBoundary(
        key: const ValueKey('post-form-preview'),
        child: PostRequestScreen(
          initialCategory: 'Cleaning',
          categoryNames: Stream.value(['Cleaning']),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    geocoding.GeocodingPlatformFactory.instance = _GeocodingFactory();
    // The map's native cache needs a platform directory in the render harness.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationCacheDirectory'
              ? Directory.systemTemp.path
              : null,
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          (call) async {
            if (call.method == 'isLocationServiceEnabled') return true;
            if (call.method == 'checkPermission') return 2;
            if (call.method == 'getCurrentPosition') {
              return <String, Object>{
                'latitude': 14.8441,
                'longitude': 120.8119,
                'timestamp': DateTime(2026, 10, 29).millisecondsSinceEpoch,
                'accuracy': 5.0,
                'altitude': 0.0,
                'altitudeAccuracy': 0.0,
                'heading': 0.0,
                'headingAccuracy': 0.0,
                'speed': 0.0,
                'speedAccuracy': 0.0,
                'isMocked': false,
              };
            }
            return null;
          },
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          null,
        );
  });

  Finder pickerField(String key, String childKey) => find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byKey(ValueKey(childKey)),
  );
  Finder gps(String key) => pickerField(key, 'job-location-gps');
  bool gpsEnabled(WidgetTester tester, String key) =>
      tester.widget<OutlinedButton>(gps(key)).onPressed != null;
  Future<void> selectWorkType(WidgetTester tester, String type) async {
    final tile = find.byKey(ValueKey('post-job-modality-$type'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  for (final owner in ['post-job-location', 'post-job-dropoff']) {
    testWidgets(
      'GPS on $owner restricts only the opposite GPS button and clearing releases it',
      (tester) async {
        await pumpPostForm(tester);
        await selectWorkType(tester, 'errand');
        final other = owner == 'post-job-location'
            ? 'post-job-dropoff'
            : 'post-job-location';
        await tester.ensureVisible(gps(owner));
        await tester.tap(gps(owner));
        await tester.pumpAndSettle();
        expect(gpsEnabled(tester, owner), isTrue);
        expect(gpsEnabled(tester, other), isFalse);
        expect(
          find.textContaining('Current location is in use for'),
          findsOneWidget,
        );
        for (final key in [owner, other]) {
          expect(
            tester
                .widget<TextField>(pickerField(key, 'job-location-search'))
                .enabled,
            isNot(false),
          );
        }
        final address = pickerField(owner, 'job-location-exact-address');
        expect(tester.widget<TextField>(address).enabled, isTrue);
        await tester.ensureVisible(address);
        await tester.enterText(address, 'A manually edited address');
        await tester.pumpAndSettle();
        expect(gpsEnabled(tester, other), isTrue);
        await tester.ensureVisible(gps(owner));
        await tester.tap(gps(owner));
        await tester.pumpAndSettle();
        expect(gpsEnabled(tester, other), isFalse);
        final search = pickerField(owner, 'job-location-search');
        await tester.ensureVisible(search);
        await tester.enterText(search, '');
        await tester.pumpAndSettle();
        expect(gpsEnabled(tester, other), isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'work type changes preserve pickup GPS and release removed drop-off GPS',
    (tester) async {
      await pumpPostForm(tester);
      await selectWorkType(tester, 'errand');
      await tester.ensureVisible(gps('post-job-location'));
      await tester.tap(gps('post-job-location'));
      await tester.pumpAndSettle();
      await selectWorkType(tester, 'onsite');
      expect(gpsEnabled(tester, 'post-job-location'), isTrue);
      expect(find.byKey(const ValueKey('post-job-dropoff')), findsNothing);
      await selectWorkType(tester, 'errand');
      expect(gpsEnabled(tester, 'post-job-dropoff'), isFalse);
      await selectWorkType(tester, 'online');
      expect(find.byKey(const ValueKey('post-job-location')), findsNothing);
      await selectWorkType(tester, 'errand');
      expect(gpsEnabled(tester, 'post-job-location'), isTrue);
      expect(gpsEnabled(tester, 'post-job-dropoff'), isTrue);
      await tester.ensureVisible(gps('post-job-dropoff'));
      await tester.tap(gps('post-job-dropoff'));
      await tester.pumpAndSettle();
      await selectWorkType(tester, 'hybrid');
      expect(gpsEnabled(tester, 'post-job-location'), isTrue);
      await selectWorkType(tester, 'errand');
      expect(gpsEnabled(tester, 'post-job-dropoff'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'duplicate pins block submission and different nearby pins clear the error',
    (tester) async {
      await pumpPostForm(tester);
      await selectWorkType(tester, 'errand');
      for (final entry in {
        'post-job-title': 'Deliver package',
        'post-job-errand-items': 'A package',
        'post-job-description': 'Please deliver carefully',
      }.entries) {
        final field = find.byKey(ValueKey(entry.key));
        await tester.ensureVisible(field);
        await tester.enterText(field, entry.value);
      }
      tester.testTextInput.hide();
      const pickup = JobLocationSelection(
        position: JobCoordinate(latitude: 14.8441, longitude: 120.8119),
        exactAddress: '123 Example St',
        areaLabel: 'Bulihan, Malolos',
      );
      JobLocationPicker picker(String key) => tester.widget<JobLocationPicker>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(JobLocationPicker),
        ),
      );
      picker('post-job-location').onChanged(pickup);
      await tester.pump();
      picker(
        'post-job-dropoff',
      ).onChanged(pickup.copyWith(exactAddress: 'Same pin, another spelling'));
      await tester.pumpAndSettle();
      final submit = find.byKey(const ValueKey('post-job-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text(errandSameLocationMessage), findsOneWidget);
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      picker('post-job-dropoff').onChanged(
        pickup.copyWith(
          position: const JobCoordinate(latitude: 14.8451, longitude: 120.8119),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .state<FormFieldState<JobLocationSelection>>(
              find.byKey(const ValueKey('post-job-dropoff')),
            )
            .validate(),
        isTrue,
      );
      await tester.pump();
      expect(find.text(errandSameLocationMessage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'reference section order preserves location and errand controls',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1150);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpPostForm(tester);
      final labels = [
        'Job title',
        'Category',
        'Work type',
        'Schedule',
        'Budget',
        'Location',
        'Description',
      ];
      final positions = labels
          .map((label) => tester.getTopLeft(find.text(label)).dy)
          .toList();
      for (var i = 1; i < positions.length; i++) {
        expect(
          positions[i],
          greaterThan(positions[i - 1]),
          reason: '${labels[i]} follows ${labels[i - 1]}',
        );
      }
      final output = Platform.environment['SWIFTSERVE_POST_PREVIEW_PATH'];
      if (output != null) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('post-form-preview')),
          );
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(output).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.ensureVisible(
        find.byKey(const ValueKey('post-job-modality-errand')),
      );
      await tester.tap(find.byKey(const ValueKey('post-job-modality-errand')));
      await tester.pumpAndSettle();
      expect(find.text('Delivery fee'), findsOneWidget);
      expect(find.byKey(const ValueKey('post-job-budget')), findsNothing);
      expect(find.byKey(const ValueKey('post-job-location')), findsOneWidget);
      expect(find.byKey(const ValueKey('post-job-dropoff')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('post-job-errand-items')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('post-job-item-cost')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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

    // The error is shown beside the schedule as well as in the snackbar.
    expect(find.text('Please choose both FROM and TO dates.'), findsWidgets);
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

class _Geocoding extends Fake implements geocoding.Geocoding {
  @override
  Future<List<geocoding.Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude, {
    Locale? locale,
  }) async => [
    const geocoding.Placemark(
      street: '123 Example Street',
      subLocality: 'Bulihan',
      locality: 'Malolos',
      subAdministrativeArea: 'Bulacan',
    ),
  ];
}
