import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/screens/public_profile_screen.dart';

void main() {
  group('publicProfileMatchesQuery', () {
    final worker = <String, dynamic>{
      'role': 'worker',
      'fullName': 'Maria Santos',
      'location': 'Malolos, Bulacan',
      'category': 'Home Services',
      'skills': ['Plumbing', 'Painting'],
      'description': 'Careful repairs for homes and small businesses.',
    };

    test('matches every searchable worker profile field', () {
      for (final query in [
        'maria',
        'malolos',
        'home services',
        'plumbing',
        'careful repairs',
      ]) {
        expect(publicProfileMatchesQuery(worker, query), isTrue);
      }
      expect(publicProfileMatchesQuery(worker, 'tutoring'), isFalse);
    });

    test('can restrict worker-side user results to clients', () {
      final client = <String, dynamic>{
        'role': 'client',
        'fullName': 'Juan Dela Cruz',
        'location': 'Guiguinto',
        'description': 'Needs help with household projects.',
      };

      expect(
        publicProfileMatchesQuery(
          client,
          'guiguinto',
          role: PublicProfileRole.client,
        ),
        isTrue,
      );
      expect(
        publicProfileMatchesQuery(
          worker,
          'maria',
          role: PublicProfileRole.client,
        ),
        isFalse,
      );
    });
  });
}
