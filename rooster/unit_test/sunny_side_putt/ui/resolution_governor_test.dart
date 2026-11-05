// The drawing resolution: while frames run slow (an integrated GPU on a
// high-density screen) the surface steps its pixel ratio down, waits for
// the step to settle, and never goes below its floor or back up.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_world3d.dart';

void main() {
  /// Feeds [seconds] of frames at [fps]; returns every step it asked for.
  List<double> run(PuttResolutionGovernor governor, double fps,
      {double seconds = 10}) {
    final steps = <double>[];
    for (var t = 0.0; t < seconds; t += 1 / fps) {
      final next = governor.frame(1 / fps);
      if (next != null) steps.add(next);
    }
    return steps;
  }

  test('slow frames while held (a hole building) are not judged', () {
    final governor = PuttResolutionGovernor(2);
    for (var t = 0.0; t < 10; t += 1 / 8) {
      governor.hold();
      expect(governor.frame(1 / 8), isNull);
    }
    expect(governor.ratio, 2);
  });

  test('a smooth game keeps its sharpness', () {
    final governor = PuttResolutionGovernor(2);
    expect(run(governor, 60, seconds: 30), isEmpty);
    expect(governor.ratio, 2);
  });

  test('slow frames step the ratio down, one settled step at a time', () {
    final governor = PuttResolutionGovernor(2);
    final steps = run(governor, 25, seconds: 6.5);
    expect(steps, [closeTo(1.6, 1e-9)],
        reason: 'the first 2.5 s are not judged, then 3 s are measured');
    final more = run(governor, 25, seconds: 30);
    expect(more.first, closeTo(1.28, 1e-9));
    expect(more.last, 1.0, reason: 'half the device ratio is the floor');
    expect(governor.ratio, 1.0);
    expect(run(governor, 10), isEmpty, reason: 'nothing below the floor');
  });

  test('a one-to-one screen goes no lower than three quarters', () {
    final governor = PuttResolutionGovernor(1);
    run(governor, 20, seconds: 6.5);
    expect(governor.ratio, closeTo(0.8, 1e-9));
    expect(governor.floor, 0.75);
    run(governor, 20, seconds: 60);
    expect(governor.ratio, 0.75);
  });

  test('pauses say nothing about the GPU', () {
    final governor = PuttResolutionGovernor(2);
    for (var i = 0; i < 40; i++) {
      expect(governor.frame(2.0), isNull, reason: 'a hidden tab');
    }
    expect(run(governor, 60, seconds: 20), isEmpty);
  });

  test('a screen already under the floor is left alone', () {
    final governor = PuttResolutionGovernor(0.5);
    expect(governor.floor, 0.5);
    expect(run(governor, 10, seconds: 30), isEmpty);
  });
}
