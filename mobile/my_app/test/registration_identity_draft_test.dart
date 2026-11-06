import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/domain/registration_identity_draft.dart';
import 'package:my_app/features/auth/presentation/widgets/registration_identity_capture.dart';
import 'package:my_app/features/worker/domain/capture_quality.dart';
import 'package:my_app/features/worker/presentation/screens/national_id_capture_screen.dart';
import 'package:my_app/features/worker/presentation/screens/face_capture_screens.dart';

class LockedTemporaryFile extends Fake implements File {
  LockedTemporaryFile(this.failures, {this.code = 32});
  final int failures, code;
  int attempts = 0;
  @override
  Future<File> delete({bool recursive = false}) async {
    if (++attempts <= failures) {
      throw FileSystemException(
        'Synthetic temporary-file lock',
        'synthetic-only',
        OSError('synthetic', code),
      );
    }
    return this;
  }
}

void main() {
  late Directory directory;
  late RegistrationIdentityDraft draft;
  var sequence = 0;
  Future<File>
  photo() => File('${directory.path}/${sequence++}.png').writeAsBytes(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
  );
  Future<void> drainImages(WidgetTester tester) async {
    // FileImage's stat/open/read stages cross the test's fake/real async zones.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> valid(File _, bool _) async {}
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'swiftserve-registration-test-',
    );
    draft = RegistrationIdentityDraft();
  });
  tearDown(() async {
    draft.dispose();
    // Only test-created synthetic files, never a gallery or user directory.
    await Future<void>.delayed(Duration.zero);
    for (final file in directory.listSync().whereType<File>()) {
      if (await file.exists()) await file.delete();
    }
    await directory.delete();
  });
  test('invalid front/back are discarded and can be replaced', () async {
    for (final front in [true, false]) {
      final invalid = await photo();
      await draft.acceptId(
        invalid,
        isFront: front,
        validate: (_, _) async {
          throw CaptureQualityException(
            front ? 'NO_FACE' : 'NO_QR',
            'Retake photo',
          );
        },
      );
      expect(await invalid.exists(), false);
      expect(draft.hasId, false);
      expect(draft.error, 'Retake photo');
      await draft.acceptId(await photo(), isFront: front, validate: valid);
    }
    expect(draft.hasId, true);
    expect(draft.error, null);
  });
  test(
    'owned temporary-file deletion retries a brief preview sharing lock',
    () async {
      final locked = LockedTemporaryFile(2);
      await RegistrationIdentityDraft.deleteTemporary(locked);
      expect(locked.attempts, 3);
    },
  );
  test(
    'temporary cleanup retries are bounded and other file errors are not retried',
    () async {
      final locked = LockedTemporaryFile(10);
      await RegistrationIdentityDraft.deleteTemporary(locked);
      expect(locked.attempts, 4);
      final denied = LockedTemporaryFile(10, code: 13);
      await RegistrationIdentityDraft.deleteTemporary(denied);
      expect(denied.attempts, 1);
    },
  );
  test(
    'invalid replacement retains last valid image without accepting invalid bytes',
    () async {
      final original = await photo();
      await draft.acceptId(original, isFront: true, validate: valid);
      final invalid = await photo();
      await draft.acceptId(
        invalid,
        isFront: true,
        validate: (_, _) async =>
            throw const CaptureQualityException('NO_FACE', 'No face'),
      );
      expect(draft.front, original);
      expect(await original.exists(), true);
      expect(await invalid.exists(), false);
    },
  );
  test(
    'selfie requires both sides; ID replacement invalidates prior selfie',
    () async {
      final premature = await photo();
      await draft.acceptSelfie(premature);
      expect(draft.selfie, null);
      expect(await premature.exists(), false);
      await draft.acceptId(await photo(), isFront: true, validate: valid);
      await draft.acceptId(await photo(), isFront: false, validate: valid);
      final selfie = await photo();
      await draft.acceptSelfie(selfie);
      expect(draft.selfie, selfie);
      await draft.acceptId(await photo(), isFront: false, validate: valid);
      expect(draft.selfie, null);
      expect(await selfie.exists(), false);
    },
  );
  test(
    'Skip ID clears partial evidence; Skip selfie keeps validated ID',
    () async {
      await draft.acceptId(await photo(), isFront: true, validate: valid);
      await draft.acceptId(await photo(), isFront: false, validate: valid);
      await draft.acceptSelfie(await photo());
      await draft.skip(id: false);
      expect(draft.hasId, true);
      expect(draft.selfie, null);
      await draft.skip(id: true);
      expect(draft.hasProgress, false);
    },
  );
  test(
    'duplicate selection and skip cannot race a validation operation',
    () async {
      final pending = Completer<void>();
      final accepted = await photo();
      final first = draft.acceptId(
        accepted,
        isFront: true,
        validate: (_, _) => pending.future,
      );
      final duplicate = await photo();
      await draft.acceptId(duplicate, isFront: true, validate: valid);
      await draft.skip(id: true);
      expect(await duplicate.exists(), false);
      expect(draft.busy, true);
      pending.complete();
      await first;
      expect(draft.front, accepted);
    },
  );
  test(
    'handoff transfers front/selfie ownership exactly once and removes local QR',
    () async {
      await draft.acceptId(await photo(), isFront: true, validate: valid);
      final back = await photo();
      await draft.acceptId(back, isFront: false, validate: valid);
      await draft.acceptSelfie(await photo());
      final files = await draft.takeForVerification();
      expect(files, isNotNull);
      expect(await back.exists(), false);
      expect(await files!.document.exists(), true);
      expect(await files.selfie!.exists(), true);
      expect(await draft.takeForVerification(), null);
      expect(draft.hasProgress, false);
    },
  );
  testWidgets('upload cards request consent, cancel keeps evidence empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RegistrationIdentityCapture(draft: draft)),
      ),
    );
    for (final side in ['front', 'back']) {
      await tester.tap(find.byKey(ValueKey('registration-$side')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Take photo'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('registration-id-gallery')));
      // The upload progress indicator intentionally animates behind consent.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Allow photo selection?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(draft.hasProgress, false);
      expect(draft.capturing, false);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'front and back open the existing camera with the correct side; cancellation preserves photos',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final name in [
        'plugins.flutter.io/camera',
        'google_mlkit_face_detector',
        'google_mlkit_barcode_scanning',
      ]) {
        messenger.setMockMethodCallHandler(
          MethodChannel(name),
          (_) async => [],
        );
      }
      addTearDown(() {
        for (final name in [
          'plugins.flutter.io/camera',
          'google_mlkit_face_detector',
          'google_mlkit_barcode_scanning',
        ]) {
          messenger.setMockMethodCallHandler(MethodChannel(name), null);
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RegistrationIdentityCapture(draft: draft),
            ),
          ),
        ),
      );
      for (final front in [true, false]) {
        await tester.tap(
          find.byKey(ValueKey('registration-${front ? 'front' : 'back'}')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(find.byKey(const ValueKey('registration-id-camera')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final capture = tester.widget<NationalIdCaptureScreen>(
          find.byType(NationalIdCaptureScreen),
        );
        expect(capture.frontSide, front);
        expect(
          find.text(front ? 'Front of your ID' : 'Back of your ID'),
          findsOneWidget,
        );
        expect(find.text('Retake front'), findsNothing);
        await tester.tap(find.byTooltip('Cancel capture'));
        await tester.pumpAndSettle();
        expect(draft.hasProgress, false);
        expect(draft.capturing, false);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'both accepted photos appear in their own frame and replacements update the preview',
    (tester) async {
      await tester.runAsync(() async {
        await draft.acceptId(await photo(), isFront: true, validate: valid);
        await draft.acceptId(await photo(), isFront: false, validate: valid);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RegistrationIdentityCapture(draft: draft),
            ),
          ),
        ),
      );
      String path(String side) {
        final provider = tester
            .widget<Image>(find.byKey(ValueKey('registration-$side-preview')))
            .image;
        final original = provider is ResizeImage
            ? provider.imageProvider
            : provider;
        return (original as FileImage).file.path;
      }

      expect(path('front'), draft.front!.path);
      expect(path('back'), draft.back!.path);
      await drainImages(tester);
      final previous = draft.front!.path;
      await tester.runAsync(
        () async =>
            draft.acceptId(await photo(), isFront: true, validate: valid),
      );
      await tester.pump();
      expect(path('front'), draft.front!.path);
      expect(path('front'), isNot(previous));
      expect(find.text('Photo accepted · Tap to replace'), findsNWidgets(2));
      await drainImages(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Take selfie opens the existing SelfieLivenessScreen and cancellation allows retry',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/camera'),
        (_) async => [],
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('google_mlkit_face_detector'),
        (_) async => null,
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/camera'),
          null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('google_mlkit_face_detector'),
          null,
        );
      });
      await tester.runAsync(() async {
        await draft.acceptId(await photo(), isFront: true, validate: valid);
        await draft.acceptId(await photo(), isFront: false, validate: valid);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RegistrationIdentityCapture(draft: draft, face: true),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('registration-selfie')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(SelfieLivenessScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(SelfieLivenessScreen))).pop();
      await tester.pumpAndSettle();
      expect(draft.selfie, null);
      expect(draft.hasId, true);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('registration-selfie')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'face screen requires accepted ID and never reports a face match from a captured selfie',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RegistrationIdentityCapture(draft: draft, face: true),
          ),
        ),
      );
      FilledButton button() => tester.widget<FilledButton>(
        find.byKey(const ValueKey('registration-selfie')),
      );
      expect(button().onPressed, isNotNull);
      expect(find.text('Add ID photos first'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('registration-selfie')));
      await tester.pump();
      expect(
        find.textContaining('Both ID photos must be accepted first:'),
        findsOneWidget,
      );
      expect(find.byType(SelfieLivenessScreen), findsNothing);
      await tester.runAsync(() async {
        await draft.acceptId(await photo(), isFront: true, validate: valid);
        await draft.acceptId(await photo(), isFront: false, validate: valid);
      });
      await tester.pump();
      expect(button().onPressed, isNotNull);
      expect(find.text('Take selfie'), findsOneWidget);
      await tester.runAsync(() async => draft.acceptSelfie(await photo()));
      await tester.pump();
      expect(
        find.text('Selfie captured. Face comparison has not run yet.'),
        findsOneWidget,
      );
      expect(find.text('Retake selfie'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'missing or incomplete ID offers an actionable return instead of a disabled selfie button',
    (tester) async {
      var returnsToId = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RegistrationIdentityCapture(
              draft: draft,
              face: true,
              onRequestId: () => returnsToId++,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('registration-selfie')));
      expect(returnsToId, 1);
      await tester.runAsync(
        () async =>
            draft.acceptId(await photo(), isFront: true, validate: valid),
      );
      await tester.pump();
      expect(find.text('Add ID photos first'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('registration-selfie')));
      expect(returnsToId, 2);
      expect(find.byType(SelfieLivenessScreen), findsNothing);
      expect(draft.selfie, null);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
