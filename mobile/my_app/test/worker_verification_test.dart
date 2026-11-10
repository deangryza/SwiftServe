import 'dart:io';
import 'dart:async';
import 'helpers/fake_document_review.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/worker/presentation/models/worker_verification_ui_state.dart';
import 'package:my_app/features/worker/presentation/screens/worker_verification_screen.dart';
import 'package:my_app/features/worker/presentation/screens/worker_job_details_screen.dart';
import 'package:my_app/shared/models/app_user.dart';
import 'package:my_app/shared/models/service_request.dart';
import 'package:my_app/shared/repositories/verification_repository.dart';

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
      expect(state.statusLabel, 'Worker access retained');
    });
    test(
      'legacy verified submission cannot override a pending canonical profile',
      () {
        final state = WorkerVerificationUiState.resolve(
          profileStatus: VerificationStatus.pending,
          submissionStatus: VerificationStatus.verified,
        );
        expect(state.isVerified, isFalse);
        expect(state.canAcceptJobs, isFalse);
        expect(
          VerificationStatus.fromWire('APPROVED'),
          VerificationStatus.pending,
        );
      },
    );
  });

  testWidgets('unverified worker is prompted to verify on a pending job', (
    tester,
  ) async {
    const locationChannel = MethodChannel('flutter.baseflow.com/geolocator');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          locationChannel,
          (call) async =>
              call.method == 'isLocationServiceEnabled' ? false : null,
        );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(locationChannel, null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: WorkerJobDetailsScreen(
          request: _request,
          worker: _worker(VerificationStatus.pending),
        ),
      ),
    );

    // The actions sit at the end of a lazily built list.
    await tester.scrollUntilVisible(
      find.text('Verify to apply'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.scrollUntilVisible(find.text('Verify to apply'), 150);
    await tester.pumpAndSettle();
    expect(find.text('Verify to apply'), findsOneWidget);
    expect(find.text('Apply for this request'), findsNothing);
  });

  group('quick verification flow', () {
    late Directory temporaryDirectory;
    late File document;
    late File replacementDocument;
    late File selfie;

    setUp(() {
      temporaryDirectory = Directory.systemTemp.createTempSync(
        'swiftserve-verification-test-',
      );
      document = File('${temporaryDirectory.path}/document.jpg')
        ..writeAsBytesSync(const [1, 2, 3]);
      replacementDocument = File(
        '${temporaryDirectory.path}/replacement-document.jpg',
      )..writeAsBytesSync(const [4, 5, 6]);
      selfie = File('${temporaryDirectory.path}/selfie.jpg')
        ..writeAsBytesSync(const [7, 8, 9]);
    });

    tearDown(() {
      if (temporaryDirectory.existsSync()) {
        temporaryDirectory.deleteSync(recursive: true);
      }
    });

    testWidgets('start asks only for the ID type and consent', (tester) async {
      await _pumpVerification(tester, documentCapture: (_) async => document);

      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(find.text('Verify your identity'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('verification_id_type_Passport')),
      );
      await _start(tester);

      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.text('Scan your Passport'), findsOneWidget);
    });

    testWidgets('start stays disabled until consent is given', (tester) async {
      await _pumpVerification(
        tester,
        documentCapture: (_) async => document,
        consent: false,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('verification_start_button')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('the ID is checked at once and leads straight to the selfie', (
      tester,
    ) async {
      final review = FakeDocumentReview();
      await _pumpVerification(
        tester,
        documentReview: review,
        documentCapture: (_) async => document,
      );
      await _start(tester);
      await _scanId(tester);

      expect(review.uploads, 1);
      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.text('Take a selfie'), findsOneWidget);
      expect(find.text('ID accepted'), findsOneWidget);
    });

    testWidgets('an unusable ID photo is refused before the selfie step', (
      tester,
    ) async {
      final review = FakeDocumentReview(error: 'FACE_NOT_DETECTED');
      var comparisons = 0;
      await _pumpVerification(
        tester,
        documentReview: review,
        documentCapture: (_) async => document,
        selfieCapture: (_) async => selfie,
        submitter:
            ({
              required idType,
              required idNumber,
              required governmentId,
              required facePhoto,
            }) async {
              comparisons++;
              return const FaceVerificationResult(status: 'pending');
            },
      );
      await _start(tester);
      await _scanId(tester);

      expect(review.uploads, 1);
      expect(comparisons, 0);
      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(
        find.textContaining('Please upload a clearer image'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('verification_capture_selfie')),
        findsNothing,
      );
      expect(find.text('Retake ID'), findsOneWidget);
    });

    testWidgets('a connection failure during the ID check can be retried', (
      tester,
    ) async {
      final review = _FlakyReview();
      await _pumpVerification(
        tester,
        documentReview: review,
        documentCapture: (_) async => document,
      );
      await _start(tester);
      await _scanId(tester);

      expect(find.textContaining('Check your connection'), findsOneWidget);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('verification_check_id')),
      );
      await tester.pumpAndSettle();
      expect(review.uploads, 2);
      expect(find.text('Step 3 of 3'), findsOneWidget);
    });

    testWidgets('the selfie is matched without a separate submit step', (
      tester,
    ) async {
      final pending = Completer<FaceVerificationResult>();
      var calls = 0;
      await _pumpVerification(
        tester,
        documentCapture: (_) async => document,
        selfieCapture: (_) async => selfie,
        submitter:
            ({
              required idType,
              required idNumber,
              required governmentId,
              required facePhoto,
            }) {
              calls++;
              expect(idNumber, isEmpty);
              expect(governmentId.path, document.path);
              expect(facePhoto.path, selfie.path);
              return pending.future;
            },
      );
      await _start(tester);
      await _scanId(tester);
      await tester.tap(
        find.byKey(const ValueKey('verification_capture_selfie')),
      );
      await tester.pump();
      await tester.pump();

      // While the match runs there is nothing to tap twice.
      expect(calls, 1);
      expect(find.textContaining('Matching your selfie'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('verification_capture_selfie')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('verification_submit')), findsNothing);
      pending.complete(
        const FaceVerificationResult(
          similarity: 72,
          band: 'borderline',
          status: 'pending',
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        find.byKey(const ValueKey('verification_submission_complete')),
        findsOneWidget,
      );
    });

    for (final role in [UserRole.client, UserRole.worker]) {
      for (final accepted in [false, true]) {
        testWidgets(
          '$role sign-up photos are checked and matched without recapture; accepted=$accepted',
          (tester) async {
            final review = FakeDocumentReview(
              status: accepted
                  ? 'DOCUMENT_ACCEPTED'
                  : 'DOCUMENT_REVIEW_REQUIRED',
            );
            var comparisons = 0;
            await _pumpVerification(
              tester,
              role: role,
              initialDocument: document,
              initialSelfie: selfie,
              documentCapture: (_) async =>
                  throw StateError('Must reuse the sign-up image'),
              selfieCapture: (_) async =>
                  throw StateError('Must reuse the sign-up selfie'),
              documentReview: review,
              submitter:
                  ({
                    required idType,
                    required idNumber,
                    required governmentId,
                    required facePhoto,
                  }) async {
                    comparisons++;
                    expect(governmentId.path, document.path);
                    expect(facePhoto.path, selfie.path);
                    expect(idType, 'National ID');
                    return const FaceVerificationResult(status: 'pending');
                  },
            );
            await _start(tester);

            expect(review.uploads, 1);
            expect(comparisons, accepted ? 1 : 0);
            if (!accepted) {
              // Strict mode: an administrator reviews the ID first.
              expect(find.text('Waiting for ID review'), findsOneWidget);
              review.status = 'DOCUMENT_ACCEPTED';
              await _tapVisible(
                tester,
                find.byKey(const ValueKey('verification_refresh_document')),
              );
              await tester.pumpAndSettle();
              expect(comparisons, 1);
            }
            expect(find.text('Almost done'), findsOneWidget);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }

    testWidgets('changing the ID replaces and deletes the previous photo', (
      tester,
    ) async {
      final deleted = <String>[];
      final review = FakeDocumentReview();
      var documentCaptureCount = 0;
      await _pumpVerification(
        tester,
        documentReview: review,
        documentCapture: (_) async =>
            documentCaptureCount++ == 0 ? document : replacementDocument,
        deleteFile: (file) async => deleted.add(file.path),
      );
      await _start(tester);
      await _scanId(tester);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('verification_retake_id')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('verification_id_accepted')),
        findsOneWidget,
      );
      await _scanId(tester);

      expect(deleted, contains(document.path));
      expect(review.uploads, 2);
      expect(find.text('Step 3 of 3'), findsOneWidget);
    });

    testWidgets('a verified response shows the result and removes the photos', (
      tester,
    ) async {
      final deleted = <String>[];
      await _pumpVerification(
        tester,
        documentCapture: (_) async => document,
        selfieCapture: (_) async => selfie,
        deleteFile: (file) async => deleted.add(file.path),
        submitter:
            ({
              required idType,
              required idNumber,
              required governmentId,
              required facePhoto,
            }) async => const FaceVerificationResult(
              similarity: 92.3,
              confidence: 92.3,
              band: 'strong',
              status: 'verified',
            ),
      );
      await _complete(tester);

      expect(find.text('You are verified'), findsOneWidget);
      expect(find.textContaining('92%'), findsOneWidget);
      expect(deleted, containsAll(<String>[document.path, selfie.path]));
    });

    testWidgets('a match that still needs an administrator is not shown as '
        'verified', (tester) async {
      await _pumpVerification(
        tester,
        documentCapture: (_) async => document,
        selfieCapture: (_) async => selfie,
        submitter:
            ({
              required idType,
              required idNumber,
              required governmentId,
              required facePhoto,
            }) async => const FaceVerificationResult(
              similarity: 92.3,
              band: 'strong',
              status: 'pending',
            ),
      );
      await _complete(tester);

      expect(
        find.byKey(const ValueKey('verification_submission_complete')),
        findsOneWidget,
      );
      expect(find.text('Almost done'), findsOneWidget);
      expect(find.textContaining('administrator'), findsOneWidget);
      expect(find.text('You are verified'), findsNothing);
    });

    testWidgets('mismatch shows the similarity and retakes the selfie', (
      tester,
    ) async {
      final deleted = <String>[];
      var comparisons = 0;
      await _pumpVerification(
        tester,
        documentCapture: (_) async => document,
        selfieCapture: (_) async => selfie,
        deleteFile: (file) async => deleted.add(file.path),
        submitter:
            ({
              required idType,
              required idNumber,
              required governmentId,
              required facePhoto,
            }) async {
              comparisons++;
              throw const FaceVerificationException(
                FaceVerificationFailure.mismatch,
                'The selfie did not match the face on the ID.',
                similarity: 41.2,
              );
            },
      );
      await _complete(tester);

      expect(
        find.byKey(const ValueKey('verification_mismatch')),
        findsOneWidget,
      );
      expect(find.textContaining('41%'), findsOneWidget);
      expect(find.textContaining('remove glasses'), findsOneWidget);
      expect(find.textContaining('hold the ID flat'), findsOneWidget);
      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(deleted, isEmpty);

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('verification_retry_selfie')),
      );
      await tester.pumpAndSettle();
      expect(comparisons, 2);

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('verification_mismatch_retake_id')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 3'), findsOneWidget);
    });

    for (final failure in [
      FaceVerificationFailure.noFace,
      FaceVerificationFailure.quality,
      FaceVerificationFailure.multipleFaces,
    ]) {
      for (final image in VerificationImage.values) {
        testWidgets(
          '${failure.name} in the ${image.name} returns to that capture with guidance',
          (tester) async {
            await _pumpVerification(
              tester,
              documentCapture: (_) async => document,
              selfieCapture: (_) async => selfie,
              submitter:
                  ({
                    required idType,
                    required idNumber,
                    required governmentId,
                    required facePhoto,
                  }) async {
                    throw FaceVerificationException(
                      failure,
                      'Hold the camera steady and retake the photo.',
                      image: image,
                    );
                  },
            );
            await _complete(tester);

            expect(
              find.text(
                image == VerificationImage.document
                    ? 'Step 2 of 3'
                    : 'Step 3 of 3',
              ),
              findsOneWidget,
            );
            expect(
              find.textContaining('Hold the camera steady'),
              findsOneWidget,
            );
            expect(find.text('Almost done'), findsNothing);
            expect(
              find.byKey(const ValueKey('verification_mismatch')),
              findsNothing,
            );
          },
        );
      }
    }

    testWidgets('a network failure keeps both photos and offers a retry', (
      tester,
    ) async {
      final deleted = <String>[];
      var comparisons = 0;
      await _pumpVerification(
        tester,
        documentCapture: (_) async => document,
        selfieCapture: (_) async => selfie,
        deleteFile: (file) async => deleted.add(file.path),
        submitter:
            ({
              required idType,
              required idNumber,
              required governmentId,
              required facePhoto,
            }) async {
              if (comparisons++ == 0) {
                throw const FaceVerificationException(
                  FaceVerificationFailure.network,
                  'Check your connection and try again.',
                );
              }
              return const FaceVerificationResult(status: 'pending');
            },
      );
      await _complete(tester);

      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.text('Check your connection and try again.'), findsOneWidget);
      expect(deleted, isEmpty);

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('verification_submit')),
      );
      await tester.pumpAndSettle();
      expect(comparisons, 2);
      expect(find.text('Almost done'), findsOneWidget);
    });

    testWidgets('status pages bypass the wizard and rejection can restart', (
      tester,
    ) async {
      await _pumpVerification(
        tester,
        submissionStatus: VerificationStatus.pending,
        documentCapture: (_) async => document,
        selfieCapture: (_) async => selfie,
      );
      expect(find.text('Verification under review'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('verification_start_button')),
        findsNothing,
      );

      await _pumpVerification(
        tester,
        profileStatus: VerificationStatus.verified,
        documentCapture: (_) async => document,
        selfieCapture: (_) async => selfie,
      );
      expect(find.text('Worker access retained'), findsOneWidget);

      await _pumpVerification(
        tester,
        profileStatus: VerificationStatus.rejected,
        submissionStatus: VerificationStatus.rejected,
        documentCapture: (_) async => document,
        selfieCapture: (_) async => selfie,
      );
      expect(find.text('Verification was not approved'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('verification_resubmit_button')),
      );
      await tester.pumpAndSettle();
      // Restarting begins again at the ID type and consent.
      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('verification_start_button')),
        findsOneWidget,
      );
    });

    testWidgets('sign-out confirmation discards captured temporary files', (
      tester,
    ) async {
      final deleted = <String>[];
      var signedOut = false;
      await _pumpVerification(
        tester,
        documentCapture: (_) async => document,
        selfieCapture: (_) async => selfie,
        deleteFile: (file) async => deleted.add(file.path),
        signOut: () async => signedOut = true,
      );
      await _start(tester);
      await _scanId(tester);

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
        selfieCapture: (_) async => selfie,
      );
      await _start(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Discard verification?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 3'), findsOneWidget);
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
        selfieCapture: (_) async => selfie,
        textScale: 2,
      );
      expect(tester.takeException(), isNull, reason: 'preparation layout');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('verification_start_button')),
        200,
      );
      await tester.tap(find.byKey(const ValueKey('verification_start_button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'ID step layout');
      await _scanId(tester);

      expect(find.byType(Scrollable), findsWidgets);
      expect(tester.takeException(), isNull, reason: 'selfie step layout');
    });
  });
}

/// Fails the first upload like a dropped connection, then accepts.
class _FlakyReview extends FakeDocumentReview {
  @override
  Future<Map<String, dynamic>> submit(
    File file,
    String type,
    Map<String, dynamic> previous,
  ) async {
    if (uploads == 0) {
      uploads++;
      throw const SocketException('offline');
    }
    return super.submit(file, type, previous);
  }
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
  FakeDocumentReview? documentReview,
  UserRole role = UserRole.worker,
  File? initialDocument,
  File? initialSelfie,
  bool consent = true,
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
        documentReview: documentReview ?? FakeDocumentReview(),
        key: ValueKey('$profileStatus-$submissionStatus'),
        profile: AppUser(
          id: 'worker-1',
          fullName: 'Synthetic User',
          email: 'synthetic@example.test',
          role: role,
          verificationStatus: profileStatus,
        ),
        initialDocument: initialDocument,
        initialSelfie: initialSelfie,
        statusStream: Stream<VerificationStatus?>.value(submissionStatus),
        documentCaptureLauncher: documentCapture,
        selfieCaptureLauncher: selfieCapture ?? (_) async => null,
        submitter:
            submitter ??
            ({
              required idType,
              required idNumber,
              required governmentId,
              required facePhoto,
            }) async => const FaceVerificationResult(
              similarity: 72,
              band: 'borderline',
              status: 'pending',
            ),
        deleteFile: deleteFile ?? (file) async {},
        signOut: signOut ?? () async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  final consentTile = find.byKey(const ValueKey('verification-consent'));
  if (consent && consentTile.evaluate().isNotEmpty) {
    final checkbox = find.descendant(
      of: consentTile,
      matching: find.byType(Checkbox),
    );
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
  }
}

Future<void> _start(WidgetTester tester) async {
  await _tapVisible(
    tester,
    find.byKey(const ValueKey('verification_start_button')),
  );
  await tester.pumpAndSettle();
}

Future<void> _scanId(WidgetTester tester) async {
  await _tapVisible(
    tester,
    find.byKey(const ValueKey('verification_capture_id')),
  );
  await tester.pumpAndSettle();
}

/// Start, scan the ID and take the selfie; the match then runs on its own.
Future<void> _complete(WidgetTester tester) async {
  await _start(tester);
  await _scanId(tester);
  await _tapVisible(
    tester,
    find.byKey(const ValueKey('verification_capture_selfie')),
  );
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
