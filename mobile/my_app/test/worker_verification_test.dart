import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/worker/presentation/models/worker_verification_ui_state.dart';
import 'package:my_app/features/worker/presentation/screens/worker_verification_screen.dart';
import 'package:my_app/features/worker/presentation/screens/worker_job_details_screen.dart';
import 'package:my_app/shared/models/app_user.dart';
import 'package:my_app/shared/models/service_request.dart';
import 'package:my_app/shared/repositories/verification_repository.dart';

// TODO(face-verification): ID-only expectations while the face-match bypass
// is active. Restore selfie steps, "Step X of 4" and mismatch coverage to
// re-enable face verification.
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

  group('guided verification onboarding', () {
    late Directory temporaryDirectory;
    late File document;
    late File replacementDocument;

    setUp(() {
      temporaryDirectory = Directory.systemTemp.createTempSync(
        'swiftserve-verification-test-',
      );
      document = File('${temporaryDirectory.path}/document.jpg')
        ..writeAsBytesSync(const [1, 2, 3]);
      replacementDocument = File(
        '${temporaryDirectory.path}/replacement-document.jpg',
      )..writeAsBytesSync(const [4, 5, 6]);
    });

    tearDown(() {
      if (temporaryDirectory.existsSync()) {
        temporaryDirectory.deleteSync(recursive: true);
      }
    });

    testWidgets('requires an ID number before advancing', (tester) async {
      await _pumpVerification(
        tester,
        documentCapture: (_) async => document,
      );

      expect(find.text('Verify your identity'), findsOneWidget);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('verification_start_button')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('verification_continue')));
      await tester.pump();

      expect(find.text('ID number is required'), findsOneWidget);
      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(find.text('Photograph your government ID'), findsNothing);
    });

    testWidgets('captures auto-advance and review masks the ID number', (
      tester,
    ) async {
      await _pumpVerification(
        tester,
        documentCapture: (_) async => document,
      );

      await _reachReview(tester, idNumber: '123456789012');

      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.text('Review and submit'), findsOneWidget);
      expect(find.text('Number: ••••••••9012'), findsOneWidget);
      expect(find.textContaining('123456789012'), findsNothing);
      expect(find.text('Government ID'), findsOneWidget);
      expect(find.text('Live selfie'), findsNothing);
    });

    testWidgets('retake replaces and deletes the previous document', (
      tester,
    ) async {
      final deleted = <String>[];
      var documentCaptureCount = 0;
      await _pumpVerification(
        tester,
        documentCapture: (_) async =>
            documentCaptureCount++ == 0 ? document : replacementDocument,
        deleteFile: (file) async => deleted.add(file.path),
      );
      await _reachReview(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('verification_retake_id')),
      );
      await tester.tap(find.byKey(const ValueKey('verification_retake_id')));
      await tester.pumpAndSettle();

      expect(find.text('Review and submit'), findsOneWidget);
      expect(deleted, contains(document.path));
    });

    testWidgets('successful ID-only submission cleans files and shows pending view', (
      tester,
    ) async {
      final deleted = <String>[];
      await _pumpVerification(
        tester,
        documentCapture: (_) async => document,
        deleteFile: (file) async => deleted.add(file.path),
      );
      await _reachReview(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('verification_submit')),
      );
      await tester.tap(find.byKey(const ValueKey('verification_submit')));
      await tester.pumpAndSettle();

      expect(find.text('Submitted for review'), findsOneWidget);
      expect(deleted, containsAll(<String>[document.path]));
    });

    testWidgets('network failure keeps the complete review draft', (
      tester,
    ) async {
      final deleted = <String>[];
      await _pumpVerification(
        tester,
        documentCapture: (_) async => document,
        deleteFile: (file) async => deleted.add(file.path),
        submitter:
            ({
              required idType,
              required idNumber,
              required governmentId,
              facePhoto,
            }) async {
              throw const FaceVerificationException(
                FaceVerificationFailure.network,
                'Check your connection and try again.',
              );
            },
      );
      await _reachReview(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('verification_submit')),
      );
      await tester.tap(find.byKey(const ValueKey('verification_submit')));
      await tester.pumpAndSettle();

      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.text('Check your connection and try again.'), findsOneWidget);
      expect(find.text('Government ID'), findsOneWidget);
      expect(find.text('Live selfie'), findsNothing);
      expect(deleted, isEmpty);
    });

    testWidgets('status pages bypass the wizard and rejection can restart', (
      tester,
    ) async {
      await _pumpVerification(
        tester,
        submissionStatus: VerificationStatus.pending,
        documentCapture: (_) async => document,
      );
      expect(find.text('Verification under review'), findsOneWidget);
      expect(find.text('Start verification'), findsNothing);

      await _pumpVerification(
        tester,
        profileStatus: VerificationStatus.verified,
        documentCapture: (_) async => document,
      );
      expect(find.text('Verification complete'), findsOneWidget);

      await _pumpVerification(
        tester,
        profileStatus: VerificationStatus.rejected,
        submissionStatus: VerificationStatus.rejected,
        documentCapture: (_) async => document,
      );
      expect(find.text('Verification was not approved'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('verification_resubmit_button')),
      );
      await tester.pump();
      expect(find.text('Step 1 of 3'), findsOneWidget);
    });

    testWidgets('sign-out confirmation discards captured temporary files', (
      tester,
    ) async {
      final deleted = <String>[];
      var signedOut = false;
      await _pumpVerification(
        tester,
        documentCapture: (_) async => document,
        deleteFile: (file) async => deleted.add(file.path),
        signOut: () async => signedOut = true,
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('verification_start_button')),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('verification_id_number')),
        '12345678',
      );
      await tester.tap(find.byKey(const ValueKey('verification_continue')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('verification_capture_id')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Discard verification?'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('verification_confirm_discard')),
      );
      await tester.pumpAndSettle();

      expect(signedOut, isTrue);
      expect(deleted, contains(document.path));
    });

    testWidgets('system back asks before discarding an in-memory draft', (
      tester,
    ) async {
      await _pumpVerification(
        tester,
        documentCapture: (_) async => document,
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('verification_start_button')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('verification_id_number')),
        '12345678',
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Discard verification?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('verification_id_number')),
            )
            .controller!
            .text,
        '12345678',
      );
    });

    testWidgets('wizard remains scrollable on a narrow large-text display', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpVerification(
        tester,
        documentCapture: (_) async => document,
        textScale: 2,
      );
      expect(tester.takeException(), isNull, reason: 'preparation layout');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('verification_start_button')),
        200,
      );
      await tester.tap(find.byKey(const ValueKey('verification_start_button')));
      await tester.pump();

      expect(find.byType(Scrollable), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _pumpVerification(
  WidgetTester tester, {
  VerificationStatus profileStatus = VerificationStatus.pending,
  VerificationStatus? submissionStatus,
  required Future<File?> Function(BuildContext) documentCapture,
  Future<File?> Function(BuildContext)? selfieCapture,
  VerificationSubmitter? submitter,
  VerificationFileDeleter? deleteFile,
  Future<void> Function()? signOut,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: WorkerVerificationScreen(
        key: ValueKey('$profileStatus-$submissionStatus'),
        profile: _worker(profileStatus),
        statusStream: Stream<VerificationStatus?>.value(submissionStatus),
        documentCaptureLauncher: documentCapture,
        // ignore: deprecated_member_use_from_same_package
        selfieCaptureLauncher: selfieCapture ?? (_) async => null,
        submitter:
            submitter ??
            ({
              required idType,
              required idNumber,
              required governmentId,
              facePhoto,
            }) async => const FaceVerificationResult(),
        deleteFile: deleteFile ?? (file) async {},
        signOut: signOut ?? () async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _reachReview(
  WidgetTester tester, {
  String idNumber = '123456789',
}) async {
  await _tapVisible(
    tester,
    find.byKey(const ValueKey('verification_start_button')),
  );
  await tester.pump();
  await tester.enterText(
    find.byKey(const ValueKey('verification_id_number')),
    idNumber,
  );
  await tester.tap(find.byKey(const ValueKey('verification_continue')));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('verification_capture_id')));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
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
