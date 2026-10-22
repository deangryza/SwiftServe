import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_app/features/client/presentation/screens/client_home_screen.dart';
import 'package:my_app/shared/models/app_user.dart';
import 'package:my_app/shared/services/api_service.dart';
import 'package:my_app/shared/services/profile_draft_store.dart';
import 'package:my_app/shared/widgets/profile_avatar.dart';

void main() {
  testWidgets(
    'profile avatar displays saved image and tolerates missing photos',
    (tester) async {
      const photo =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j6aQAAAAASUVORK5CYII=';
      await tester.pumpWidget(
        const MaterialApp(home: ProfileAvatar(photoBase64: photo)),
      );
      expect(find.byType(Image), findsOneWidget);
      await tester.pumpWidget(
        const MaterialApp(home: ProfileAvatar(photoBase64: 'invalid')),
      );
      expect(find.byIcon(Icons.person), findsOneWidget);
    },
  );

  testWidgets('recent profiles show a charcoal new-member badge', (
    tester,
  ) async {
    final joinedAt = DateTime.now().subtract(const Duration(days: 7));
    await tester.pumpWidget(
      MaterialApp(home: ProfileAvatar(joinedAt: joinedAt)),
    );
    expect(find.byKey(const ValueKey('recent-member-badge')), findsOneWidget);
    final badge = tester.widget<Container>(
      find.byKey(const ValueKey('recent-member-badge')),
    );
    final decoration = badge.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xFF242424));

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileAvatar(
          joinedAt: DateTime.now().subtract(const Duration(days: 15)),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('recent-member-badge')), findsNothing);
  });

  test('saved draft retains its photo and sends it on profile retry', () async {
    SharedPreferences.setMockInitialValues({});
    const draft = ProfileDraft(
      fullName: 'Alice Santos',
      email: 'alice@example.com',
      phoneNumber: '',
      address: '',
      role: 'client',
      photoBase64: 'photo-data',
    );
    await ProfileDraftStore().save(draft);
    final restored = (await ProfileDraftStore().load())!;
    final api = ApiService(
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['fullName'], 'Alice Santos');
        expect(body['photoBase64'], 'photo-data');
        return http.Response('{}', 201);
      }),
    );
    await api.createUserProfile(
      idToken: 'token',
      fullName: restored.fullName,
      email: restored.email,
      phoneNumber: restored.phoneNumber,
      address: restored.address,
      role: restored.role,
      photoBase64: restored.photoBase64,
    );
  });

  testWidgets('dashboard displays and updates the saved user name', (
    tester,
  ) async {
    AppUser profile(String name) => AppUser(
      id: 'alice',
      fullName: name,
      email: 'alice@example.com',
      role: UserRole.client,
      verificationStatus: VerificationStatus.pending,
    );
    await tester.pumpWidget(
      MaterialApp(home: ClientHomeScreen(profile: profile('Alice Santos'))),
    );
    expect(find.text('Hello 👋'), findsOneWidget);
    expect(find.text('Alice Santos'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(home: ClientHomeScreen(profile: profile('Alice Cruz'))),
    );
    expect(find.text('Alice Cruz'), findsOneWidget);
    expect(find.text('Alice Santos'), findsNothing);
    expect(find.text('Most Booked Services'), findsOneWidget);
    expect(find.text('Other services'), findsOneWidget);
    expect(find.text('Post what you need help'), findsNothing);
    expect(find.text('Bookings'), findsOneWidget);
    expect(find.text('History'), findsNothing);
  });
}
