import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_app/shared/services/national_id_mock_client.dart';
import 'package:my_app/features/auth/presentation/screens/national_id_mock_screen.dart';
import 'package:my_app/shared/theme/app_theme.dart';
import 'package:my_app/shared/utils/synthetic_identity_image.dart';

final reference = 'mock-v1-${List.filled(64, 'a').join()}';
Map<String, dynamic> wire(String state) => {
  'verificationReference': reference,
  'providerType': 'MOCK',
  'officiallyVerified': false,
  'verificationStatus': state,
  'consentVersion': state == 'CONSENT_REQUIRED'
      ? null
      : NationalIdMockClient.consentVersion,
  'governmentVerificationStatus': 'PASSED',
  'faceVerificationStatus': 'UNAVAILABLE',
  'livenessStatus': 'UNSUPPORTED',
};
NationalIdMockClient client(
  http.Client transport, {
  String project = 'demo-swiftserve-cleanup',
  String Function()? uid,
  bool enabled = true,
}) => NationalIdMockClient(
  client: transport,
  project: () => project,
  uid: uid ?? () => 'synthetic-user',
  token: () async => 'synthetic-token',
  baseUrl: Uri.parse('http://127.0.0.1:5007'),
  enabled: enabled,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('generated test pair uses a decodable bounded geometric PNG', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bytes = await syntheticIdentityImage();
      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(bytes.length, lessThan(1500000));
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 320);
      expect(frame.image.height, 320);
      frame.image.dispose();
      codec.dispose();
    });
  });
  test(
    'mock is disabled by default; production and staging targets cannot make requests',
    () async {
      expect(NationalIdMockClient.buildEnabled, isFalse);
      var requests = 0;
      final transport = MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      });
      for (final api in [
        client(transport, enabled: false),
        client(transport, project: 'swiftserve-production'),
        client(transport, project: 'swiftserve-staging-2026'),
      ]) {
        await expectLater(api.begin(), throwsStateError);
      }
      expect(requests, 0);
    },
  );
  test(
    'persistent idempotency is scoped to project/account and sends no client verdict',
    () async {
      final ids = <String>[];
      var uid = 'synthetic-a';
      final api = client(
        MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body.keys.toList(), ['requestId']);
          ids.add(body['requestId']);
          return http.Response(jsonEncode(wire('CONSENT_REQUIRED')), 201);
        }),
        uid: () => uid,
      );
      await api.begin();
      await api.begin();
      expect(ids[0], ids[1]);
      uid = 'synthetic-b';
      await api.begin();
      expect(ids[2], isNot(ids[0]));
      await api.begin(fresh: true);
      expect(ids[3], isNot(ids[2]));
    },
  );
  test(
    'response parser never treats official-looking or injected paths as mock verification',
    () {
      expect(
        () => MockIdentityResult.fromJson({
          ...wire('VERIFIED'),
          'providerType': 'PSA',
        }),
        throwsFormatException,
      );
      expect(
        () => MockIdentityResult.fromJson({
          ...wire('VERIFIED'),
          'officiallyVerified': true,
        }),
        throwsFormatException,
      );
      expect(
        () => MockIdentityResult.fromJson({
          ...wire('VERIFIED'),
          'verificationReference': '../users',
        }),
        throwsFormatException,
      );
      expect(IdentityState.parse('INVENTED'), IdentityState.failed);
    },
  );
  test(
    'upload checks size/type and reports progress without sending client outcomes',
    () async {
      var count = 0;
      final api = client(
        MockClient((request) async {
          count++;
          expect(request.headers['Authorization'], 'Bearer synthetic-token');
          final multipart = utf8.decode(
            request.bodyBytes,
            allowMalformed: true,
          );
          expect(multipart, contains('documentFormat'));
          expect(multipart, isNot(contains('livenessPassed')));
          return http.Response(jsonEncode(wire('MANUAL_REVIEW')), 200);
        }),
      );
      await expectLater(
        api.submit(reference, Uint8List(2), Uint8List(2), digital: false),
        throwsFormatException,
      );
      final bytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      var progress = 0.0;
      final result = await api.submit(
        reference,
        bytes,
        bytes,
        digital: true,
        progress: (value) => progress = value,
      );
      expect(count, 1);
      expect(progress, 1);
      expect(result.state, IdentityState.manualReview);
    },
  );
  testWidgets(
    'consent gates capture and mock results never claim official verification',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var submitted = false, continued = false;
      final api = client(
        MockClient((request) async {
          final state = request.url.path.endsWith('/consent')
              ? 'PENDING'
              : request.url.path.endsWith('/submit')
              ? 'MANUAL_REVIEW'
              : 'CONSENT_REQUIRED';
          submitted |= request.url.path.endsWith('/submit');
          return http.Response(jsonEncode(wire(state)), 200);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: NationalIdMockScreen(
            client: api,
            onContinue: () => continued = true,
            capture: (_, _, _) async =>
                Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(MockIdentityResult.label), findsOneWidget);
      expect(find.byKey(const ValueKey('identity-document')), findsNothing);
      final consent = find.byKey(const ValueKey('identity-consent'));
      await tester.scrollUntilVisible(consent, 200);
      await tester.pumpAndSettle();
      await tester.tap(consent);
      await tester.pumpAndSettle();
      expect(find.text('Mock status: pending'), findsOneWidget);
      for (final key in [
        'identity-document',
        'identity-selfie',
        'identity-submit',
      ]) {
        final action = find.byKey(ValueKey(key));
        await tester.scrollUntilVisible(action, 200);
        await tester.pumpAndSettle();
        await tester.tap(action);
        await tester.pumpAndSettle();
      }
      expect(submitted, isTrue);
      await tester.scrollUntilVisible(
        find.text('Mock status: manualReview'),
        -250,
      );
      expect(find.text('Mock status: manualReview'), findsOneWidget);
      final leave = find.text('Continue to app (mock only)');
      await tester.scrollUntilVisible(leave, 200);
      await tester.tap(leave);
      await tester.pumpAndSettle();
      expect(continued, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
