import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../domain/liveness_tracker.dart';

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
      options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate),
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
      final capture = await controller.takePicture();
      final faces = await _detector.processImage(
        InputImage.fromFilePath(capture.path),
      );
      if (faces.length != 1) {
        await File(capture.path).delete().catchError((_) => File(capture.path));
        if (!mounted) return;
        setState(
          () => _error = faces.isEmpty
              ? 'No face found on the ID. Retake it in good light without blur or glare.'
              : 'More than one face was found. Frame only the ID document.',
        );
        return;
      }
      if (mounted) Navigator.pop(context, File(capture.path));
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

class _SelfieLivenessScreenState extends State<SelfieLivenessScreen> {
  CameraController? _controller;
  late final FaceDetector _detector;
  late LivenessTracker _tracker;
  Timer? _timer;
  bool _processing = false;
  bool _capturing = false;
  bool _timedOut = false;
  String? _error;

  @override
  void initState() {
    super.initState();
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
    if (controller.value.isStreamingImages) await controller.stopImageStream();
    setState(() {
      _tracker = LivenessTracker(_randomChallenge());
      _timedOut = false;
      _error = null;
    });
    await controller.startImageStream(_processFrame);
    _timer = Timer(const Duration(seconds: 10), () async {
      if (!mounted || _capturing) return;
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      if (mounted) setState(() => _timedOut = true);
    });
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_processing || _capturing || _timedOut) return;
    final input = _inputImage(image);
    if (input == null) return;
    _processing = true;
    try {
      final faces = await _detector.processImage(input);
      final face = faces.length == 1 ? faces.first : null;
      final centered =
          face == null ||
          _isCentered(face, image.width.toDouble(), image.height.toDouble());
      final complete = _tracker.process(
        faceCount: faces.length,
        leftEyeOpenProbability: face?.leftEyeOpenProbability,
        rightEyeOpenProbability: face?.rightEyeOpenProbability,
        yaw: face?.headEulerAngleY,
        centered: centered,
      );
      if (mounted) setState(() {});
      if (complete && !_capturing) {
        _capturing = true;
        unawaited(Future<void>.delayed(Duration.zero, _finishCapture));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not analyze the camera image.');
      }
    } finally {
      _processing = false;
    }
  }

  bool _isCentered(Face face, double width, double height) {
    final center = face.boundingBox.center;
    return (center.dx - width / 2).abs() <= width * 0.3 &&
        (center.dy - height / 2).abs() <= height * 0.3;
  }

  InputImage? _inputImage(CameraImage image) {
    final controller = _controller;
    if (controller == null || image.planes.length != 1) return null;
    final rotation = _rotationFor(
      controller.description,
      controller.value.deviceOrientation,
    );
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (rotation == null || format == null) return null;
    return InputImage.fromBytes(
      bytes: image.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
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
    if (controller == null) {
      _capturing = false;
      return;
    }
    _timer?.cancel();
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      final capture = await controller.takePicture();
      if (mounted) Navigator.pop(context, File(capture.path));
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not capture the selfie: $error');
      }
      _capturing = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    _detector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _CameraScaffold(
    title: 'Live selfie check',
    controller: _controller,
    error: _error,
    instructions: _timedOut
        ? 'The challenge timed out. Keep one face centered and try again.'
        : _tracker.prompt,
    action: _timedOut
        ? FilledButton.icon(
            onPressed: _startChallenge,
            icon: const Icon(Icons.refresh),
            label: const Text('Try another challenge'),
          )
        : const LinearProgressIndicator(),
  );
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
