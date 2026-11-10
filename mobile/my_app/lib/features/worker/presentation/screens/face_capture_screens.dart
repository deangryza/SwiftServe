import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../domain/liveness_tracker.dart';
import '../../domain/capture_quality.dart';
import '../../domain/steady_hold_tracker.dart';

Future<void> _validateFinalPhoto(
  File file,
  FaceDetector detector, {
  double minSharpness = CaptureQuality.minSharpness,
}) => CaptureQuality.validate(
  file,
  minSharpness: minSharpness,
  // Debug builds print the measured values so the floor can be tuned.
  onMetrics: (mean, sharpness) {
    if (kDebugMode) {
      debugPrint('Capture quality: mean=$mean sharpness=$sharpness');
    }
  },
  (photo) async {
    final faces = await detector.processImage(
      InputImage.fromFilePath(photo.path),
    );
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
  },
);

class DocumentCaptureScreen extends StatefulWidget {
  const DocumentCaptureScreen({super.key});

  @override
  State<DocumentCaptureScreen> createState() => _DocumentCaptureScreenState();
}

class _DocumentCaptureScreenState extends State<DocumentCaptureScreen> {
  CameraController? _controller;
  late final FaceDetector _detector;
  String? _error;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: true,
      ),
    );
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      final camera = cameras
          .where((item) => item.lensDirection == CameraLensDirection.back)
          .firstOrNull;
      if (camera == null) {
        throw CameraException('noRearCamera', 'No rear camera is available.');
      }
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) return controller.dispose();
      setState(() => _controller = controller);
    } catch (error) {
      if (mounted) setState(() => _error = 'Camera unavailable: $error');
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final photo = await captureValidatedPhoto(
        capture: () async => File((await controller.takePicture()).path),
        validate: (file) => _validateFinalPhoto(file, _detector),
        isActive: () =>
            mounted &&
            controller.value.isInitialized &&
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      );
      if (mounted) Navigator.pop(context, photo);
    } on CaptureQualityException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not capture the ID: $error');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _detector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _CameraScaffold(
    title: 'Capture government ID',
    controller: _controller,
    error: _error,
    instructions:
        'Place the ID inside the frame. Avoid glare and keep the portrait sharp.',
    action: FilledButton.icon(
      onPressed: _checking ? null : _capture,
      icon: const Icon(Icons.camera_alt),
      label: Text(_checking ? 'Checking face…' : 'Capture ID'),
    ),
  );
}

class SelfieLivenessScreen extends StatefulWidget {
  const SelfieLivenessScreen({super.key});

  @override
  State<SelfieLivenessScreen> createState() => _SelfieLivenessScreenState();
}

/// challenge: follow the random prompt. hold: stay still for the countdown.
/// checking: photo taken, being validated. confirm: user accepts or retakes.
/// failed: timed out or the photo was rejected.
enum _SelfiePhase { challenge, hold, checking, confirm, failed }

class _SelfieLivenessScreenState extends State<SelfieLivenessScreen> {
  CameraController? _controller;
  late final FaceDetector _detector;
  late final FaceDetector _finalDetector;
  late LivenessTracker _tracker;
  SteadyHoldTracker _hold = SteadyHoldTracker();
  Timer? _timer;
  _SelfiePhase _phase = _SelfiePhase.challenge;
  bool _processing = false;
  bool _retakePhoto = false;
  bool _faceReady = false;
  bool _accepted = false;
  File? _photo;
  String? _error;
  String? _guidance;
  String _failure =
      'The challenge timed out. Keep one face centered and try again.';

  @override
  void initState() {
    super.initState();
    _finalDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: true,
      ),
    );
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
    _tracker = LivenessTracker(_randomChallenge());
    _initialize();
  }

  LivenessChallenge _randomChallenge() =>
      LivenessChallenge.values[Random.secure().nextInt(
        LivenessChallenge.values.length,
      )];

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      final camera = cameras
          .where((item) => item.lensDirection == CameraLensDirection.front)
          .firstOrNull;
      if (camera == null) {
        throw CameraException('noFrontCamera', 'No front camera is available.');
      }
      final controller = CameraController(
        camera,
        // Higher than the live analysis needs, so the saved selfie is sharp.
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted) return controller.dispose();
      setState(() => _controller = controller);
      await _startChallenge();
    } catch (error) {
      if (mounted) setState(() => _error = 'Camera unavailable: $error');
    }
  }

  Future<void> _startChallenge() async {
    final controller = _controller;
    if (controller == null) return;
    _timer?.cancel();
    final discarded = _photo;
    _photo = null;
    if (discarded != null) unawaited(_deleteQuietly(discarded));
    if (controller.value.isStreamingImages) await controller.stopImageStream();
    if (!mounted) return;
    setState(() {
      _tracker = LivenessTracker(_randomChallenge());
      _hold = SteadyHoldTracker();
      _phase = _SelfiePhase.challenge;
      _retakePhoto = false;
      _faceReady = false;
      _error = null;
      _guidance = null;
    });
    await controller.startImageStream(_processFrame);
    _startTimeout(
      const Duration(seconds: 20),
      'The challenge timed out. Keep one face centered and try again.',
    );
  }

  void _startTimeout(Duration after, String message) {
    _timer?.cancel();
    final controller = _controller;
    _timer = Timer(after, () async {
      if (!mounted ||
          controller == null ||
          (_phase != _SelfiePhase.challenge && _phase != _SelfiePhase.hold)) {
        return;
      }
      // Set the phase first so no later frame can start a capture.
      setState(() {
        _phase = _SelfiePhase.failed;
        _failure = message;
      });
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    });
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_processing ||
        (_phase != _SelfiePhase.challenge && _phase != _SelfiePhase.hold)) {
      return;
    }
    final frame = _inputImage(image);
    if (frame == null) {
      if (mounted && _error == null) {
        setState(() {
          _error =
              'This camera frame could not be analyzed. Try restarting the challenge.';
        });
      }
      return;
    }
    _processing = true;
    try {
      final faces = await _detector.processImage(frame.input);
      // The phase may have changed (timeout, retake) while detecting.
      if (_phase != _SelfiePhase.challenge && _phase != _SelfiePhase.hold) {
        return;
      }
      final face = faces.length == 1 ? faces.first : null;
      final centered = face != null && _isCentered(face, frame.coordinateSize);
      var guidance = switch ((faces.length, centered)) {
        (0, _) => 'No face detected. Move closer and face the camera.',
        (> 1, _) => 'More than one face detected. Keep only your face in view.',
        (1, false) => 'Move your face into the oval.',
        _ => null,
      };
      var capture = false;
      if (_phase == _SelfiePhase.challenge) {
        final complete = _tracker.process(
          faceCount: faces.length,
          leftEyeOpenProbability: face?.leftEyeOpenProbability,
          rightEyeOpenProbability: face?.rightEyeOpenProbability,
          yaw: face?.headEulerAngleY,
          centered: centered,
        );
        if (complete) {
          // The challenge proves a live person; the photo waits for stillness.
          _phase = _SelfiePhase.hold;
          _hold = SteadyHoldTracker();
          _startTimeout(
            const Duration(seconds: 15),
            'Could not get a steady view. Hold the phone still and try again.',
          );
        }
      } else {
        capture = _hold.process(
          now: DateTime.now(),
          faceCount: faces.length,
          frameSize: frame.coordinateSize,
          box: face?.boundingBox,
          centered: centered,
          yaw: face?.headEulerAngleY,
          pitch: face?.headEulerAngleX,
          roll: face?.headEulerAngleZ,
          leftEyeOpenProbability: face?.leftEyeOpenProbability,
          rightEyeOpenProbability: face?.rightEyeOpenProbability,
        );
        guidance = _hold.guidance;
      }
      if (capture) _phase = _SelfiePhase.checking;
      if (mounted) {
        setState(() {
          _error = null;
          _guidance = guidance;
          _faceReady = guidance == null;
        });
      }
      if (capture) unawaited(_finishCapture());
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not analyze the camera image.');
      }
    } finally {
      _processing = false;
    }
  }

  bool _isCentered(Face face, Size coordinateSize) {
    final center = face.boundingBox.center;
    return (center.dx - coordinateSize.width / 2).abs() <=
            coordinateSize.width * 0.35 &&
        (center.dy - coordinateSize.height / 2).abs() <=
            coordinateSize.height * 0.35;
  }

  ({InputImage input, Size coordinateSize})? _inputImage(CameraImage image) {
    final controller = _controller;
    if (controller == null || image.planes.length != 1) return null;
    final rotation = _rotationFor(
      controller.description,
      controller.value.deviceOrientation,
    );
    if (rotation == null) return null;
    final reportedFormat = InputImageFormatValue.fromRawValue(image.format.raw);
    final format = Platform.isAndroid
        // CameraX can label its single-plane NV21 output as yuv420.
        ? InputImageFormat.nv21
        : reportedFormat;
    if (format == null ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }
    final input = InputImage.fromBytes(
      bytes: image.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
    final quarterTurn =
        rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    return (
      input: input,
      coordinateSize: quarterTurn
          ? Size(image.height.toDouble(), image.width.toDouble())
          : Size(image.width.toDouble(), image.height.toDouble()),
    );
  }

  InputImageRotation? _rotationFor(
    CameraDescription camera,
    DeviceOrientation orientation,
  ) {
    const orientationDegrees = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    var rotation = camera.sensorOrientation;
    if (Platform.isAndroid) {
      final compensation = orientationDegrees[orientation];
      if (compensation == null) return null;
      rotation = camera.lensDirection == CameraLensDirection.front
          ? (rotation + compensation) % 360
          : (rotation - compensation + 360) % 360;
    }
    return InputImageRotationValue.fromRawValue(rotation);
  }

  Future<void> _finishCapture() async {
    final controller = _controller;
    if (controller == null) return;
    _timer?.cancel();
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      final photo = await captureValidatedPhoto(
        capture: () async {
          final raw = File((await controller.takePicture()).path);
          // The Android front camera saves a mirror image.
          return Platform.isAndroid ? unmirrorPhoto(raw) : raw;
        },
        validate: (file) => _validateFinalPhoto(
          file,
          _finalDetector,
          minSharpness: CaptureQuality.selfieMinSharpness,
        ),
        isActive: () =>
            mounted &&
            controller.value.isInitialized &&
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      );
      if (!mounted) return _deleteQuietly(photo);
      setState(() {
        _photo = photo;
        _phase = _SelfiePhase.confirm;
      });
    } on CaptureQualityException catch (error) {
      _fail(error.message);
    } catch (error) {
      _fail('Could not check the captured selfie. Retake the selfie.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _phase = _SelfiePhase.failed;
      _failure = 'That selfie could not be used.';
      _retakePhoto = true;
    });
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort cleanup of a camera-owned temporary file.
    }
  }

  void _usePhoto() {
    final photo = _photo;
    if (photo == null) return;
    _accepted = true;
    Navigator.pop(context, photo);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    _detector.close();
    _finalDetector.close();
    // A photo the user never accepted must not outlive this screen.
    final photo = _photo;
    if (photo != null && !_accepted) unawaited(_deleteQuietly(photo));
    super.dispose();
  }

  (IconData, String) get _prompt => switch (_phase) {
    _SelfiePhase.challenge => (
      switch (_tracker.challenge) {
        LivenessChallenge.blink => Icons.visibility_outlined,
        LivenessChallenge.turnLeft => Icons.turn_left,
        LivenessChallenge.turnRight => Icons.turn_right,
      },
      _tracker.prompt,
    ),
    _SelfiePhase.hold => (
      Icons.center_focus_strong_outlined,
      'Look straight and hold still',
    ),
    _SelfiePhase.checking => (
      Icons.hourglass_top_rounded,
      'Checking your selfie…',
    ),
    _SelfiePhase.confirm => (
      Icons.check_circle_outline,
      'Is this photo clear?',
    ),
    _SelfiePhase.failed => (Icons.refresh, _failure),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final controller = _controller;
    final ready = controller?.value.isInitialized ?? false;
    final photo = _photo;
    final live =
        _phase == _SelfiePhase.challenge || _phase == _SelfiePhase.hold;
    final guideColor = !live
        ? colors.outlineVariant
        : _faceReady
        ? Colors.green
        : _guidance != null
        ? Colors.amber
        : Colors.white;
    final (icon, prompt) = _prompt;
    final step = switch (_phase) {
      _SelfiePhase.challenge || _SelfiePhase.failed => 0,
      _SelfiePhase.hold || _SelfiePhase.checking => 1,
      _SelfiePhase.confirm => 2,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Live selfie check')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _SelfieSteps(current: step),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: _phase == _SelfiePhase.confirm && photo != null
                        ? Image.file(
                            photo,
                            key: const ValueKey('selfie_confirm_photo'),
                            fit: BoxFit.contain,
                          )
                        : ready
                        ? Stack(
                            children: [
                              CameraPreview(controller!),
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _FaceGuidePainter(guideColor),
                                ),
                              ),
                              if (_phase == _SelfiePhase.hold)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 16,
                                  child: Center(
                                    child: _Countdown(
                                      progress: _hold.progress,
                                      secondsLeft: _hold.secondsLeft,
                                    ),
                                  ),
                                ),
                              if (_phase == _SelfiePhase.checking)
                                const Positioned.fill(
                                  child: ColoredBox(
                                    color: Colors.black54,
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                                ),
                            ],
                          )
                        : _error == null
                        ? const CircularProgressIndicator()
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 28, color: colors.primary),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          prompt,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Fixed height so the layout does not jump as hints change.
                  SizedBox(
                    height: 40,
                    child: Text(
                      switch (_phase) {
                        _SelfiePhase.confirm =>
                          'Your face should be sharp, well lit and fully visible.',
                        _SelfiePhase.hold =>
                          _guidance ??
                              'The photo is taken when the timer ends.',
                        _SelfiePhase.challenge => _guidance ?? '',
                        _ => '',
                      },
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  if (_error != null) ...[
                    Material(
                      color: colors.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onErrorContainer),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_phase == _SelfiePhase.confirm) ...[
                    FilledButton.icon(
                      key: const ValueKey('selfie_use_photo'),
                      onPressed: _usePhoto,
                      icon: const Icon(Icons.check),
                      label: const Text('Use this photo'),
                    ),
                    TextButton.icon(
                      key: const ValueKey('selfie_retake'),
                      onPressed: _startChallenge,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retake'),
                    ),
                  ] else if (_phase == _SelfiePhase.failed)
                    FilledButton.icon(
                      onPressed: _startChallenge,
                      icon: const Icon(Icons.refresh),
                      label: Text(_retakePhoto ? 'Retake selfie' : 'Try again'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelfieSteps extends StatelessWidget {
  const _SelfieSteps({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const labels = ['Follow the prompt', 'Hold still', 'Confirm'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= current
                          ? colors.primary
                          : colors.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${i + 1}. ${labels[i]}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: i == current
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.progress, required this.secondsLeft});

  final double progress;
  final int secondsLeft;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: 'Taking the photo in $secondsLeft',
    child: SizedBox.square(
      dimension: 72,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
          ),
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 5,
            color: Colors.green,
            backgroundColor: Colors.white24,
          ),
          Center(
            child: Text(
              '$secondsLeft',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Dims everything outside an oval so the user knows where to place the face.
class _FaceGuidePainter extends CustomPainter {
  const _FaceGuidePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final oval = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.45),
      width: size.width * 0.68,
      height: size.height * 0.62,
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addOval(oval),
      ),
      Paint()..color = Colors.black54,
    );
    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_FaceGuidePainter old) => old.color != color;
}

class _CameraScaffold extends StatelessWidget {
  const _CameraScaffold({
    required this.title,
    required this.controller,
    required this.error,
    required this.instructions,
    required this.action,
  });

  final String title;
  final CameraController? controller;
  final String? error;
  final String instructions;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final ready = controller?.value.isInitialized ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ready
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: CameraPreview(controller!),
                      ),
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(instructions, textAlign: TextAlign.center),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 16),
                  action,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
