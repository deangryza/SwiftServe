import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/worker/domain/steady_hold_tracker.dart';

void main() {
  const frame = Size(720, 1280);
  final start = DateTime(2026, 11, 10, 9);
  const steadyBox = Rect.fromLTWH(210, 400, 300, 380);

  bool feed(
    SteadyHoldTracker tracker,
    int milliseconds, {
    int faceCount = 1,
    Rect? box = steadyBox,
    bool centered = true,
    double yaw = 0,
    double pitch = 0,
    double roll = 0,
    double eyes = 0.9,
  }) => tracker.process(
    now: start.add(Duration(milliseconds: milliseconds)),
    faceCount: faceCount,
    frameSize: frame,
    box: faceCount == 1 ? box : null,
    centered: centered,
    yaw: yaw,
    pitch: pitch,
    roll: roll,
    leftEyeOpenProbability: eyes,
    rightEyeOpenProbability: eyes,
  );

  test('completes only after three steady seconds, never instantly', () {
    final tracker = SteadyHoldTracker();
    expect(feed(tracker, 0), isFalse);
    expect(tracker.secondsLeft, 3);
    expect(feed(tracker, 1100), isFalse);
    expect(tracker.secondsLeft, 2);
    expect(feed(tracker, 2900), isFalse);
    expect(tracker.secondsLeft, 1);
    expect(tracker.guidance, isNull);
    expect(feed(tracker, 3000), isTrue);
    expect(tracker.isComplete, isTrue);
    expect(tracker.progress, 1);
  });

  test('every kind of bad frame restarts the countdown with guidance', () {
    final bad = <HoldIssue, bool Function(SteadyHoldTracker, int)>{
      HoldIssue.noFace: (t, ms) => feed(t, ms, faceCount: 0),
      HoldIssue.manyFaces: (t, ms) => feed(t, ms, faceCount: 2),
      HoldIssue.offCenter: (t, ms) => feed(t, ms, centered: false),
      HoldIssue.tooFar: (t, ms) =>
          feed(t, ms, box: const Rect.fromLTWH(300, 500, 120, 150)),
      HoldIssue.turned: (t, ms) => feed(t, ms, yaw: 18),
      HoldIssue.eyesClosed: (t, ms) => feed(t, ms, eyes: 0.2),
      HoldIssue.moving: (t, ms) =>
          feed(t, ms, box: steadyBox.shift(const Offset(60, 0))),
    };
    for (final entry in bad.entries) {
      final tracker = SteadyHoldTracker();
      feed(tracker, 0);
      feed(tracker, 2500);
      expect(entry.value(tracker, 2600), isFalse, reason: '${entry.key}');
      expect(tracker.issue, entry.key);
      expect(tracker.guidance, isNotNull);
      expect(tracker.progress, 0);
      expect(tracker.secondsLeft, 3);
    }
  });

  test('pitch and roll count as a turned head', () {
    for (final turn in [
      (SteadyHoldTracker t) => feed(t, 0, pitch: -20),
      (SteadyHoldTracker t) => feed(t, 0, roll: 15),
    ]) {
      final tracker = SteadyHoldTracker();
      turn(tracker);
      expect(tracker.issue, HoldIssue.turned);
    }
  });

  test('the countdown restarts from the first good frame after a bad one', () {
    final tracker = SteadyHoldTracker();
    feed(tracker, 0);
    feed(tracker, 2000, yaw: 25);
    expect(feed(tracker, 2100), isFalse);
    expect(feed(tracker, 5000), isFalse);
    expect(feed(tracker, 5100), isTrue);
  });
}
