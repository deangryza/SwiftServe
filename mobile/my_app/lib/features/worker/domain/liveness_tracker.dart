enum LivenessChallenge { blink, turnLeft, turnRight }

class LivenessTracker {
  LivenessTracker(this.challenge);

  final LivenessChallenge challenge;

  int _stage = 0;
  int _consecutiveFrames = 0;
  bool _complete = false;

  bool get isComplete => _complete;

  String get prompt => switch (challenge) {
    LivenessChallenge.blink => switch (_stage) {
      0 => 'Keep both eyes open',
      1 => 'Blink now',
      _ => 'Open your eyes again',
    },
    LivenessChallenge.turnLeft =>
      _stage == 0 ? 'Turn your head left' : 'Return to the center',
    LivenessChallenge.turnRight =>
      _stage == 0 ? 'Turn your head right' : 'Return to the center',
  };

  void reset() {
    _stage = 0;
    _consecutiveFrames = 0;
    _complete = false;
  }

  bool process({
    required int faceCount,
    double? leftEyeOpenProbability,
    double? rightEyeOpenProbability,
    double? yaw,
    bool centered = true,
  }) {
    if (_complete) return true;
    if (faceCount != 1 || !centered) {
      reset();
      return false;
    }

    return switch (challenge) {
      LivenessChallenge.blink => _processBlink(
        leftEyeOpenProbability,
        rightEyeOpenProbability,
      ),
      LivenessChallenge.turnLeft => _processTurn(yaw, expectPositive: false),
      LivenessChallenge.turnRight => _processTurn(yaw, expectPositive: true),
    };
  }

  bool _processBlink(double? left, double? right) {
    if (left == null || right == null) {
      _consecutiveFrames = 0;
      return false;
    }
    final qualifies = switch (_stage) {
      0 || 2 => left >= 0.7 && right >= 0.7,
      _ => left <= 0.3 && right <= 0.3,
    };
    _advanceWhen(qualifies, requiredFrames: 2, finalStage: 2);
    return _complete;
  }

  bool _processTurn(double? yaw, {required bool expectPositive}) {
    if (yaw == null) {
      _consecutiveFrames = 0;
      return false;
    }
    final qualifies = _stage == 0
        ? (expectPositive ? yaw >= 20 : yaw <= -20)
        : yaw.abs() <= 10;
    _advanceWhen(qualifies, requiredFrames: _stage == 0 ? 3 : 2, finalStage: 1);
    return _complete;
  }

  void _advanceWhen(
    bool qualifies, {
    required int requiredFrames,
    required int finalStage,
  }) {
    if (!qualifies) {
      _consecutiveFrames = 0;
      return;
    }
    _consecutiveFrames += 1;
    if (_consecutiveFrames < requiredFrames) return;
    _consecutiveFrames = 0;
    if (_stage == finalStage) {
      _complete = true;
    } else {
      _stage += 1;
    }
  }
}
