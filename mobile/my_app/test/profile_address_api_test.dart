import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_app/shared/services/api_service.dart';

void main() {
  test(
    'worker service edits send resolved names without unrelated fields',
    () async {
      final api = ApiService(
        client: MockClient((request) async {
          expect(request.url.path, '/api/users/profile/details');
          expect(request.headers['Authorization'], 'Bearer worker-token');
          expect(jsonDecode(request.body), {
            'fullName': 'Worker',
            'services': ['Repair', 'Pet grooming'],
          });
          return http.Response('{}', 200);
        }),
      );
      await api.updateProfileDetails(
        idToken: 'worker-token',
        fullName: 'Worker',
        services: ['Repair', 'Pet grooming'],
      );
    },
  );

  test(
    'About-only save omits unchanged address and supports clearing About',
    () async {
      final api = ApiService(
        client: MockClient((request) async {
          expect(request.url.path, '/api/users/profile/details');
          expect(request.headers['Authorization'], 'Bearer token');
          expect(jsonDecode(request.body), {
            'fullName': 'Name',
            'description': '',
          });
          return http.Response('{}', 200);
        }),
      );
      await api.updateProfileDetails(
        idToken: 'token',
        fullName: 'Name',
        description: '',
      );
    },
  );

  test('About and address use the same save request', () async {
    final api = ApiService(
      client: MockClient((request) async {
        expect(jsonDecode(request.body), {
          'fullName': 'Name',
          'description': 'Reliable',
          'address': 'Brgy. Ligas, Malolos, Bulacan',
        });
        return http.Response('{}', 200);
      }),
    );
    await api.updateProfileDetails(
      idToken: 'token',
      fullName: 'Name',
      description: 'Reliable',
      address: 'Brgy. Ligas, Malolos, Bulacan',
    );
  });

  test('address save uses authenticated backend projection endpoint', () async {
    final api = ApiService(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/users/profile/address');
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(jsonDecode(request.body), {
          'fullName': 'Chichay',
          'address': '123 Street, Brgy. Ligas, Malolos, Bulacan',
        });
        return http.Response('{}', 200);
      }),
    );
    await api.updateProfileAddress(
      idToken: 'test-token',
      fullName: 'Chichay',
      address: '123 Street, Brgy. Ligas, Malolos, Bulacan',
    );
  });

  test(
    'address save propagates backend failure rather than claiming success',
    () async {
      final api = ApiService(
        client: MockClient((_) async => http.Response('{}', 500)),
      );
      await expectLater(
        api.updateProfileAddress(
          idToken: 'token',
          fullName: 'Name',
          address: 'Address',
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test('address save reports an unavailable backend', () async {
    final api = ApiService(
      client: MockClient((_) async => throw http.ClientException('Offline')),
    );
    await expectLater(
      api.updateProfileAddress(
        idToken: 'token',
        fullName: 'Name',
        address: 'Address',
      ),
      throwsA(isA<ApiConnectionException>()),
    );
  });
}
