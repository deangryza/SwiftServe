import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_app/shared/services/staging_api_client.dart';

void main() {
  final endpoint = Uri.parse('http://127.0.0.1:5002/api/users/profile');
  test(
    'staging sends App Check and preserves Authentication without logging either',
    () async {
      final reports = <String>[];
      final client = StagingApiClient(
        inner: MockClient((request) async {
          expect(request.headers['X-Firebase-AppCheck'], 'private-app-check');
          expect(request.headers['Authorization'], 'Bearer private-auth');
          return http.Response('{}', 201);
        }),
        project: () => 'swiftserve-staging-2026',
        token: () async => 'private-app-check',
        report: reports.add,
      );
      expect(
        (await client.post(
          endpoint,
          headers: {'Authorization': 'Bearer private-auth'},
        )).statusCode,
        201,
      );
      expect(reports.join(), isNot(contains('private')));
      client.close();
    },
  );
  test(
    'rejects production project and every backend except loopback port 5002',
    () async {
      var calls = 0;
      for (final project in [
        'swiftserve-production',
        'swiftserve-staging-2026',
      ]) {
        final client = StagingApiClient(
          inner: MockClient((_) async {
            calls++;
            return http.Response('{}', 200);
          }),
          project: () => project,
          token: () async => 'private',
          report: (_) {},
        );
        final urls = project == 'swiftserve-production'
            ? [endpoint]
            : [
                Uri.parse('http://127.0.0.1:5000/api/users/profile'),
                Uri.parse('https://example.com:5002/api/users/profile'),
                Uri.parse('http://localhost:5002/api/users/profile'),
              ];
        for (final url in urls) {
          await expectLater(
            client.get(url),
            throwsA(isA<http.ClientException>()),
          );
        }
        client.close();
      }
      expect(calls, 0);
    },
  );
  test(
    'App Check failure blocks writes, while health remains reachable',
    () async {
      var calls = 0;
      final client = StagingApiClient(
        inner: MockClient((request) async {
          calls++;
          expect(request.headers.containsKey('X-Firebase-AppCheck'), isFalse);
          return http.Response('{}', 200);
        }),
        project: () => 'swiftserve-staging-2026',
        token: () async => null,
        report: (_) {},
      );
      await expectLater(
        client.post(endpoint),
        throwsA(isA<http.ClientException>()),
      );
      await client.get(Uri.parse('http://127.0.0.1:5002/api/health'));
      expect(calls, 1);
      client.close();
    },
  );
}
