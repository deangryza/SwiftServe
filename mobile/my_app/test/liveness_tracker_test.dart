import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/worker/domain/liveness_tracker.dart';

void main() {
  test('blink requires open closed open over consecutive frames', () {
    final tracker = LivenessTracker(LivenessChallenge.blink);
    for (var i = 0; i < 2; i++) {
      tracker.process(
        faceCount: 1,
        leftEyeOpenProbability: .9,
        rightEyeOpenProbability: .9,
      );
    }
    for (var i = 0; i < 2; i++) {
      tracker.process(
        faceCount: 1,
        leftEyeOpenProbability: .1,
        rightEyeOpenProbability: .1,
      );
    }
    expect(tracker.isComplete, isFalse);
    for (var i = 0; i < 2; i++) {
      tracker.process(
        faceCount: 1,
        leftEyeOpenProbability: .9,
        rightEyeOpenProbability: .9,
      );
    }
    expect(tracker.isComplete, isTrue);
  });

  test('left turn requires sustained turn and a centered return', () {
    final tracker = LivenessTracker(LivenessChallenge.turnLeft);
    for (var i = 0; i < 3; i++) {
      tracker.process(faceCount: 1, yaw: -25);
    }
    expect(tracker.isComplete, isFalse);
    for (var i = 0; i < 2; i++) {
      tracker.process(faceCount: 1, yaw: 0);
    }
    expect(tracker.isComplete, isTrue);
  });

  test('right turn requires sustained turn and a centered return', () {
    final tracker = LivenessTracker(LivenessChallenge.turnRight);
    for (var i = 0; i < 3; i++) {
      tracker.process(faceCount: 1, yaw: 25);
    }
    for (var i = 0; i < 2; i++) {
      tracker.process(faceCount: 1, yaw: 5);
    }
    expect(tracker.isComplete, isTrue);
  });

  test('turn challenge accepts mirrored front-camera yaw', () {
    final tracker = LivenessTracker(LivenessChallenge.turnLeft);
    tracker.process(faceCount: 1, yaw: 20);
    tracker.process(faceCount: 1, yaw: 20);
    tracker.process(faceCount: 1, yaw: 5);
    tracker.process(faceCount: 1, yaw: 5);
    expect(tracker.isComplete, isTrue);
  });

  test('one dropped frame does not erase completed challenge stages', () {
    final tracker = LivenessTracker(LivenessChallenge.turnLeft);
    tracker.process(faceCount: 1, yaw: -20);
    tracker.process(faceCount: 1, yaw: -20);
    tracker.process(faceCount: 0, yaw: null);
    tracker.process(faceCount: 1, yaw: 0);
    tracker.process(faceCount: 1, yaw: 0);
    expect(tracker.isComplete, isTrue);
  });

  test('repeatedly losing the face resets progress', () {
    final tracker = LivenessTracker(LivenessChallenge.turnLeft);
    tracker.process(faceCount: 1, yaw: -25);
    tracker.process(faceCount: 1, yaw: -25);
    tracker.process(faceCount: 0, yaw: -25);
    tracker.process(faceCount: 0, yaw: -25);
    tracker.process(faceCount: 0, yaw: -25);
    tracker.process(faceCount: 1, yaw: -25);
    expect(tracker.isComplete, isFalse);
  });
}
