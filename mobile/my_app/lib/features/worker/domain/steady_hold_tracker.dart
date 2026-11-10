import 'dart:ui';

/// Why the hold-still countdown is not progressing.
enum HoldIssue {
  noFace,
  manyFaces,
  offCenter,
  tooFar,
  turned,
  eyesClosed,
  moving,
}

/// Runs after the liveness challenge. The photo is taken only once the face
/// has stayed centred, forward-facing and still for [holdFor], so the picture
/// is never taken mid-movement.
class SteadyHoldTracker {
  SteadyHoldTracker({this.holdFor = const Duration(seconds: 3)});

  final Duration holdFor;

  static const maxYaw = 10.0, maxPitch = 12.0, maxRoll = 10.0;
  static const minEyeOpen = 0.5;
  static const minFaceWidthRatio = 0.3;
  static const maxMoveRatio = 0.04;

  DateTime? _steadySince;
  Offset? _lastCenter;
  Duration _held = Duration.zero;
  bool _complete = false;
  HoldIssue? _issue;

  bool get isComplete => _complete;

  /// Null while the current frame is good.
  HoldIssue? get issue => _issue;

  double get progress => _complete
      ? 1
      : (_held.inMilliseconds / holdFor.inMilliseconds).clamp(0.0, 1.0);

  /// Whole seconds still to wait, counting 3, 2, 1.
  int get secondsLeft => _complete
      ? 0
      : ((holdFor - _held).inMilliseconds / 1000).ceil().clamp(
          1,
          holdFor.inSeconds,
        );

  String? get guidance => switch (_issue) {
    null => null,
    HoldIssue.noFace => 'No face detected. Face the camera.',
    HoldIssue.manyFaces => 'Keep only your face in view.',
    HoldIssue.offCenter => 'Move your face into the oval.',
    HoldIssue.tooFar => 'Move closer to the camera.',
    HoldIssue.turned => 'Look straight at the camera.',
    HoldIssue.eyesClosed => 'Keep your eyes open.',
    HoldIssue.moving => 'Hold still.',
  };

  void reset() {
    _steadySince = null;
    _lastCenter = null;
    _held = Duration.zero;
    _complete = false;
    _issue = null;
  }

  /// Feeds one camera frame. Returns true once the hold is complete.
  bool process({
    required DateTime now,
    required int faceCount,
    required Size frameSize,
    Rect? box,
    bool centered = true,
    double? yaw,
    double? pitch,
    double? roll,
    double? leftEyeOpenProbability,
    double? rightEyeOpenProbability,
  }) {
    if (_complete) return true;
    final issue = _check(
      faceCount: faceCount,
      frameSize: frameSize,
      box: box,
      centered: centered,
      yaw: yaw,
      pitch: pitch,
      roll: roll,
      leftEye: leftEyeOpenProbability,
      rightEye: rightEyeOpenProbability,
    );
    _lastCenter = box?.center;
    _issue = issue;
    if (issue != null) {
      _steadySince = null;
      _held = Duration.zero;
      return false;
    }
    _steadySince ??= now;
    _held = now.difference(_steadySince!);
    if (_held >= holdFor) _complete = true;
    return _complete;
  }

  HoldIssue? _check({
    required int faceCount,
    required Size frameSize,
    required Rect? box,
    required bool centered,
    required double? yaw,
    required double? pitch,
    required double? roll,
    required double? leftEye,
    required double? rightEye,
  }) {
    if (faceCount > 1) return HoldIssue.manyFaces;
    if (faceCount == 0 || box == null) return HoldIssue.noFace;
    if (!centered) return HoldIssue.offCenter;
    if (box.width < frameSize.width * minFaceWidthRatio) {
      return HoldIssue.tooFar;
    }
    if ((yaw ?? 0).abs() > maxYaw ||
        (pitch ?? 0).abs() > maxPitch ||
        (roll ?? 0).abs() > maxRoll) {
      return HoldIssue.turned;
    }
    if ((leftEye ?? 1) < minEyeOpen || (rightEye ?? 1) < minEyeOpen) {
      return HoldIssue.eyesClosed;
    }
    final last = _lastCenter;
    if (last != null &&
        (box.center - last).distance > frameSize.width * maxMoveRatio) {
      return HoldIssue.moving;
    }
    return null;
  }
}
