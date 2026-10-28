import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/config/emergency_config.dart';
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/models/service_request.dart';
import 'package:my_app/shared/services/api_service.dart';
import 'package:my_app/shared/services/device_location_service.dart';
import 'package:my_app/shared/services/sos_service.dart';
import 'package:my_app/shared/widgets/sos_button.dart';

class _FakeApi extends ApiService {
  _FakeApi({this.fail = false});

  final bool fail;
  final raised = <Map<String, Object?>>[];
  final safe = <String>[];

  @override
  Future<String> raiseSos({
    required String idToken,
    required String requestId,
    double? latitude,
    double? longitude,
    double? accuracy,
  }) async {
    raised.add({'requestId': requestId, 'lat': latitude, 'lng': longitude});
    if (fail) throw const ApiConnectionException('Server unreachable.');
    return 'alert-1';
  }

  @override
  Future<void> markSosSafe({
    required String idToken,
    required String alertId,
  }) async => safe.add(alertId);
}

class _FakeLocation extends DeviceLocationService {
  const _FakeLocation({this.fail = false});

  final bool fail;

  @override
  Future<JobCoordinate> currentPosition() async {
    if (fail) {
      throw const DeviceLocationException(
        DeviceLocationFailure.permissionDenied,
      );
    }
    return const JobCoordinate(latitude: 14.84, longitude: 120.81);
  }
}

ServiceRequest _request({
  ServiceRequestStatus status = ServiceRequestStatus.ongoing,
  JobModality modality = JobModality.onsite,
}) => ServiceRequest(
  id: 'job-1',
  clientId: 'client',
  clientName: 'Carla',
  title: 'Fix sink',
  category: 'Repair',
  location: 'Malolos',
  description: '',
  budget: 500,
  status: status,
  modality: modality,
  workerId: 'worker',
);

void main() {
  late List<Uri> launched;

  SosService service(
    _FakeApi api, {
    bool locationFails = false,
    String dialNumber = '+639170000000',
  }) => SosService(
    api: api,
    dialNumber: dialNumber,
    location: _FakeLocation(fail: locationFails),
    launch: (uri) async {
      launched.add(uri);
      return true;
    },
    idToken: () async => 'token',
  );

  setUp(() => launched = []);

  test('SOS is offered only on accepted or ongoing in-person jobs', () {
    expect(sosAvailableFor(_request()), isTrue);
    expect(
      sosAvailableFor(_request(status: ServiceRequestStatus.accepted)),
      isTrue,
    );
    expect(sosAvailableFor(_request(modality: JobModality.errand)), isTrue);
    expect(
      sosAvailableFor(_request(status: ServiceRequestStatus.pending)),
      isFalse,
    );
    expect(
      sosAvailableFor(_request(status: ServiceRequestStatus.completed)),
      isFalse,
    );
    expect(sosAvailableFor(_request(modality: JobModality.online)), isFalse);
  });

  test('without a demo number SOS dials nothing', () async {
    expect(emergencyNumber, isEmpty);
    final sos = SosService(
      api: _FakeApi(),
      launch: (uri) async {
        launched.add(uri);
        return true;
      },
      idToken: () async => 'token',
    );
    expect(await sos.callEmergency(), isFalse);
    expect(launched, isEmpty);
  });

  test('the alert carries the current location', () async {
    final api = _FakeApi();
    expect(await service(api).raiseAlert('job-1'), 'alert-1');
    expect(api.raised.single, {
      'requestId': 'job-1',
      'lat': 14.84,
      'lng': 120.81,
    });
  });

  test('a location failure still sends the alert', () async {
    final api = _FakeApi();
    await service(api, locationFails: true).raiseAlert('job-1');
    expect(api.raised.single['lat'], isNull);
  });

  testWidgets('the button is hidden when SOS does not apply', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SosButton(
            request: _request(status: ServiceRequestStatus.completed),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('sos-button')), findsNothing);
  });

  Future<void> pressSos(WidgetTester tester, SosService sos) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SosButton(request: _request(), service: sos),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('sos-button')));
    await tester.pumpAndSettle();
  }

  testWidgets('cancelling the confirmation does nothing', (tester) async {
    final api = _FakeApi();
    await pressSos(tester, service(api));
    await tester.tap(find.byKey(const ValueKey('sos-cancel')));
    await tester.pumpAndSettle();
    expect(launched, isEmpty);
    expect(api.raised, isEmpty);
  });

  testWidgets('confirming dials the demo contact and reports the alert', (
    tester,
  ) async {
    final api = _FakeApi();
    await pressSos(tester, service(api));
    await tester.tap(find.byKey(const ValueKey('sos-confirm')));
    await tester.pumpAndSettle();

    expect(launched.single.toString(), 'tel:+639170000000');
    expect(api.raised, hasLength(1));
    expect(find.text('SwiftServe has been alerted'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sos-safe')));
    await tester.pumpAndSettle();
    expect(api.safe, ['alert-1']);
    expect(find.byKey(const ValueKey('sos-status')), findsNothing);
  });

  testWidgets('a failed alert still dials and offers a retry', (tester) async {
    final api = _FakeApi(fail: true);
    await pressSos(tester, service(api));
    await tester.tap(find.byKey(const ValueKey('sos-confirm')));
    await tester.pumpAndSettle();

    expect(launched.single.toString(), 'tel:+639170000000');
    expect(find.text('Couldn\'t alert SwiftServe'), findsOneWidget);
    expect(find.text('Retry alert'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sos-resend')));
    await tester.pumpAndSettle();
    expect(api.raised, hasLength(2));
  });
}
