import 'dart:io';
import 'helpers/fake_document_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/models/app_user.dart';
import 'package:my_app/shared/models/verification_evidence.dart';
import 'package:my_app/shared/widgets/verification_evidence_panel.dart';
import 'package:my_app/shared/repositories/verification_repository.dart';
import 'package:my_app/features/worker/presentation/screens/worker_verification_screen.dart';

void main() {
  test(
    'synthetic QR format validation is strict and never accepts a government payload',
    () {
      expect(DemoIdentityQr.valid(DemoIdentityQr.sample), isTrue);
      for (final value in [
        '',
        'PHILSYS:REAL',
        'https://example.test/id',
        '${DemoIdentityQr.sample}\n',
        'SWIFTSERVE-DEMO:2:SYNTHETIC-001',
        'x' * 10000,
      ]) {
        expect(DemoIdentityQr.valid(value), isFalse);
      }
    },
  );
  test(
    'face and worker approval never imply official government authentication; mock wins',
    () {
      final faceOnly = VerificationEvidence(
        data: {
          'face': {'status': 'MATCH'},
          'workerDecision': {'eligible': false},
        },
      );
      expect(faceOnly.face, 'FACE MATCHED');
      expect(faceOnly.government, contains('NOT OFFICIALLY VERIFIED'));
      expect(faceOnly.eligibility, contains('PENDING'));
      final mock = VerificationEvidence(
        data: {
          'providerType': 'MOCK',
          'workerDecision': {'eligible': true, 'officiallyVerified': true},
        },
      );
      expect(mock.government, contains('NOT OFFICIALLY VERIFIED'));
      expect(mock.eligibility, contains('NO WORKER PRIVILEGES'));
      expect(
        const VerificationEvidence(
          requester: true,
          legacyAccess: true,
        ).eligibility,
        'ACCOUNT APPROVAL RECORDED',
      );
    },
  );
  testWidgets(
    'DEMO QR simulated scan shows valid and invalid states without claiming authentication',
    (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DemoQrCheck(onResult: (value) => result = value),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('demo-qr-valid')));
      await tester.pumpAndSettle();
      expect(result, 'DEMO QR FORMAT VALID');
      await tester.tap(find.byKey(const ValueKey('demo-qr-invalid')));
      await tester.pumpAndSettle();
      expect(result, 'DEMO QR FORMAT INVALID');
      expect(find.textContaining('No camera decoding'), findsOneWidget);
    },
  );
  for (final role in [UserRole.client, UserRole.worker]) {
    testWidgets(
      '${role.name} uses shared consent, capture and independent result screen',
      (tester) async {
        final profile = AppUser(
          id: 'synthetic',
          fullName: 'Synthetic User',
          email: 'synthetic@example.test',
          role: role,
          verificationStatus: VerificationStatus.pending,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: WorkerVerificationScreen(
              documentReview: FakeDocumentReview(),
              profile: profile,
              statusStream: Stream.value(null),
              documentCaptureLauncher: (_) async => File('synthetic-id.png'),
              selfieCaptureLauncher: (_) async => File('synthetic-selfie.png'),
              deleteFile: (_) async {},
              signOut: () async {},
              submitter:
                  ({
                    required idType,
                    required idNumber,
                    required governmentId,
                    required facePhoto,
                  }) async => const FaceVerificationResult(
                    similarity: 90,
                    band: 'strong',
                    status: 'pending',
                    evidence: {
                      'faceResult': {'status': 'MATCH'},
                      'workerDecision': {'eligible': false},
                    },
                  ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final start = find.byKey(const ValueKey('verification_start_button'));
        expect(tester.widget<FilledButton>(start).onPressed, isNull);
        final consent = find.byKey(const ValueKey('verification-consent'));
        await tester.ensureVisible(consent);
        await tester.tap(consent);
        await tester.pumpAndSettle();
        await tester.ensureVisible(start);
        await tester.tap(start);
        await tester.pumpAndSettle();
        // No ID number and no submit button: the ID is checked on capture
        // and the match runs as soon as the selfie is taken.
        expect(find.byType(TextFormField), findsNothing);
        await tester.tap(find.byKey(const ValueKey('verification_capture_id')));
        await tester.pumpAndSettle();
        final selfie = find.byKey(
          const ValueKey('verification_capture_selfie'),
        );
        await tester.ensureVisible(selfie);
        await tester.tap(selfie);
        await tester.pumpAndSettle();
        expect(find.text('FACE MATCHED'), findsOneWidget);
        expect(find.textContaining('PSA NOT INTEGRATED'), findsOneWidget);
        expect(
          find.text(
            role == UserRole.client
                ? 'ACCOUNT APPROVAL PENDING'
                : 'WORKER APPROVAL PENDING / BLOCKED',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('evidence panel supports narrow screens and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: VerificationEvidencePanel(
              evidence: VerificationEvidence(data: {'providerType': 'MOCK'}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
