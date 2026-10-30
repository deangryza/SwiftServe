import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/utils/public_profile_location.dart';
import 'package:my_app/shared/screens/public_profile_screen.dart';

void main() {
  final cases =
      jsonDecode(
            File(
              'test/fixtures/public_profile_locations.json',
            ).readAsStringSync(),
          )
          as List;
  for (var i = 0; i < cases.length; i++) {
    test('public location shared vector ${i + 1}', () {
      final fixture = cases[i] as Map<String, dynamic>;
      final input = fixture['input'];
      final result = input is Map<String, dynamic>
          ? PublicProfileLocation.fromProfile(input)
          : PublicProfileLocation.fromAddress(input);
      expect(result.label, fixture['expected']);
      expect(
        result.displayLabel,
        result.label.isEmpty ? 'Location not provided' : result.label,
      );
    });
  }
  test('private street cannot be found via profile search in either role', () {
    for (final role in ['worker', 'client']) {
      final profile = <String, dynamic>{
        'role': role,
        'fullName': 'User',
        'location': '123 Example Street, Brgy. Ligas, Malolos, Bulacan',
      };
      expect(publicProfileMatchesQuery(profile, 'example street'), isFalse);
      expect(publicProfileMatchesQuery(profile, '123'), isFalse);
      expect(publicProfileMatchesQuery(profile, 'bulacan'), isFalse);
      expect(publicProfileMatchesQuery(profile, 'ligas'), isTrue);
      expect(publicProfileMatchesQuery(profile, 'malolos'), isTrue);
    }
  });
  test('overlong raw or structured location fields fail closed', () {
    expect(
      PublicProfileLocation.fromAddress('Brgy. Ligas, ${'x' * 301}').label,
      isEmpty,
    );
    expect(
      PublicProfileLocation.fromProfile({'cityMunicipality': 'x' * 81}).label,
      isEmpty,
    );
  });
}
