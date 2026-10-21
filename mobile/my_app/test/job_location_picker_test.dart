import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/services/device_location_service.dart';
import 'package:my_app/shared/services/job_geocoding_service.dart';
import 'package:my_app/shared/widgets/job_location_picker.dart';

class _FakeLocationService extends DeviceLocationService {
  _FakeLocationService({this.position, this.error});

  final JobCoordinate? position;
  final DeviceLocationException? error;
  int settingsOpenCount = 0;

  @override
  Future<JobCoordinate> currentPosition() async {
    if (error != null) throw error!;
    return position!;
  }

  @override
  Future<bool> openRecoverySettings(DeviceLocationFailure failure) async {
    settingsOpenCount += 1;
    return true;
  }
}

class _FakeGeocodingService implements JobAddressResolver {
  _FakeGeocodingService({this.result, this.shouldFail = false});

  final ResolvedJobAddress? result;
  final bool shouldFail;

  @override
  Future<ResolvedJobAddress> resolve(JobCoordinate coordinate) async {
    if (shouldFail) throw StateError('lookup failed');
    return result!;
  }
}

Widget _testMap(
  BuildContext context,
  JobCoordinate? position,
  ValueChanged<JobCoordinate> onSelected,
) => SizedBox(
  height: 230,
  child: TextButton(
    key: const Key('select-map-pin'),
    onPressed: () =>
        onSelected(const JobCoordinate(latitude: 14.8441, longitude: 120.8119)),
    child: Text(position == null ? 'Choose pin' : 'Pin selected'),
  ),
);

Widget _harness({
  required DeviceLocationService locationService,
  required JobAddressResolver geocodingService,
  ValueChanged<JobLocationSelection?>? onChanged,
  String? errorText,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: JobLocationPicker(
        locationService: locationService,
        geocodingService: geocodingService,
        mapBuilder: _testMap,
        errorText: errorText,
        onChanged: onChanged ?? (_) {},
      ),
    ),
  ),
);

void main() {
  const coordinate = JobCoordinate(latitude: 14.8441, longitude: 120.8119);
  const resolved = ResolvedJobAddress(
    exactAddress: '123 Example Street, Malolos, Bulacan',
    areaLabel: 'Malolos, Bulacan',
  );

  testWidgets('starts without a pin and exposes inline validation', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        locationService: _FakeLocationService(position: coordinate),
        geocodingService: _FakeGeocodingService(result: resolved),
        errorText: 'Choose the service location on the map.',
      ),
    );

    expect(find.text('Choose pin'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      find.text('Choose the service location on the map.'),
      findsOneWidget,
    );
  });

  testWidgets('shows a recoverable permission-denied state', (tester) async {
    await tester.pumpWidget(
      _harness(
        locationService: _FakeLocationService(
          error: const DeviceLocationException(
            DeviceLocationFailure.permissionDenied,
          ),
        ),
        geocodingService: _FakeGeocodingService(result: resolved),
      ),
    );

    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Location permission was denied'),
      findsOneWidget,
    );
    expect(find.text('Use my current location'), findsOneWidget);
  });

  testWidgets('offers settings recovery when location services are disabled', (
    tester,
  ) async {
    final locationService = _FakeLocationService(
      error: const DeviceLocationException(
        DeviceLocationFailure.serviceDisabled,
      ),
    );
    await tester.pumpWidget(
      _harness(
        locationService: locationService,
        geocodingService: _FakeGeocodingService(result: resolved),
      ),
    );

    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open location settings'));
    await tester.pump();

    expect(locationService.settingsOpenCount, 1);
  });

  testWidgets('GPS selection resolves an address and emits a safe area label', (
    tester,
  ) async {
    JobLocationSelection? selection;
    await tester.pumpWidget(
      _harness(
        locationService: _FakeLocationService(position: coordinate),
        geocodingService: _FakeGeocodingService(result: resolved),
        onChanged: (value) => selection = value,
      ),
    );

    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();

    expect(find.text(resolved.exactAddress), findsOneWidget);
    expect(selection?.areaLabel, 'Malolos, Bulacan');
    expect(selection?.position.latitude, 14.8441);
    expect(
      find.text('Exact address is shared only with the accepted worker.'),
      findsOneWidget,
    );
  });

  testWidgets('keeps the pin and accepts manual address after lookup failure', (
    tester,
  ) async {
    JobLocationSelection? selection;
    await tester.pumpWidget(
      _harness(
        locationService: _FakeLocationService(position: coordinate),
        geocodingService: _FakeGeocodingService(shouldFail: true),
        onChanged: (value) => selection = value,
      ),
    );

    await tester.tap(find.byKey(const Key('select-map-pin')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Address lookup failed'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Manual service address');
    await tester.pump();

    expect(selection?.exactAddress, 'Manual service address');
    expect(selection?.areaLabel, 'Pinned service area');
  });
}
