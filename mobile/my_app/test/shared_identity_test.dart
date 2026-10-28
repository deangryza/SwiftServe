import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/worker/presentation/models/worker_verification_ui_state.dart';
import 'package:my_app/features/worker/presentation/screens/worker_verification_screen.dart';
import 'package:my_app/shared/models/app_user.dart';
import 'package:my_app/shared/repositories/verification_repository.dart';

AppUser _profile(String status) => AppUser.fromMap('dual', {
  'role': 'worker',
  'roles': ['client', 'worker'],
  'verificationStatus': status,
});

void main() {
  for (final status in [
    'pending',
    'rejected',
    'expired',
    'revoked',
    'not_required',
  ]) {
    test(
      '$status never grants eligibility merely from a submission or client posting access',
      () {
        final profile = _profile(status);
        expect(
          WorkerVerificationUiState.resolve(
            profileStatus: profile.verificationStatus,
            submissionStatus: VerificationStatus.verified,
          ).canAcceptJobs,
          isFalse,
        );
      },
    );
  }

  testWidgets(
    'verification screen follows live canonical approval and revocation without reopening',
    (tester) async {
      final profiles = StreamController<AppUser?>.broadcast();
      addTearDown(profiles.close);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkerVerificationScreen(
            profile: _profile('pending'),
            profileStream: profiles.stream,
            statusStream: Stream.value(null),
            submitter:
                ({
                  required idType,
                  required idNumber,
                  required governmentId,
                  required facePhoto,
                }) async => const FaceVerificationResult(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('verification_verified_status')),
        findsNothing,
      );
      profiles.add(_profile('verified'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('verification_verified_status')),
        findsOneWidget,
      );
      profiles.add(_profile('revoked'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('verification_verified_status')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(profiles.hasListener, isFalse);
    },
  );
}
