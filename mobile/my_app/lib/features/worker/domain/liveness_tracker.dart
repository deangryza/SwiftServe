enum LivenessChallenge { blink, turnLeft, turnRight }

class LivenessTracker {
  LivenessTracker(this.challenge);

  final LivenessChallenge challenge;

  int _stage = 0;
  int _consecutiveFrames = 0;
  int _invalidFrames = 0;
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
    _invalidFrames = 0;
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
      _invalidFrames += 1;
      _consecutiveFrames = 0;
      if (_invalidFrames >= 3) reset();
      return false;
    }
    _invalidFrames = 0;

    return switch (challenge) {
      LivenessChallenge.blink => _processBlink(
        leftEyeOpenProbability,
        rightEyeOpenProbability,
      ),
      LivenessChallenge.turnLeft => _processTurn(yaw),
      LivenessChallenge.turnRight => _processTurn(yaw),
    };
  }

  bool _processBlink(double? left, double? right) {
    if (left == null || right == null) {
      _consecutiveFrames = 0;
      return false;
    }
    final qualifies = switch (_stage) {
      0 || 2 => left >= 0.55 && right >= 0.55,
      _ => left <= 0.45 && right <= 0.45,
    };
    _advanceWhen(qualifies, requiredFrames: _stage == 1 ? 1 : 2, finalStage: 2);
    return _complete;
  }

  bool _processTurn(double? yaw) {
    if (yaw == null) {
      _consecutiveFrames = 0;
      return false;
    }
    final qualifies = _stage == 0 ? yaw.abs() >= 15 : yaw.abs() <= 12;
    _advanceWhen(qualifies, requiredFrames: 2, finalStage: 1);
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
