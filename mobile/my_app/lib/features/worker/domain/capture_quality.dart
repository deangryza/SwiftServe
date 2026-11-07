import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Local usability guidance only. The backend independently checks its image.
class CaptureQualityException implements Exception {
  const CaptureQualityException(this.reason, this.message);
  final String reason;
  final String message;
  @override
  String toString() => message;
}

class CaptureFace {
  const CaptureFace(this.box, this.points);
  final ui.Rect box;
  final List<ui.Offset> points;
}

abstract final class CaptureQuality {
  static const minFaceSide = 64;
  static const minMean = 15.0, maxMean = 240.0, minSharpness = 4.0;
  static const sampleSide = 128;
  static void reject(String reason) {
    throw CaptureQualityException(reason, switch (reason) {
      'NO_FACE' =>
        'No face found. Improve lighting and keep the face fully visible.',
      'MULTIPLE_FACES' =>
        'More than one face found. Keep only your face in the selfie, or frame only the ID document.',
      'FACE_TOO_SMALL' =>
        'Move closer so the face is larger and contains clear detail.',
      'FACE_CROPPED' =>
        'Keep the entire face inside the photo. Retake without cropping the face.',
      'TOO_DARK' =>
        'Improve lighting and retake the photo. Avoid deep shadows on the face.',
      'TOO_BRIGHT' =>
        'Reduce bright light or glare on the face and retake the photo.',
      'TOO_BLURRY' =>
        'Hold the camera steady, focus on the face and retake the photo.',
      _ =>
        'Keep the face fully visible. Remove glare from the ID portrait and retake the photo.',
    });
  }

  static void geometry(int width, int height, CaptureFace face) {
    final box = face.box;
    if (![box.left, box.top, box.width, box.height].every((v) => v.isFinite) ||
        box.width <= 0 ||
        box.height <= 0) {
      reject('FACE_DETAIL');
    }
    if (box.left <= 0 ||
        box.top <= 0 ||
        box.right >= width ||
        box.bottom >= height) {
      reject('FACE_CROPPED');
    }
    if (math.min(box.width, box.height) < minFaceSide) reject('FACE_TOO_SMALL');
    if (face.points.length < 4 ||
        face.points.any(
          (p) =>
              !p.dx.isFinite ||
              !p.dy.isFinite ||
              p.dx <= 0 ||
              p.dy <= 0 ||
              p.dx >= width ||
              p.dy >= height,
        )) {
      reject('FACE_DETAIL');
    }
  }

  static ({double mean, double sharpness}) metrics(
    Uint8List rgba,
    int width,
    int height,
    ui.Rect box,
  ) {
    final w = box.width.floor(), h = box.height.floor();
    final columns = math.min(w, sampleSide), rows = math.min(h, sampleSide);
    final gray = Float64List(columns * rows);
    var sum = 0.0;
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < columns; x++) {
        final px = box.left.floor() + (x * (w - 1) / (columns - 1)).floor();
        final py = box.top.floor() + (y * (h - 1) / (rows - 1)).floor();
        final i = (py * width + px) * 4;
        final value =
            .2126 * rgba[i] + .7152 * rgba[i + 1] + .0722 * rgba[i + 2];
        gray[y * columns + x] = value;
        sum += value;
      }
    }
    var lapSum = 0.0, squares = 0.0, count = 0;
    for (var y = 1; y < rows - 1; y++) {
      for (var x = 1; x < columns - 1; x++) {
        final i = y * columns + x;
        final lap =
            4 * gray[i] -
            gray[i - 1] -
            gray[i + 1] -
            gray[i - columns] -
            gray[i + columns];
        lapSum += lap;
        squares += lap * lap;
        count++;
      }
    }
    return (
      mean: sum / gray.length,
      sharpness: squares / count - math.pow(lapSum / count, 2),
    );
  }

  static void checkMetrics(double mean, double sharpness) {
    if (!mean.isFinite || !sharpness.isFinite) reject('FACE_DETAIL');
    if (mean < minMean) reject('TOO_DARK');
    if (mean > maxMean) reject('TOO_BRIGHT');
    if (sharpness < minSharpness) reject('TOO_BLURRY');
  }

  /// Decode and detect on the actual final file, never a preview frame.
  static Future<void> validate(
    File file,
    Future<List<CaptureFace>> Function(File) detect,
  ) async {
    final codec = await ui.instantiateImageCodec(await file.readAsBytes());
    ui.Image? image;
    try {
      image = (await codec.getNextFrame()).image;
      final faces = await detect(file);
      if (faces.isEmpty) reject('NO_FACE');
      // Preserve the existing Flutter single-ID/single-selfie capture policy.
      if (faces.length != 1) reject('MULTIPLE_FACES');
      geometry(image.width, image.height, faces.single);
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (pixels == null) reject('FACE_DETAIL');
      final result = metrics(
        pixels!.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes),
        image.width,
        image.height,
        faces.single.box,
      );
      checkMetrics(result.mean, result.sharpness);
    } finally {
      image?.dispose();
      codec.dispose();
    }
  }
}

/// Camera-owned files only. Failed/cancelled photos never leave the capture page.
Future<File> captureValidatedPhoto({
  required Future<File> Function() capture,
  required Future<void> Function(File) validate,
  required bool Function() isActive,
}) async {
  final file = await capture();
  try {
    if (!isActive()) throw StateError('Capture cancelled');
    await validate(file);
    if (!isActive()) throw StateError('Capture cancelled');
    return file;
  } catch (_) {
    await file.delete().catchError((_) => file);
    rethrow;
  }
}
