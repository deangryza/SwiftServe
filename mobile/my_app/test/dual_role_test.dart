import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/models/app_user.dart';
import 'package:my_app/shared/screens/public_profile_screen.dart';
import 'package:my_app/shared/screens/swiftserve_settings_screen.dart';

void main() {
  group('AppUser roles', () {
    test('older accounts fall back to their single role', () {
      final user = AppUser.fromMap('u1', {'role': 'worker'});
      expect(user.roles, [UserRole.worker]);
      expect(user.hasRole(UserRole.client), isFalse);
      expect(user.otherRole, UserRole.client);
    });

    test('dual accounts list both roles and keep the active one', () {
      final user = AppUser.fromMap('u2', {
        'role': 'worker',
        'roles': ['client', 'worker'],
      });
      expect(user.role, UserRole.worker);
      expect(user.hasRole(UserRole.client), isTrue);
      expect(user.hasRole(UserRole.worker), isTrue);
    });

    test('the active role is always included', () {
      final user = AppUser.fromMap('u3', {
        'role': 'worker',
        'roles': ['client'],
      });
      expect(user.hasRole(UserRole.worker), isTrue);
    });
  });

  test('dual-role public profiles match both role filters', () {
    final profile = <String, dynamic>{
      'role': 'client',
      'roles': ['client', 'worker'],
      'fullName': 'Dual User',
    };
    expect(profileHasRole(profile, 'worker'), isTrue);
    expect(
      publicProfileMatchesQuery(
        profile,
        'dual',
        role: PublicProfileRole.worker,
      ),
      isTrue,
    );
    expect(
      publicProfileMatchesQuery(
        profile,
        'dual',
        role: PublicProfileRole.client,
      ),
      isTrue,
    );
    expect(profileHasRole({'role': 'client'}, 'worker'), isFalse);
  });

  group('settings role tile', () {
    Future<void> pumpSettings(WidgetTester tester, AppUser? profile) =>
        tester.pumpWidget(
          MaterialApp(
            home: SwiftServeSettingsScreen(
              darkModeTitle: 'Dark mode',
              darkModeSubtitle: 'Test',
              darkModeToggleKey: const ValueKey('dark'),
              profile: profile,
            ),
          ),
        );

    testWidgets('offers to become a worker for client-only accounts', (
      tester,
    ) async {
      await pumpSettings(tester, AppUser.fromMap('c', {'role': 'client'}));
      expect(find.text('Become a Worker'), findsOneWidget);
    });

    testWidgets('offers a direct switch when both roles exist', (tester) async {
      await pumpSettings(
        tester,
        AppUser.fromMap('d', {
          'role': 'client',
          'roles': ['client', 'worker'],
        }),
      );
      expect(find.text('Switch to Worker'), findsOneWidget);

      await pumpSettings(
        tester,
        AppUser.fromMap('d', {
          'role': 'worker',
          'roles': ['client', 'worker'],
        }),
      );
      expect(find.text('Switch to Client'), findsOneWidget);
    });

    testWidgets('lets worker-only accounts add the client role', (
      tester,
    ) async {
      await pumpSettings(tester, AppUser.fromMap('w', {'role': 'worker'}));
      expect(find.text('Also hire as a Client'), findsOneWidget);
    });

    testWidgets('hides the switch without a profile or for admins', (
      tester,
    ) async {
      await pumpSettings(tester, null);
      expect(find.byKey(const ValueKey('settings-switch-role')), findsNothing);
      await pumpSettings(tester, AppUser.fromMap('a', {'role': 'admin'}));
      expect(find.byKey(const ValueKey('settings-switch-role')), findsNothing);
      expect(find.text('Log out'), findsOneWidget);
    });
  });
}
