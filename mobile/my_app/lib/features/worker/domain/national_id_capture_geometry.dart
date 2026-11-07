import 'dart:ui';
import 'dart:math' as math;

import 'capture_quality.dart';

/// Identical normalized guides for the preview and the final decoded image.
abstract final class NationalIdCaptureGeometry {
  /// Maps final-image guides through the same centered BoxFit.cover transform
  /// used by the camera. Cropping the preview never changes validation bounds.
  static Rect project(Rect box, Size image, Size viewport) {
    final scale = math.max(
      viewport.width / image.width,
      viewport.height / image.height,
    );
    final offset = Offset(
      (viewport.width - image.width * scale) / 2,
      (viewport.height - image.height * scale) / 2,
    );
    return Rect.fromLTWH(
      box.left * scale + offset.dx,
      box.top * scale + offset.dy,
      box.width * scale,
      box.height * scale,
    );
  }

  static Rect card(Size image) {
    final width = (image.width * .9).clamp(0.0, image.height * 1.586 * .9);
    return Rect.fromCenter(
      center: Offset(image.width / 2, image.height / 2),
      width: width,
      height: width / 1.586,
    );
  }

  static Rect target(Size image, {required bool front}) {
    final frame = card(image);
    return Rect.fromLTWH(
      frame.left + frame.width * (front ? .05 : .57),
      frame.top + frame.height * .15,
      frame.width * (front ? .30 : .39),
      frame.height * .70,
    );
  }

  static bool contains(Size image, Rect box, {required bool front}) {
    if (image.isEmpty ||
        !image.width.isFinite ||
        !image.height.isFinite ||
        ![box.left, box.top, box.width, box.height].every((v) => v.isFinite) ||
        box.isEmpty) {
      return false;
    }
    final guide = target(image, front: front);
    return guide.contains(box.topLeft) && guide.contains(box.bottomRight);
  }

  /// The yellow QR box is an aiming aid, not an exact acceptance boundary.
  /// Allow perspective/rotation around it while retaining a complete, right-side
  /// QR within the ID frame's small surrounding margin. Front checks stay exact.
  static bool containsQr(Size image, Rect box) {
    if (image.isEmpty ||
        !image.width.isFinite ||
        !image.height.isFinite ||
        ![box.left, box.top, box.width, box.height].every((v) => v.isFinite) ||
        box.isEmpty) {
      return false;
    }
    final frame = card(image);
    final margin = frame.inflate(frame.width * .06);
    return box.left >= 0 &&
        box.top >= 0 &&
        box.right <= image.width &&
        box.bottom <= image.height &&
        box.center.dx >= frame.center.dx &&
        frame.contains(box.center) &&
        margin.contains(box.topLeft) &&
        margin.contains(box.bottomRight);
  }

  /// Inverse of the preview's centered BoxFit.cover transform for focus taps.
  static Offset focusPoint(Offset tap, Size image, Size viewport) {
    if (image.isEmpty ||
        viewport.isEmpty ||
        ![
          tap.dx,
          tap.dy,
          image.width,
          image.height,
          viewport.width,
          viewport.height,
        ].every((v) => v.isFinite)) {
      return const Offset(.5, .5);
    }
    final scale = math.max(
      viewport.width / image.width,
      viewport.height / image.height,
    );
    final offset = Offset(
      (viewport.width - image.width * scale) / 2,
      (viewport.height - image.height * scale) / 2,
    );
    final point = (tap - offset) / scale;
    return Offset(
      (point.dx / image.width).clamp(0.0, 1.0),
      (point.dy / image.height).clamp(0.0, 1.0),
    );
  }

  static void requirePosition(Size image, Rect box, {required bool front}) {
    if (!contains(image, box, front: front)) {
      throw CaptureQualityException(
        'ID_POSITION',
        front
            ? 'Place the ID portrait fully inside the left photo box.'
            : 'Place the entire readable QR code inside the right box.',
      );
    }
  }
}
