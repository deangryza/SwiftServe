import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/services/staging_app_check.dart';

void main() {
  test(
    'fresh token diagnostics report success without exposing the token',
    () async {
      final messages = <String>[];
      expect(
        await requestFreshStagingToken(
          request: () async => 'private-token',
          report: messages.add,
        ),
        isTrue,
      );
      expect(messages.single, contains('acquired'));
      expect(messages.single, isNot(contains('private-token')));
    },
  );
  test(
    'null and failed fresh token requests do not block app startup',
    () async {
      expect(
        await requestFreshStagingToken(
          request: () async => null,
          report: (_) {},
        ),
        isFalse,
      );
      expect(
        await requestFreshStagingToken(
          request: () async => throw StateError('secret'),
          report: (message) {
            expect(message, isNot(contains('secret')));
          },
        ),
        isFalse,
      );
    },
  );
  bool allowed({
    bool requested = true,
    String project = 'swiftserve-staging-2026',
    bool debug = true,
    bool android = true,
    bool web = false,
  }) => stagingAppCheckAllowed(
    requested: requested,
    projectId: project,
    debug: debug,
    android: android,
    web: web,
  );
  test('staging App Check can initialize independently of push', () {
    expect(allowed(), isTrue);
  });
  test('disabled flag never activates App Check', () {
    expect(
      allowed(requested: false, project: 'swiftserve-production'),
      isFalse,
    );
  });
  test(
    'rejects production, arbitrary projects, release, web and non-Android',
    () {
      expect(() => allowed(project: 'swiftserve-production'), throwsStateError);
      expect(() => allowed(project: 'other'), throwsStateError);
      expect(() => allowed(debug: false), throwsStateError);
      expect(() => allowed(web: true), throwsStateError);
      expect(() => allowed(android: false), throwsStateError);
    },
  );
}
