import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../domain/capture_quality.dart';
import '../../domain/national_id_photo_validator.dart';
import '../../domain/national_id_capture_geometry.dart';

/// Native selected-photo access, preceded by an explanation and consent.
/// No broad access to the user's gallery is requested.
Future<bool> requestIdGalleryConsent(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Allow photo selection?'),
        content: const Text(
          'Choose an ID image for verification. SwiftServe only '
          'accesses the photo you select. You can cancel and use the camera instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose photo'),
          ),
        ],
      ),
    ) ??
    false;

/// Default mode returns the front backend document and deletes the checked back.
/// Single-side mode transfers that side to registration for local previews.
/// Decoding is NOT government authentication or worker approval.
class NationalIdCaptureScreen extends StatefulWidget {
  const NationalIdCaptureScreen({
    super.key,
    this.openGallery = false,
    this.validator,
    this.frontSide,
  });
  final bool openGallery;
  final NationalIdPhotoValidator? validator;

  /// Registration can capture one side without discarding the other side.
  /// Null preserves the existing two-sided verification flow and File result.
  final bool? frontSide;

  @override
  State<NationalIdCaptureScreen> createState() =>
      _NationalIdCaptureScreenState();
}

class _NationalIdCaptureScreenState extends State<NationalIdCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  final _faces = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableLandmarks: true,
    ),
  );
  final _qr = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
  File? _front;
  File? _preview;
  bool _busy = false, _returned = false, _disposed = false, _cancelled = false;
  int _cameraGeneration = 0;
  Future<void>? _operation;
  String? _error;
  bool _focusing = false;

  Future<void> _focusAt(CameraController camera, Offset point) async {
    if (_focusing || _busy || _disposed || _camera != camera) return;
    _focusing = true;
    try {
      for (final action in <Future<void> Function()>[
        () => camera.setFocusMode(FocusMode.auto),
        () => camera.setFocusPoint(point),
        () => camera.setExposurePoint(point),
      ]) {
        if (_disposed || _camera != camera || !camera.value.isInitialized) {
          return;
        }
        try {
          await action();
        } catch (_) {
          // Fixed-focus/unsupported metering must not disable camera capture.
        }
      }
    } finally {
      _focusing = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!widget.openGallery) _initialize();
    if (widget.openGallery) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _select(true);
      });
    }
  }

  Future<void> _initialize() async {
    final generation = ++_cameraGeneration;
    CameraController? candidate;
    try {
      final devices = await availableCameras();
      if (!mounted || generation != _cameraGeneration) return;
      final rear = devices
          .where((c) => c.lensDirection == CameraLensDirection.back)
          .firstOrNull;
      if (rear == null) throw StateError('No rear camera');
      candidate = CameraController(
        rear,
        ResolutionPreset.veryHigh,
        enableAudio: false,
      );
      try {
        await candidate.initialize();
      } catch (_) {
        // Dense ID QR codes benefit from more source pixels. Retain capture
        // on devices that cannot initialize the higher-resolution preset.
        await candidate.dispose();
        if (!mounted || generation != _cameraGeneration) return;
        candidate = CameraController(
          rear,
          ResolutionPreset.high,
          enableAudio: false,
        );
        await candidate.initialize();
      }
      if (!mounted || generation != _cameraGeneration) {
        await candidate.dispose();
        return;
      }
      setState(() => _camera = candidate);
      unawaited(_focusAt(candidate, const Offset(.5, .5)));
    } catch (_) {
      await candidate?.dispose();
      if (mounted && generation == _cameraGeneration) {
        setState(
          () => _error ??=
              'Camera unavailable. Allow camera access in Settings, or choose a photo.',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      ++_cameraGeneration;
      final camera = _camera;
      _camera = null;
      unawaited(camera?.dispose());
    } else if (state == AppLifecycleState.resumed && _camera == null) {
      _initialize();
    }
  }

  Future<void> _delete(File? file) async {
    if (file != null) {
      try {
        await file.delete();
      } catch (_) {
        /* Best-effort owned temporary file cleanup. */
      }
    }
  }

  void _select(bool gallery) {
    if (_busy || _cancelled) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    _operation = _process(gallery);
  }

  Future<void> _process(bool gallery) async {
    File? file;
    final front = widget.frontSide ?? (_front == null);
    try {
      if (gallery) {
        if (!await requestIdGalleryConsent(context) || !mounted || _cancelled) {
          return;
        }
        final selected = await ImagePicker().pickImage(
          source: ImageSource.gallery,
        );
        if (selected == null || !mounted || _cancelled) return;
        // Never delete or modify the selected gallery original.
        final extension = await NationalIdPhotoValidator.imageExtension(
          File(selected.path),
        );
        file = await File(selected.path).copy(
          '${Directory.systemTemp.path}/swiftserve-national-id-${DateTime.now().microsecondsSinceEpoch}.$extension',
        );
      } else {
        final camera = _camera;
        if (camera == null || !camera.value.isInitialized) return;
        file = File((await camera.takePicture()).path);
      }
      if (!mounted || _cancelled) return;
      setState(() => _preview = file);
      await (widget.validator ?? NationalIdPhotoValidator(_faces, _qr))
          .validate(file, front);
      if (!mounted || _cancelled) return;
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        throw const CaptureQualityException(
          'INTERRUPTED',
          'Capture interrupted. Please retake this side.',
        );
      }
      if (widget.frontSide != null) {
        _returned = true;
        Navigator.pop(context, file);
        file = null; // Ownership transfers to the registration draft.
      } else if (front) {
        setState(() {
          _front = file;
          _preview = null;
        });
        file = null; // Owned until success or cancellation.
      } else {
        _returned = true;
        Navigator.pop(context, _front);
      }
    } on CaptureQualityException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not read the image. Check photo permissions, then retry or retake.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _preview = null;
          _busy = false;
        });
      }
      await _delete(file);
      if (mounted &&
          !_cancelled &&
          !_returned &&
          _camera == null &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_initialize());
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_cameraGeneration;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_camera?.dispose());
    // Native detectors must stay alive until their in-flight processing finishes.
    unawaited(
      (_operation ?? Future<void>.value()).whenComplete(() async {
        await _faces.close();
        await _qr.close();
        if (!_returned) await _delete(_front);
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final front = widget.frontSide ?? (_front == null);
    return PopScope<File>(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _cancelled = true;
      },
      child: Scaffold(
        backgroundColor: AppTheme.ink,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        front ? 'Front of your ID' : 'Back of your ID',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cancel capture',
                      color: Colors.white,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  front
                      ? 'Place the front inside the frame and fit your photo in the left box.'
                      : 'Keep the QR on the right. Tap it to focus; the small box is only a guide.',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              Expanded(
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final camera = _camera;
                      final preview = _preview;
                      final source = camera?.value.previewSize;
                      final landscape =
                          MediaQuery.orientationOf(context) ==
                          Orientation.landscape;
                      final imageSize = source == null
                          ? constraints.biggest
                          : landscape
                          ? Size(source.width, source.height)
                          : Size(source.height, source.width);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: preview != null || camera == null || _busy
                            ? null
                            : (details) => unawaited(
                                _focusAt(
                                  camera,
                                  NationalIdCaptureGeometry.focusPoint(
                                    details.localPosition,
                                    imageSize,
                                    constraints.biggest,
                                  ),
                                ),
                              ),
                        child: SizedBox.expand(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (preview != null)
                                Image.file(
                                  preview,
                                  fit: BoxFit.contain,
                                  // Cancellation may remove the owned file while a
                                  // departing preview still has an image read queued.
                                  errorBuilder: (_, error, stack) =>
                                      const SizedBox.expand(),
                                )
                              else if (camera != null &&
                                  camera.value.isInitialized)
                                FittedBox(
                                  fit: BoxFit.cover,
                                  clipBehavior: Clip.hardEdge,
                                  child: SizedBox(
                                    width: imageSize.width,
                                    height: imageSize.height,
                                    child: CameraPreview(camera),
                                  ),
                                ),
                              if (preview == null)
                                CustomPaint(
                                  painter: _IdGuides(front, imageSize),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    if (_busy)
                      const LinearProgressIndicator(color: AppTheme.yellow),
                    Text(
                      _busy
                          ? (front
                                ? 'Checking portrait and image quality…'
                                : 'Reading QR code…')
                          : front
                          ? 'Fit your photo in the left box'
                          : 'Tap the QR to focus, hold steady, then capture',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.yellow),
                    ),
                    const SizedBox(height: 10),
                    if (!front && widget.frontSide == null)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final previous = _front;
                                setState(() {
                                  _front = null;
                                  _error = null;
                                });
                                await _delete(previous);
                              },
                        child: const Text(
                          'Retake front',
                          style: TextStyle(color: AppTheme.yellow),
                        ),
                      ),
                    if (_error != null)
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFFFB4AB)),
                      ),
                    const Text(
                      'Avoid glare and keep all four corners visible. Face and QR detection do not authenticate a government ID.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    const SizedBox(width: 56),
                    Expanded(
                      child: Center(
                        child: Semantics(
                          label: 'Capture ${front ? 'front' : 'back'} of ID',
                          button: true,
                          child: SizedBox(
                            width: 72,
                            height: 72,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.all(5),
                                side: const BorderSide(
                                  color: Colors.white,
                                  width: 3,
                                ),
                                shape: const CircleBorder(),
                              ),
                              onPressed:
                                  _busy ||
                                      _disposed ||
                                      _camera?.value.isInitialized != true
                                  ? null
                                  : () => _select(false),
                              child: const CircleAvatar(
                                radius: 30,
                                backgroundColor: AppTheme.yellow,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Choose ID photo from gallery',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white12,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _busy ? null : () => _select(true),
                      icon: const Icon(Icons.photo_library_outlined),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IdGuides extends CustomPainter {
  const _IdGuides(this.front, this.imageSize);
  final bool front;
  final Size imageSize;
  @override
  void paint(Canvas canvas, Size size) {
    final card = NationalIdCaptureGeometry.project(
      NationalIdCaptureGeometry.card(imageSize),
      imageSize,
      size,
    );
    final target = NationalIdCaptureGeometry.project(
      NationalIdCaptureGeometry.target(imageSize, front: front),
      imageSize,
      size,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(card, const Radius.circular(16)),
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final corner = Path()
      ..moveTo(0, 24)
      ..lineTo(0, 12)
      ..quadraticBezierTo(0, 0, 12, 0)
      ..lineTo(24, 0);
    for (final (point, x, y) in [
      (card.topLeft, 1.0, 1.0),
      (card.topRight, -1.0, 1.0),
      (card.bottomLeft, 1.0, -1.0),
      (card.bottomRight, -1.0, -1.0),
    ]) {
      canvas.save();
      canvas.translate(point.dx, point.dy);
      canvas.scale(x, y);
      canvas.drawPath(
        corner,
        Paint()
          ..color = AppTheme.yellow
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(target, const Radius.circular(8)),
      Paint()
        ..color = Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final icon = front ? Icons.person_outline : Icons.qr_code_2;
    final symbol = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          color: Colors.white24,
          fontSize: target.shortestSide * .65,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    symbol.paint(
      canvas,
      target.center - Offset(symbol.width / 2, symbol.height / 2),
    );
    final label = TextPainter(
      text: TextSpan(
        text: front ? 'PHOTO' : 'QR CODE',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(
      canvas,
      Offset(target.center.dx - label.width / 2, target.bottom + 6),
    );
  }

  @override
  bool shouldRepaint(_IdGuides oldDelegate) =>
      oldDelegate.front != front || oldDelegate.imageSize != imageSize;
}
