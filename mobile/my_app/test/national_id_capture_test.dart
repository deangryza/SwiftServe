import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:my_app/features/worker/domain/capture_quality.dart';
import 'package:my_app/features/worker/domain/national_id_capture_geometry.dart';
import 'package:my_app/features/worker/domain/national_id_photo_validator.dart';
import 'package:my_app/features/worker/presentation/screens/national_id_capture_screen.dart';

// Synthetic pixels and injected detector results test the local gate. They do
// not measure native ML Kit accuracy or real-camera orientation/QR decoding.
class _Faces extends Fake implements FaceDetector {
  List<Face> results = [];
  String? processedPath;
  @override
  Future<List<Face>> processImage(InputImage image) async {
    processedPath = image.filePath;
    return results;
  }
}

class _Qr extends Fake implements BarcodeScanner {
  List<Barcode> results = [];
  String? processedPath;
  @override
  Future<List<Barcode>> processImage(InputImage image) async {
    processedPath = image.filePath;
    return results;
  }
}

class _FlowValidator extends Fake implements NationalIdPhotoValidator {
  bool validBack = false;
  Completer<void>? pending;
  final List<bool> checkedSides = [];
  final List<File> checkedFiles = [];
  @override
  Future<void> validate(File file, bool front) async {
    checkedSides.add(front);
    checkedFiles.add(file);
    await pending?.future;
    if (!front && !validBack) {
      throw const CaptureQualityException(
        'NO_QR',
        'No readable QR in the right box.',
      );
    }
  }
}

Face face({Rect box = const Rect.fromLTWH(90, 140, 100, 120)}) => Face(
  boundingBox: box,
  landmarks: {
    for (final entry in {
      FaceLandmarkType.leftEye: const Point(115, 175),
      FaceLandmarkType.rightEye: const Point(165, 175),
      FaceLandmarkType.noseBase: const Point(140, 200),
      FaceLandmarkType.bottomMouth: const Point(140, 225),
    }.entries)
      entry.key: FaceLandmark(type: entry.key, position: entry.value),
  },
  contours: {},
);

Barcode qr({
  Rect box = const Rect.fromLTWH(410, 160, 100, 100),
  String? value = 'SWIFTSERVE-SYNTHETIC-DEMO',
  BarcodeFormat format = BarcodeFormat.qrCode,
}) => Barcode(
  type: BarcodeType.text,
  format: format,
  displayValue: null,
  rawValue: value,
  rawBytes: null,
  boundingBox: box,
  cornerPoints: [],
  value: null,
);

Matcher reason(String value) =>
    isA<CaptureQualityException>().having((e) => e.reason, 'reason', value);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File image;
  late _Faces faces;
  late _Qr scanner;
  late NationalIdPhotoValidator validator;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'swiftserve-synthetic-id-test-',
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var y = 0; y < 480; y += 4) {
      for (var x = 0; x < 640; x += 4) {
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 4, 4),
          Paint()
            ..color = (x ~/ 4 + y ~/ 4).isEven
                ? const Color(0xFF666666)
                : const Color(0xFF999999),
        );
      }
    }
    final picture = recorder.endRecording();
    final pixels = await picture.toImage(640, 480);
    final bytes = await pixels.toByteData(format: ui.ImageByteFormat.png);
    image = await File(
      '${directory.path}/synthetic.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    pixels.dispose();
    picture.dispose();
    faces = _Faces();
    scanner = _Qr();
    validator = NationalIdPhotoValidator(faces, scanner);
  });
  tearDown(() async {
    // Only this test's verified temporary directory is removed.
    await image.delete();
    for (final file in directory.listSync().whereType<File>()) {
      await file.delete();
    }
    await directory.delete();
  });

  test('front requires a face on the final file', () async {
    await expectLater(
      validator.validate(image, true),
      throwsA(reason('NO_FACE')),
    );
    expect(faces.processedPath, image.path);
    expect(scanner.processedPath, isNull);
  });
  test('front accepts a clear single face fully inside left guide', () async {
    faces.results = [face()];
    await validator.validate(image, true);
    expect(faces.processedPath, image.path);
  });
  test('face outside the left guide cannot advance', () async {
    faces.results = [face(box: const Rect.fromLTWH(410, 160, 100, 100))];
    await expectLater(
      validator.validate(image, true),
      throwsA(reason('ID_POSITION')),
    );
  });
  test('multiple portraits retain existing rejection policy', () async {
    faces.results = [face(), face()];
    await expectLater(
      validator.validate(image, true),
      throwsA(reason('MULTIPLE_FACES')),
    );
  });
  test('small faces retain existing minimum size', () async {
    faces.results = [face(box: const Rect.fromLTWH(90, 140, 63, 63))];
    await expectLater(
      validator.validate(image, true),
      throwsA(reason('FACE_TOO_SMALL')),
    );
  });
  test('back requires an actually decoded QR on the final file', () async {
    await expectLater(
      validator.validate(image, false),
      throwsA(reason('NO_QR')),
    );
    expect(scanner.processedPath, image.path);
    expect(faces.processedPath, isNull);
  });
  test(
    'readable QR in right guide passes without authenticating contents',
    () async {
      scanner.results = [qr()];
      await validator.validate(image, false);
    },
  );
  test('QR in left guide cannot advance', () async {
    scanner.results = [qr(box: const Rect.fromLTWH(90, 140, 100, 100))];
    await expectLater(
      validator.validate(image, false),
      throwsA(reason('QR_POSITION')),
    );
  });
  test(
    'decoded QR crossing the small guide is accepted within the right ID area',
    () async {
      for (final box in [
        const Rect.fromLTWH(365, 85, 215, 250),
        const Rect.fromLTWH(470, 195, 155, 155),
      ]) {
        expect(
          NationalIdCaptureGeometry.contains(
            const Size(640, 480),
            box,
            front: false,
          ),
          false,
        );
        scanner.results = [qr(box: box)];
        await validator.validate(image, false);
      }
    },
  );
  test(
    'readable but cropped, misplaced or invalid QR geometry is rejected separately',
    () async {
      for (final box in [
        const Rect.fromLTWH(550, 160, 100, 100),
        const Rect.fromLTWH(420, 0, 100, 40),
        const Rect.fromLTWH(420, 160, 0, 100),
        const Rect.fromLTWH(double.nan, 160, 100, 100),
      ]) {
        scanner.results = [qr(box: box)];
        await expectLater(
          validator.validate(image, false),
          throwsA(reason('QR_POSITION')),
        );
      }
    },
  );
  test('tap-to-focus mapping reverses the same cropped preview transform', () {
    for (final imageSize in [const Size(640, 480), const Size(480, 640)]) {
      for (final viewport in [const Size(320, 500), const Size(600, 250)]) {
        final point = NationalIdCaptureGeometry.target(
          imageSize,
          front: false,
        ).center;
        final projected = NationalIdCaptureGeometry.project(
          Rect.fromCenter(center: point, width: 2, height: 2),
          imageSize,
          viewport,
        ).center;
        final mapped = NationalIdCaptureGeometry.focusPoint(
          projected,
          imageSize,
          viewport,
        );
        expect(mapped.dx, closeTo(point.dx / imageSize.width, .00001));
        expect(mapped.dy, closeTo(point.dy / imageSize.height, .00001));
      }
    }
    expect(
      NationalIdCaptureGeometry.focusPoint(
        Offset.zero,
        Size.zero,
        const Size(300, 400),
      ),
      const Offset(.5, .5),
    );
    final clamped = NationalIdCaptureGeometry.focusPoint(
      const Offset(-1000, 1000),
      const Size(640, 480),
      const Size(320, 500),
    );
    expect(clamped.dx, 0);
    expect(clamped.dy, 1);
  });
  test('non-QR barcode and empty or undecodable QR cannot advance', () async {
    for (final code in [
      qr(format: BarcodeFormat.code128),
      qr(value: ''),
      qr(value: null),
    ]) {
      scanner.results = [code];
      await expectLater(
        validator.validate(image, false),
        throwsA(reason('NO_QR')),
      );
    }
  });
  test('malformed input fails before native processing', () async {
    final invalid = await File(
      '${directory.path}/invalid.jpg',
    ).writeAsString('not an image');
    await expectLater(
      validator.validate(invalid, true),
      throwsA(reason('FORMAT')),
    );
    expect(faces.processedPath, isNull);
  });
  test('National ID over 5 MB retains bytes and passes the QR gate', () async {
    final original = await image.readAsBytes();
    final large = await File(
      '${directory.path}/over-five.png',
    ).writeAsBytes([...original, ...List<int>.filled(6 * 1024 * 1024, 0)]);
    scanner.results = [qr()];
    await validator.validate(large, false);
    expect(scanner.processedPath, large.path);
    expect(await large.length(), original.length + 6 * 1024 * 1024);
  });
  test('oversized input fails before decoding and native processing', () async {
    final oversized = File('${directory.path}/large.jpg');
    final handle = await oversized.open(mode: FileMode.write);
    await handle.truncate(20 * 1024 * 1024 + 1);
    await handle.close();
    await expectLater(
      validator.validate(oversized, false),
      throwsA(reason('SIZE')),
    );
    expect(scanner.processedPath, isNull);
  });
  test(
    'guide coordinates scale consistently and reject nonfinite geometry',
    () {
      for (final size in [const Size(640, 480), const Size(480, 640)]) {
        final box = NationalIdCaptureGeometry.target(
          size,
          front: true,
        ).deflate(5);
        expect(
          NationalIdCaptureGeometry.contains(size, box, front: true),
          isTrue,
        );
        final doubled = Rect.fromLTRB(
          box.left * 2,
          box.top * 2,
          box.right * 2,
          box.bottom * 2,
        );
        expect(
          NationalIdCaptureGeometry.contains(size * 2, doubled, front: true),
          isTrue,
        );
        expect(
          NationalIdCaptureGeometry.contains(size, box, front: false),
          isFalse,
        );
      }
      expect(
        NationalIdCaptureGeometry.contains(
          const Size(640, 480),
          const Rect.fromLTWH(double.nan, 10, 30, 30),
          front: false,
        ),
        isFalse,
      );
      final projected = NationalIdCaptureGeometry.project(
        NationalIdCaptureGeometry.card(const Size(640, 480)),
        const Size(640, 480),
        const Size(320, 200),
      );
      expect(projected.center.dx, closeTo(160, .001));
      expect(projected.center.dy, closeTo(100, .001));
      expect(projected.width, closeTo(288, .001));
    },
  );

  for (final allow in [false, true]) {
    testWidgets(
      'gallery explanation returns explicit ${allow ? 'consent' : 'denial'}',
      (tester) async {
        bool? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await requestIdGalleryConsent(context);
                  },
                  child: const Text('Gallery'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Gallery'));
        await tester.pump(const Duration(milliseconds: 350));
        expect(result, isNull);
        expect(find.text('Allow photo selection?'), findsOneWidget);
        await tester.tap(find.text(allow ? 'Choose photo' : 'Cancel'));
        await tester.pump(const Duration(milliseconds: 350));
        expect(result, allow);
      },
    );
  }

  group('National ID guided screen with mocked native channels', () {
    late _FlowValidator flowValidator;
    var pickerCalls = 0;

    setUp(() {
      flowValidator = _FlowValidator();
      TestWidgetsFlutterBinding.ensureInitialized()
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      pickerCalls = 0;

      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/camera'),
        (_) async => [],
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/image_picker'),
        (_) async {
          pickerCalls++;
          return image.path;
        },
      );
      for (final name in [
        'google_mlkit_face_detector',
        'google_mlkit_barcode_scanning',
      ]) {
        messenger.setMockMethodCallHandler(
          MethodChannel(name),
          (_) async => null,
        );
      }
    });
    tearDown(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final name in [
        'plugins.flutter.io/camera',
        'plugins.flutter.io/image_picker',
        'google_mlkit_face_detector',
        'google_mlkit_barcode_scanning',
      ]) {
        messenger.setMockMethodCallHandler(MethodChannel(name), null);
      }
    });

    Future<void> drain(WidgetTester tester) async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    testWidgets(
      'denied gallery consent never opens picker; narrow layout has no overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          const MaterialApp(home: NationalIdCaptureScreen()),
        );
        await drain(tester);
        expect(find.text('Front of your ID'), findsOneWidget);
        expect(find.byIcon(Icons.flash_on), findsNothing);
        await tester.tap(find.byTooltip('Choose ID photo from gallery'));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(find.text('Cancel'));
        await drain(tester);
        expect(pickerCalls, 0);
        expect(find.text('Front of your ID'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await drain(tester);
      },
    );

    testWidgets(
      'gallery requires both sides; invalid QR stays on back; valid retry returns only front',
      (tester) async {
        File? returned;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    returned = await Navigator.of(context).push<File>(
                      MaterialPageRoute(
                        builder: (_) => NationalIdCaptureScreen(
                          openGallery: true,
                          validator: flowValidator,
                        ),
                      ),
                    );
                  },
                  child: const Text('Start'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Start'));
        await tester.pump(const Duration(milliseconds: 350));
        await drain(tester);
        expect(pickerCalls, 0);
        await tester.runAsync(() async {
          await tester.tap(find.text('Choose photo'));
          await Future<void>.delayed(const Duration(milliseconds: 250));
        });
        await drain(tester);
        expect(
          find.text('Back of your ID'),
          findsOneWidget,
          reason:
              'picker calls: $pickerCalls; visible: ${tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).join(" | ")}',
        );
        expect(returned, isNull);
        expect(pickerCalls, 1);
        await tester.tap(find.byTooltip('Choose ID photo from gallery'));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.runAsync(() async {
          await tester.tap(find.text('Choose photo'));
          await Future<void>.delayed(const Duration(milliseconds: 250));
        });
        await drain(tester);
        expect(find.textContaining('No readable QR'), findsOneWidget);
        expect(returned, isNull);

        flowValidator.validBack = true;
        await tester.tap(find.byTooltip('Choose ID photo from gallery'));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.runAsync(() async {
          await tester.tap(find.text('Choose photo'));
          await Future<void>.delayed(const Duration(milliseconds: 250));
        });
        await drain(tester);
        expect(returned, isNotNull);
        expect(returned!.path, endsWith('.png'));
        await tester.runAsync(() async {
          expect(await returned!.exists(), isTrue);
          expect(await image.exists(), isTrue); // Gallery original untouched.
          expect(await returned!.readAsBytes(), await image.readAsBytes());
          await returned!.delete();
        });
        expect(pickerCalls, 3);
        expect(flowValidator.checkedSides, [true, false, false]);
        expect(tester.takeException(), isNull);
      },
    );

    for (final front in [true, false]) {
      testWidgets(
        'single-side capture validates and transfers the ${front ? 'front' : 'back'} file without deleting it',
        (tester) async {
          flowValidator.validBack = true;
          File? returned;
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      returned = await Navigator.of(context).push<File>(
                        MaterialPageRoute(
                          builder: (_) => NationalIdCaptureScreen(
                            frontSide: front,
                            openGallery: true,
                            validator: flowValidator,
                          ),
                        ),
                      );
                    },
                    child: const Text('Start single'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Start single'));
          await tester.pump(const Duration(milliseconds: 350));
          await drain(tester);
          await tester.runAsync(() async {
            await tester.tap(find.text('Choose photo'));
            await Future<void>.delayed(const Duration(milliseconds: 250));
          });
          await drain(tester);
          expect(flowValidator.checkedSides, [front]);
          expect(returned, isNotNull);
          await tester.pumpAndSettle();
          expect(find.byType(NationalIdCaptureScreen), findsNothing);
          await tester.runAsync(() async {
            expect(await returned!.exists(), true);
            expect(await returned!.readAsBytes(), await image.readAsBytes());
            expect(await image.exists(), true);
            await returned!.delete();
          });
          expect(tester.takeException(), null);
        },
      );
    }

    testWidgets(
      'cancellation during validation cleans the owned copy and blocks duplicate selection',
      (tester) async {
        flowValidator.pending = Completer<void>();
        File? returned;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    returned = await Navigator.of(context).push<File>(
                      MaterialPageRoute(
                        builder: (_) => NationalIdCaptureScreen(
                          openGallery: true,
                          validator: flowValidator,
                        ),
                      ),
                    );
                  },
                  child: const Text('Start'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Start'));
        await tester.pump(const Duration(milliseconds: 350));
        await drain(tester);
        await tester.runAsync(() async {
          await tester.tap(find.text('Choose photo'));
          await Future<void>.delayed(const Duration(milliseconds: 250));
        });
        await drain(tester);
        expect(flowValidator.checkedFiles, hasLength(1));
        final gallery = tester.widget<IconButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is IconButton &&
                widget.tooltip == 'Choose ID photo from gallery',
          ),
        );
        expect(gallery.onPressed, isNull);
        await tester.tap(find.byTooltip('Cancel capture'));
        flowValidator.pending!.complete();
        await tester.pump(const Duration(milliseconds: 350));
        await drain(tester);
        expect(returned, isNull);
        await tester.runAsync(() async {
          expect(await flowValidator.checkedFiles.single.exists(), isFalse);
          expect(await image.exists(), isTrue);
        });
        expect(pickerCalls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
