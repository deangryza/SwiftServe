import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/services/device_location_service.dart';
import 'package:my_app/shared/services/job_geocoding_service.dart';
import 'package:my_app/shared/widgets/job_location_picker.dart';

class _FakeLocationService extends DeviceLocationService {
  _FakeLocationService({this.position, this.error, this.response});

  final JobCoordinate? position;
  final DeviceLocationException? error;
  final Future<JobCoordinate>? response;
  int settingsOpenCount = 0;

  @override
  Future<JobCoordinate> currentPosition() async {
    if (error != null) throw error!;
    if (response != null) return response!;
    return position!;
  }

  @override
  Future<bool> openRecoverySettings(DeviceLocationFailure failure) async {
    settingsOpenCount += 1;
    return true;
  }
}

class _FakeGeocodingService implements JobAddressResolver {
  _FakeGeocodingService({
    this.result,
    this.shouldFail = false,
    this.searchHandler,
    this.resolveHandler,
  });

  final ResolvedJobAddress? result;
  final bool shouldFail;
  final Future<JobLocationSelection> Function(String)? searchHandler;
  final Future<ResolvedJobAddress> Function(JobCoordinate)? resolveHandler;
  final searches = <String>[];

  @override
  Future<JobLocationSelection> search(String address) async {
    searches.add(address);
    if (searchHandler != null) return searchHandler!(address);
    throw StateError('No matching address');
  }

  @override
  Future<ResolvedJobAddress> resolve(JobCoordinate coordinate) async {
    if (resolveHandler != null) return resolveHandler!(coordinate);
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
  JobLocationSelection? initialValue,
  String? errorText,
  JobLocationMapBuilder? mapBuilder = _testMap,
  bool currentLocationEnabled = true,
  bool Function()? onCurrentLocationRequested,
  VoidCallback? onCurrentLocationReleased,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: JobLocationPicker(
        locationService: locationService,
        geocodingService: geocodingService,
        initialValue: initialValue,
        mapBuilder: mapBuilder,
        errorText: errorText,
        currentLocationEnabled: currentLocationEnabled,
        onCurrentLocationRequested: onCurrentLocationRequested,
        onCurrentLocationReleased: onCurrentLocationReleased,
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

  testWidgets(
    'reserves GPS before startup and releases when typing cancels startup',
    (tester) async {
      final gps = Completer<JobCoordinate>();
      var reservations = 0;
      var releases = 0;
      final selections = <JobLocationSelection?>[];
      await tester.pumpWidget(
        _harness(
          locationService: _FakeLocationService(response: gps.future),
          geocodingService: _FakeGeocodingService(result: resolved),
          onCurrentLocationRequested: () {
            reservations++;
            return true;
          },
          onCurrentLocationReleased: () {
            releases++;
          },
          onChanged: selections.add,
        ),
      );
      await tester.tap(find.text('Use my current location'));
      await tester.pump();
      expect(reservations, 1);
      expect(releases, 0);
      await tester.enterText(
        find.byKey(const ValueKey('job-location-search')),
        'M',
      );
      await tester.pump();
      expect(releases, 1);
      gps.complete(coordinate);
      await tester.pumpAndSettle();
      expect(selections.whereType<JobLocationSelection>(), isEmpty);
      expect(find.text('Choose pin'), findsOneWidget);
    },
  );

  for (final permissionError in [true, false]) {
    testWidgets(
      'GPS ${permissionError ? 'permission' : 'unexpected'} failure releases reservation',
      (tester) async {
        var releases = 0;
        final gps = Completer<JobCoordinate>();
        await tester.pumpWidget(
          _harness(
            locationService: _FakeLocationService(response: gps.future),
            geocodingService: _FakeGeocodingService(result: resolved),
            onCurrentLocationRequested: () => true,
            onCurrentLocationReleased: () {
              releases++;
            },
          ),
        );
        await tester.tap(find.text('Use my current location'));
        await tester.pump();
        gps.completeError(
          permissionError
              ? const DeviceLocationException(
                  DeviceLocationFailure.permissionDenied,
                )
              : StateError('GPS platform unavailable'),
        );
        await tester.pumpAndSettle();
        expect(releases, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'failed GPS retry retains ownership of the previously selected GPS pin',
    (tester) async {
      var releases = 0;
      Widget harness(DeviceLocationService service) => _harness(
        locationService: service,
        geocodingService: _FakeGeocodingService(result: resolved),
        onCurrentLocationRequested: () => true,
        onCurrentLocationReleased: () {
          releases++;
        },
      );
      await tester.pumpWidget(
        harness(_FakeLocationService(position: coordinate)),
      );
      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        harness(
          _FakeLocationService(
            error: const DeviceLocationException(
              DeviceLocationFailure.timedOut,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();
      expect(releases, 0);
      expect(find.text('Pin selected'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('job-location-exact-address')),
            )
            .controller!
            .text,
        resolved.exactAddress,
      );
    },
  );

  testWidgets(
    'map selection releases GPS ownership without disabling manual lookup',
    (tester) async {
      var releases = 0;
      await tester.pumpWidget(
        _harness(
          locationService: _FakeLocationService(position: coordinate),
          geocodingService: _FakeGeocodingService(result: resolved),
          onCurrentLocationRequested: () => true,
          onCurrentLocationReleased: () {
            releases++;
          },
        ),
      );
      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();
      expect(releases, 0);
      await tester.tap(find.byKey(const Key('select-map-pin')));
      await tester.pumpAndSettle();
      expect(releases, 1);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('job-location-search')),
            )
            .enabled,
        isNot(false),
      );
    },
  );

  testWidgets(
    'disabled GPS leaves manual search enabled and request veto prevents GPS startup',
    (tester) async {
      var attempts = 0;
      Widget harness(bool enabled) => _harness(
        locationService: _FakeLocationService(),
        geocodingService: _FakeGeocodingService(result: resolved),
        currentLocationEnabled: enabled,
        onCurrentLocationRequested: () {
          attempts++;
          return false;
        },
      );
      await tester.pumpWidget(harness(false));
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('job-location-gps')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('job-location-search')),
            )
            .enabled,
        isNot(false),
      );
      await tester.pumpWidget(harness(true));
      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(find.text('Choose pin'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
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
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('job-location-search')))
          .enabled,
      isNot(false),
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('job-location-exact-address')),
          )
          .enabled,
      isFalse,
    );
    expect(
      find.text('Choose the service location on the map.'),
      findsOneWidget,
    );
  });

  testWidgets('starts from a saved pin when editing a post', (tester) async {
    await tester.pumpWidget(
      _harness(
        locationService: _FakeLocationService(position: coordinate),
        geocodingService: _FakeGeocodingService(result: resolved),
        initialValue: const JobLocationSelection(
          position: coordinate,
          exactAddress: '45 Saved Street, Malolos',
          areaLabel: 'Malolos, Bulacan',
        ),
      ),
    );

    expect(find.text('Pin selected'), findsOneWidget);
    expect(find.text('45 Saved Street, Malolos'), findsOneWidget);
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

    expect(find.text(resolved.exactAddress), findsNWidgets(2));
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
    await tester.enterText(
      find.byKey(const ValueKey('job-location-exact-address')),
      'Manual service address',
    );
    await tester.pump();

    expect(selection?.exactAddress, 'Manual service address');
    expect(selection?.areaLabel, 'Pinned service area');
  });

  const searchKey = ValueKey('job-location-search');
  const found = JobLocationSelection(
    position: JobCoordinate(latitude: 14.55, longitude: 121.02),
    exactAddress: 'Greenbelt, Makati',
    areaLabel: 'Makati',
  );

  testWidgets('debounces typing and commits only a resolved selection', (
    tester,
  ) async {
    final response = Completer<JobLocationSelection>();
    final geocoding = _FakeGeocodingService(
      searchHandler: (_) => response.future,
    );
    JobLocationSelection? selection;
    await tester.pumpWidget(
      _harness(
        locationService: _FakeLocationService(),
        geocodingService: geocoding,
        onChanged: (value) => selection = value,
      ),
    );
    await tester.enterText(find.byKey(searchKey), 'Green');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(searchKey), 'Greenbelt');
    await tester.pump(const Duration(milliseconds: 649));
    expect(geocoding.searches, isEmpty);
    expect(selection, isNull);
    await tester.pump(const Duration(milliseconds: 1));
    expect(geocoding.searches, ['Greenbelt']);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    response.complete(found);
    await tester.pumpAndSettle();
    expect(selection?.position, same(found.position));
    expect(selection?.exactAddress, found.exactAddress);
    expect(find.text('Pin selected'), findsOneWidget);
    expect(find.text('Search'), findsNothing);
    expect(find.text('Locate'), findsNothing);
  });

  testWidgets(
    'empty or short input never searches or reuses stale coordinates',
    (tester) async {
      final geocoding = _FakeGeocodingService(result: resolved);
      JobLocationSelection? selection;
      await tester.pumpWidget(
        _harness(
          locationService: _FakeLocationService(position: coordinate),
          geocodingService: geocoding,
          onChanged: (value) => selection = value,
        ),
      );
      await tester.tap(find.byKey(const Key('select-map-pin')));
      await tester.pumpAndSettle();
      expect(selection, isNotNull);
      await tester.enterText(find.byKey(searchKey), '');
      await tester.pump(const Duration(seconds: 1));
      expect(selection, isNull);
      expect(find.text('Pin selected'), findsOneWidget);
      await tester.enterText(find.byKey(searchKey), 'Ma');
      await tester.pump(const Duration(seconds: 1));
      expect(geocoding.searches, isEmpty);
      expect(selection, isNull);
    },
  );

  for (final error in [
    StateError('No matching address'),
    const SocketException('offline'),
  ]) {
    testWidgets('failed search preserves the last marker: $error', (
      tester,
    ) async {
      JobCoordinate? marker;
      JobLocationSelection? selection;
      await tester.pumpWidget(
        _harness(
          locationService: _FakeLocationService(position: coordinate),
          geocodingService: _FakeGeocodingService(
            result: resolved,
            searchHandler: (_) async => throw error,
          ),
          onChanged: (value) => selection = value,
          mapBuilder: (context, position, select) {
            marker = position;
            return _testMap(context, position, select);
          },
        ),
      );
      await tester.tap(find.byKey(const Key('select-map-pin')));
      await tester.pumpAndSettle();
      final previous = marker;
      await tester.enterText(find.byKey(searchKey), 'Unknown place');
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();
      expect(marker, same(previous));
      expect(selection, isNull);
      expect(
        find.textContaining('Could not find this location'),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    'typing again invalidates an already running search immediately',
    (tester) async {
      final older = Completer<JobLocationSelection>();
      final newer = Completer<JobLocationSelection>();
      JobLocationSelection? selection;
      await tester.pumpWidget(
        _harness(
          locationService: _FakeLocationService(),
          geocodingService: _FakeGeocodingService(
            searchHandler: (query) =>
                query == 'Old place' ? older.future : newer.future,
          ),
          onChanged: (value) => selection = value,
        ),
      );
      await tester.enterText(find.byKey(searchKey), 'Old place');
      await tester.pump(const Duration(milliseconds: 650));
      await tester.enterText(find.byKey(searchKey), 'New place');
      older.complete(found);
      await tester.pump();
      expect(selection, isNull);
      expect(find.text('Choose pin'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 650));
      newer.complete(found.copyWith(exactAddress: 'New place'));
      await tester.pumpAndSettle();
      expect(selection?.exactAddress, 'New place');
    },
  );

  for (final useGps in [false, true]) {
    testWidgets(
      '${useGps ? 'GPS' : 'map'} selection supersedes a running search',
      (tester) async {
        final old = Completer<JobLocationSelection>();
        JobLocationSelection? selection;
        await tester.pumpWidget(
          _harness(
            locationService: _FakeLocationService(position: coordinate),
            geocodingService: _FakeGeocodingService(
              result: resolved,
              searchHandler: (_) => old.future,
            ),
            onChanged: (value) => selection = value,
          ),
        );
        await tester.enterText(find.byKey(searchKey), 'Old place');
        await tester.pump(const Duration(milliseconds: 650));
        final control = useGps
            ? find.text('Use my current location')
            : find.byKey(const Key('select-map-pin'));
        await tester.ensureVisible(control);
        await tester.tap(control);
        await tester.pumpAndSettle();
        old.complete(found);
        await tester.pumpAndSettle();
        expect(selection?.position.latitude, coordinate.latitude);
        expect(selection?.exactAddress, resolved.exactAddress);
        expect(
          tester.widget<TextField>(find.byKey(searchKey)).controller!.text,
          resolved.exactAddress,
        );
      },
    );
  }

  testWidgets('manual lookup works after GPS permission is denied', (
    tester,
  ) async {
    JobLocationSelection? selection;
    await tester.pumpWidget(
      _harness(
        locationService: _FakeLocationService(
          error: const DeviceLocationException(
            DeviceLocationFailure.permissionDenied,
          ),
        ),
        geocodingService: _FakeGeocodingService(
          searchHandler: (_) async => found,
        ),
        onChanged: (value) => selection = value,
      ),
    );
    await tester.ensureVisible(find.text('Use my current location'));
    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(searchKey));
    await tester.enterText(find.byKey(searchKey), 'Greenbelt');
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();
    expect(selection?.position, same(found.position));
  });

  testWidgets('a late GPS fix cannot replace a newer text selection', (
    tester,
  ) async {
    final gps = Completer<JobCoordinate>();
    JobLocationSelection? selection;
    await tester.pumpWidget(
      _harness(
        locationService: _FakeLocationService(response: gps.future),
        geocodingService: _FakeGeocodingService(
          searchHandler: (_) async => found,
        ),
        onChanged: (value) => selection = value,
      ),
    );
    await tester.ensureVisible(find.text('Use my current location'));
    await tester.tap(find.text('Use my current location'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(searchKey));
    await tester.enterText(find.byKey(searchKey), 'Greenbelt');
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();
    gps.complete(coordinate);
    await tester.pumpAndSettle();
    expect(selection?.position, same(found.position));
  });

  testWidgets('disposing cancels a pending debounce', (tester) async {
    final geocoding = _FakeGeocodingService();
    await tester.pumpWidget(
      _harness(
        locationService: _FakeLocationService(),
        geocodingService: geocoding,
      ),
    );
    await tester.enterText(find.byKey(searchKey), 'Greenbelt');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(geocoding.searches, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('map selection cancels a search still waiting for debounce', (
    tester,
  ) async {
    final geocoding = _FakeGeocodingService(result: resolved);
    JobLocationSelection? selection;
    await tester.pumpWidget(
      _harness(
        locationService: _FakeLocationService(),
        geocodingService: geocoding,
        onChanged: (value) => selection = value,
      ),
    );
    await tester.enterText(find.byKey(searchKey), 'Old search');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.byKey(const Key('select-map-pin')));
    await tester.tap(find.byKey(const Key('select-map-pin')));
    await tester.pump(const Duration(seconds: 1));
    expect(geocoding.searches, isEmpty);
    expect(selection?.exactAddress, resolved.exactAddress);
  });

  testWidgets('late reverse lookup cannot overwrite a newer address search', (
    tester,
  ) async {
    final reverse = Completer<ResolvedJobAddress>();
    JobLocationSelection? selection;
    await tester.pumpWidget(
      _harness(
        locationService: _FakeLocationService(),
        geocodingService: _FakeGeocodingService(
          resolveHandler: (_) => reverse.future,
          searchHandler: (_) async => found,
        ),
        onChanged: (value) => selection = value,
      ),
    );
    await tester.tap(find.byKey(const Key('select-map-pin')));
    await tester.pump();
    await tester.enterText(find.byKey(searchKey), 'Greenbelt');
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();
    reverse.complete(resolved);
    await tester.pumpAndSettle();
    expect(selection?.position, same(found.position));
    expect(selection?.exactAddress, found.exactAddress);
  });

  testWidgets(
    'pickup and drop-off searches keep independent selected locations',
    (tester) async {
      JobLocationSelection? pickup;
      JobLocationSelection? dropoff;
      final other = found.copyWith(
        position: coordinate,
        exactAddress: resolved.exactAddress,
        areaLabel: resolved.areaLabel,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  JobLocationPicker(
                    key: const ValueKey('pickup'),
                    onChanged: (value) => pickup = value,
                    geocodingService: _FakeGeocodingService(
                      searchHandler: (_) async => found,
                    ),
                    mapBuilder: _testMap,
                  ),
                  JobLocationPicker(
                    key: const ValueKey('dropoff'),
                    onChanged: (value) => dropoff = value,
                    geocodingService: _FakeGeocodingService(
                      searchHandler: (_) async => other,
                    ),
                    mapBuilder: _testMap,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final pickupInput = find.descendant(
        of: find.byKey(const ValueKey('pickup')),
        matching: find.byKey(searchKey),
      );
      final dropoffInput = find.descendant(
        of: find.byKey(const ValueKey('dropoff')),
        matching: find.byKey(searchKey),
      );
      await tester.enterText(pickupInput, 'Greenbelt');
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();
      await tester.ensureVisible(dropoffInput);
      await tester.enterText(dropoffInput, 'Malolos');
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();
      expect(pickup?.position, same(found.position));
      expect(dropoff?.position, same(coordinate));
    },
  );

  testWidgets('resolved search moves the real map camera and marker', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
      final bytes = await File(
        '${artifacts.path}/material_fonts/roboto-regular.ttf',
      ).readAsBytes();
      await (FontLoader(
        'MapTestFont',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'MapTestFont'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: JobLocationPicker(
              onChanged: (_) {},
              locationService: _FakeLocationService(position: coordinate),
              geocodingService: _FakeGeocodingService(
                result: resolved,
                searchHandler: (_) async => found,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byKey(searchKey), 'Greenbelt');
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .mapController!;
    expect(controller.camera.center.latitude, found.position.latitude);
    expect(controller.camera.center.longitude, found.position.longitude);
    expect(controller.camera.zoom, 16);
    final marker = tester
        .widget<DragMarkers>(find.byType(DragMarkers))
        .markers
        .single;
    expect(marker.point.latitude, found.position.latitude);
    expect(marker.point.longitude, found.position.longitude);
    expect(
      find.text('Location found. Check the pin before posting.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Use my current location'));
    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();
    expect(controller.camera.center.latitude, coordinate.latitude);
    expect(controller.camera.center.longitude, coordinate.longitude);
    expect(
      tester.widget<TextField>(find.byKey(searchKey)).controller!.text,
      resolved.exactAddress,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
