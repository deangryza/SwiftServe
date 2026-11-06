import 'dart:io';
import 'dart:ui';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'capture_quality.dart';
import 'national_id_capture_geometry.dart';

/// Local final-image presence/position checks, never official authentication.
class NationalIdPhotoValidator {
  NationalIdPhotoValidator(this._faces, this._qr);
  final FaceDetector _faces;
  final BarcodeScanner _qr;
  static Future<String> imageExtension(File file) async {
    if (await file.length() > 20 * 1024 * 1024) {
      throw const CaptureQualityException(
        'SIZE',
        'Choose a JPEG or PNG image no larger than 20 MB.',
      );
    }
    final header = await file.openRead(0, 8).expand((part) => part).toList();
    final jpeg =
        header.length >= 3 &&
        header[0] == 255 &&
        header[1] == 216 &&
        header[2] == 255;
    final png = header.join(',') == '137,80,78,71,13,10,26,10';
    if (!jpeg && !png) {
      throw const CaptureQualityException(
        'FORMAT',
        'Choose a JPEG or PNG image.',
      );
    }
    return png ? 'png' : 'jpg';
  }

  Future<void> validate(File file, bool front) async {
    await imageExtension(file);
    final codec = await instantiateImageCodec(await file.readAsBytes());
    late Size size;
    try {
      final image = (await codec.getNextFrame()).image;
      try {
        if (image.width * image.height > 16000000) {
          throw const CaptureQualityException(
            'DIMENSIONS',
            'Choose an image of 16 megapixels or less.',
          );
        }
        size = Size(image.width.toDouble(), image.height.toDouble());
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
    final input = InputImage.fromFilePath(file.path);
    if (front) {
      await CaptureQuality.validate(file, (_) async {
        final faces = await _faces.processImage(input);
        if (faces.length == 1) {
          NationalIdCaptureGeometry.requirePosition(
            size,
            faces.single.boundingBox,
            front: true,
          );
        }
        return faces
            .map(
              (face) => CaptureFace(face.boundingBox, [
                for (final type in [
                  FaceLandmarkType.leftEye,
                  FaceLandmarkType.rightEye,
                  FaceLandmarkType.noseBase,
                  FaceLandmarkType.bottomMouth,
                ])
                  if (face.landmarks[type] != null)
                    Offset(
                      face.landmarks[type]!.position.x.toDouble(),
                      face.landmarks[type]!.position.y.toDouble(),
                    ),
              ]),
            )
            .toList();
      });
    } else {
      final codes = await _qr.processImage(input);
      final readable = codes.where(
        (code) =>
            code.format == BarcodeFormat.qrCode &&
            code.rawValue != null &&
            code.rawValue!.isNotEmpty,
      );
      if (readable.isEmpty) {
        throw const CaptureQualityException(
          'NO_QR',
          'QR could not be read. Clean the lens, tap the QR to focus, hold steady and avoid reflections. Move slightly closer while keeping the whole QR visible.',
        );
      }
      if (!readable.any(
        (code) => NationalIdCaptureGeometry.containsQr(size, code.boundingBox),
      )) {
        throw const CaptureQualityException(
          'QR_POSITION',
          'QR was read, but is outside the ID area. Keep the whole back in the frame with the QR on the right. It does not need to fit the small box exactly.',
        );
      }
      // Deliberately do not store, log or authenticate decoded QR contents.
    }
  }
}
