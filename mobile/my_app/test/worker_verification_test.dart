import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/worker/presentation/models/worker_verification_ui_state.dart';
import 'package:my_app/features/worker/presentation/screens/worker_job_details_screen.dart';
import 'package:my_app/shared/models/app_user.dart';
import 'package:my_app/shared/models/service_request.dart';

void main() {
  group('worker verification state', () {
    test('missing submission offers verification', () {
      final state = WorkerVerificationUiState.resolve(
        profileStatus: VerificationStatus.pending,
        submissionStatus: null,
      );

      expect(state.shouldShowForm, isTrue);
      expect(state.isAwaitingReview, isFalse);
      expect(state.actionLabel, 'Verify account');
      expect(state.canAcceptJobs, isFalse);
    });

    test('pending submission shows review status', () {
      final state = WorkerVerificationUiState.resolve(
        profileStatus: VerificationStatus.pending,
        submissionStatus: VerificationStatus.pending,
      );

      expect(state.shouldShowForm, isFalse);
      expect(state.isAwaitingReview, isTrue);
      expect(state.actionLabel, 'View verification status');
    });

    test('rejected submission offers resubmission', () {
      final state = WorkerVerificationUiState.resolve(
        profileStatus: VerificationStatus.rejected,
        submissionStatus: VerificationStatus.rejected,
      );

      expect(state.shouldShowForm, isTrue);
      expect(state.actionLabel, 'Resubmit verification');
      expect(state.canAcceptJobs, isFalse);
    });

    test('only verified user profile authorizes job acceptance', () {
      final state = WorkerVerificationUiState.resolve(
        profileStatus: VerificationStatus.verified,
        submissionStatus: VerificationStatus.pending,
      );

      expect(state.isVerified, isTrue);
      expect(state.canAcceptJobs, isTrue);
      expect(state.statusLabel, 'Verified');
    });
  });

  testWidgets('unverified worker is prompted to verify on a pending job', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WorkerJobDetailsScreen(
          request: _request,
          worker: _worker(VerificationStatus.pending),
        ),
      ),
    );

    expect(find.text('Verify to accept jobs'), findsOneWidget);
    expect(find.text('Accept request'), findsNothing);
  });

  testWidgets('verified worker retains the accept action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WorkerJobDetailsScreen(
          request: _request,
          worker: _worker(VerificationStatus.verified),
        ),
      ),
    );

    expect(find.text('Accept request'), findsOneWidget);
    expect(find.text('Verify to accept jobs'), findsNothing);
  });
}

const _request = ServiceRequest(
  id: 'request-1',
  clientId: 'client-1',
  clientName: 'Client',
  title: 'Repair sink',
  category: 'Plumbing',
  location: 'Manila',
  description: 'Leaking kitchen sink',
  budget: 500,
  status: ServiceRequestStatus.pending,
);

AppUser _worker(VerificationStatus status) => AppUser(
  id: 'worker-1',
  fullName: 'Worker',
  email: 'worker@example.com',
  role: UserRole.worker,
  verificationStatus: status,
);
