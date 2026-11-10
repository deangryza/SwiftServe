import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/worker/domain/capture_quality.dart';

const face = CaptureFace(ui.Rect.fromLTWH(50, 50, 100, 100), [
  ui.Offset(80, 80),
  ui.Offset(120, 80),
  ui.Offset(100, 100),
  ui.Offset(100, 120),
]);
Matcher rejected(String reason) =>
    isA<CaptureQualityException>().having((e) => e.reason, 'reason', reason);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(
    () async => directory = await Directory.systemTemp.createTemp(
      'swiftserve-synthetic-quality-',
    ),
  );
  tearDown(() async => directory.delete(recursive: true));
  Future<File> png(int value, {bool detail = false}) async {
    final recorder = ui.PictureRecorder(), canvas = ui.Canvas(recorder);
    for (var y = 0; y < 200; y += 4) {
      for (var x = 0; x < 200; x += 4) {
        final level = detail
            ? ((x ~/ 4 + y ~/ 4).isEven ? value - 30 : value + 30)
            : value;
        canvas.drawRect(
          ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 4, 4),
          ui.Paint()..color = ui.Color.fromARGB(255, level, level, level),
        );
      }
    }
    final picture = recorder.endRecording(),
        image = await picture.toImage(200, 200);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return File(
      '${directory.path}/synthetic-${directory.listSync().length}.png',
    )..writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  test('selfies use a higher sharpness floor; the ID floor is unchanged', () {
    CaptureQuality.checkMetrics(120, 4);
    CaptureQuality.checkMetrics(
      120,
      CaptureQuality.selfieMinSharpness,
      minSharpness: CaptureQuality.selfieMinSharpness,
    );
    expect(
      () => CaptureQuality.checkMetrics(
        120,
        CaptureQuality.selfieMinSharpness - 0.001,
        minSharpness: CaptureQuality.selfieMinSharpness,
      ),
      throwsA(rejected('TOO_BLURRY')),
    );
  });
  test('unmirrorPhoto flips the photo left-to-right into a new file', () async {
    final recorder = ui.PictureRecorder(), canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 10, 20),
      ui.Paint()..color = const ui.Color(0xFFFF0000),
    );
    canvas.drawRect(
      const ui.Rect.fromLTWH(10, 0, 10, 20),
      ui.Paint()..color = const ui.Color(0xFF0000FF),
    );
    final picture = recorder.endRecording(),
        image = await picture.toImage(20, 20);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    final original = File('${directory.path}/selfie.jpg')
      ..writeAsBytesSync(bytes!.buffer.asUint8List());

    final flipped = await unmirrorPhoto(original);

    expect(original.existsSync(), isFalse);
    expect(flipped.path, endsWith('selfie-unmirrored.png'));
    final codec = await ui.instantiateImageCodec(await flipped.readAsBytes());
    final decoded = (await codec.getNextFrame()).image;
    final rgba = (await decoded.toByteData())!;
    expect((decoded.width, decoded.height), (20, 20));
    // Left edge was red and is now blue; right edge was blue and is now red.
    expect([rgba.getUint8(0), rgba.getUint8(2)], [0, 255]);
    expect([rgba.getUint8(19 * 4), rgba.getUint8(19 * 4 + 2)], [255, 0]);
    decoded.dispose();
    codec.dispose();
  });
  test('exposure and sharpness boundaries and retake guidance', () {
    for (final mean in [15.0, 240.0]) {
      CaptureQuality.checkMetrics(mean, 4);
    }
    expect(
      () => CaptureQuality.checkMetrics(14.999, 4),
      throwsA(rejected('TOO_DARK')),
    );
    expect(
      () => CaptureQuality.checkMetrics(240.001, 4),
      throwsA(rejected('TOO_BRIGHT')),
    );
    expect(
      () => CaptureQuality.checkMetrics(120, 3.999),
      throwsA(rejected('TOO_BLURRY')),
    );
    expect(
      () => CaptureQuality.checkMetrics(double.nan, 4),
      throwsA(rejected('FACE_DETAIL')),
    );
    try {
      CaptureQuality.reject('TOO_BLURRY');
    } on CaptureQualityException catch (e) {
      expect(e.message, contains('steady'));
    }
    try {
      CaptureQuality.reject('TOO_DARK');
    } on CaptureQualityException catch (e) {
      expect(e.message, contains('lighting'));
    }
  });
  test(
    'small, cropped and missing facial detail are distinct; minimum size is inclusive',
    () {
      CaptureQuality.geometry(
        200,
        200,
        CaptureFace(const ui.Rect.fromLTWH(50, 50, 64, 64), face.points),
      );
      expect(
        () => CaptureQuality.geometry(
          200,
          200,
          CaptureFace(const ui.Rect.fromLTWH(50, 50, 63.99, 64), face.points),
        ),
        throwsA(rejected('FACE_TOO_SMALL')),
      );
      expect(
        () => CaptureQuality.geometry(
          200,
          200,
          CaptureFace(const ui.Rect.fromLTWH(0, 50, 100, 100), face.points),
        ),
        throwsA(rejected('FACE_CROPPED')),
      );
      expect(
        () => CaptureQuality.geometry(
          200,
          200,
          CaptureFace(const ui.Rect.fromLTWH(150, 50, 100, 100), face.points),
        ),
        throwsA(rejected('FACE_CROPPED')),
      );
      expect(
        () => CaptureQuality.geometry(
          200,
          200,
          const CaptureFace(ui.Rect.fromLTWH(50, 50, 100, 100), []),
        ),
        throwsA(rejected('FACE_DETAIL')),
      );
    },
  );
  test(
    'generated PNGs exercise final-file decoding, usable detail, darkness, exposure and blur',
    () async {
      for (final entry in [
        (5, 'TOO_DARK'),
        (250, 'TOO_BRIGHT'),
        (120, 'TOO_BLURRY'),
      ]) {
        final file = await png(entry.$1);
        await expectLater(
          CaptureQuality.validate(file, (_) async => [face]),
          throwsA(rejected(entry.$2)),
        );
      }
      await CaptureQuality.validate(
        await png(120, detail: true),
        (_) async => [face],
      );
    },
  );
  test(
    'actual final-file detection rejects no face and multiple faces',
    () async {
      final file = await png(120, detail: true);
      await expectLater(
        CaptureQuality.validate(file, (_) async => []),
        throwsA(rejected('NO_FACE')),
      );
      await expectLater(
        CaptureQuality.validate(file, (_) async => [face, face]),
        throwsA(rejected('MULTIPLE_FACES')),
      );
    },
  );
  test(
    'final selfie is validated before it can leave capture; rejected camera file is removed',
    () async {
      final file = await png(120);
      var checked = false;
      await expectLater(
        captureValidatedPhoto(
          capture: () async => file,
          isActive: () => true,
          validate: (actual) async {
            expect(actual.path, file.path);
            checked = true;
            await CaptureQuality.validate(actual, (_) async => [face]);
          },
        ),
        throwsA(rejected('TOO_BLURRY')),
      );
      expect(checked, isTrue);
      expect(await file.exists(), isFalse);
    },
  );
  test(
    'usable final photo survives; cancellation during validation cannot return a file',
    () async {
      final good = await png(120, detail: true);
      expect(
        await captureValidatedPhoto(
          capture: () async => good,
          validate: (file) =>
              CaptureQuality.validate(file, (_) async => [face]),
          isActive: () => true,
        ),
        good,
      );
      expect(await good.exists(), isTrue);
      final cancelled = await png(120, detail: true),
          started = Completer<void>(),
          release = Completer<void>();
      var active = true;
      final pending = captureValidatedPhoto(
        capture: () async => cancelled,
        validate: (_) async {
          started.complete();
          await release.future;
        },
        isActive: () => active,
      );
      await started.future;
      active = false;
      final assertion = expectLater(pending, throwsStateError);
      release.complete();
      await assertion;
      expect(await cancelled.exists(), isFalse);
    },
  );
  test('quality pixels are inspected without modification', () {
    final rgba = Uint8List(100 * 100 * 4);
    for (var i = 0; i < rgba.length; i += 4) {
      rgba[i] = rgba[i + 1] = rgba[i + 2] = 100;
      rgba[i + 3] = 255;
    }
    final before = Uint8List.fromList(rgba);
    expect(
      CaptureQuality.metrics(
        rgba,
        100,
        100,
        const ui.Rect.fromLTWH(10, 10, 80, 80),
      ).mean,
      closeTo(100, .0001),
    );
    expect(rgba, orderedEquals(before));
  });
}
