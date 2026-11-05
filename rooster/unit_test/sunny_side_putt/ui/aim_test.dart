// The aim math of Sunny Side Putt, with no game, no screen and no
// pointer: the slingshot angle, the power curve (crisp for flicks), the
// dead zone, and the arrow's wobble under Hawk Eye.
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/aim_controller.dart';

void main() {
  group('the power curve', () {
    test('zero pull is zero power', () {
      final aim = AimController();
      expect(aim.powerFor(0), 0);
    });

    test('full windup is full power', () {
      final aim = AimController(maxDragLength: 8);
      expect(aim.powerFor(8), 1);
      expect(aim.powerFor(20), 1); // past full is clamped, not more
    });

    test('monotonic: pulling farther never loses power', () {
      final aim = AimController(maxDragLength: 8);
      var previous = -1.0;
      for (var d = 0.0; d <= 8; d += 0.25) {
        final power = aim.powerFor(d);
        expect(power, greaterThanOrEqualTo(previous));
        previous = power;
      }
    });

    test('crisp for flicks: half the windup keeps two thirds of power', () {
      final aim = AimController(maxDragLength: 8, powerExponent: 0.6);
      final half = aim.powerFor(4);
      expect(half, moreOrLessEquals(0.66, epsilon: 0.01),
          reason: 'a flick (short pull) must not be punished by a linear '
              'curve; exponent 0.6 puts half-drag at 2/3 power');
      expect(aim.powerFor(2), greaterThan(0.35),
          reason: 'a quarter pull still carries a quarter-ish stroke and '
              'some more');
    });
  });

  group('the slingshot', () {
    test('pull south, shoot north', () {
      final aim = AimController();
      aim.begin(const Vec2(5, 5));
      aim.update(const Vec2(5, 8)); // dragged 3 units down
      final shot = aim.commit()!;
      // (origin - pointer) points up: angle -pi/2 in the core's convention.
      expect(shot.angle, moreOrLessEquals(-math.pi / 2, epsilon: 1e-9));
      expect(shot.power, greaterThan(0));
    });

    test('drag direction sets the angle all the way around', () {
      final aim = AimController(maxDragLength: 8);
      aim.begin(const Vec2(0, 0));
      aim.update(const Vec2(-4, 0)); // pulled west, shoots east
      expect(aim.commit()!.angle, moreOrLessEquals(0, epsilon: 1e-9));

      aim.begin(const Vec2(0, 0));
      aim.update(const Vec2(0, 5)); // pulled south, shoots north
      expect(
          aim.commit()!.angle, moreOrLessEquals(-math.pi / 2, epsilon: 1e-9));
    });

    test('a tap is not a putt: the dead zone cancels', () {
      final aim = AimController();
      aim.begin(const Vec2(2, 2));
      aim.update(const Vec2(2.5, 2.5)); // well under 0.8 units
      expect(aim.commit(), isNull);
      expect(aim.isActive, isFalse, reason: 'the stroke is done either way');
    });

    test('the drag measures from the press, not the egg block position', () {
      final aim = AimController(maxDragLength: 8);
      aim.begin(const Vec2(10, 10));
      aim.update(const Vec2(10 - 2, 10 - 2));
      expect(aim.dragLength, moreOrLessEquals(math.sqrt(8), epsilon: 1e-9));
      aim.cancel();
      expect(aim.isActive, isFalse);
      expect(aim.commit(), isNull);
    });
  });

  group('the wobble', () {
    // Past the hold's ramp, at full power: the sway's whole reach.
    const held = AimController.steadySeconds + AimController.swayRampSeconds;

    test('Hawk Eye holds the arrow dead still', () {
      final aim = AimController(wobbleAmplitude: 0.035)..noWobble = true;
      for (var t = 0.0; t <= 10; t += 0.1) {
        expect(aim.visualWobble(t), 0);
      }
    });

    test('a hard pull held a while sways inside the amplitude', () {
      final aim = AimController(wobbleAmplitude: 0.035);
      // Peak sway is the amplitude, at a quarter period past the ramp.
      final period = 1 / AimController.wobbleHz;
      final quarter = held + period - (held % period) + period / 4;
      expect(aim.visualWobble(quarter), moreOrLessEquals(0.035, epsilon: 1e-9));
      // Bounded everywhere.
      for (var t = 0.0; t <= 6; t += 1.0 / 60) {
        expect(aim.visualWobble(t).abs(), lessThanOrEqualTo(0.035 + 1e-12));
      }
    });

    test('a quick putt holds still', () {
      final aim = AimController(wobbleAmplitude: 0.035);
      for (var t = 0.0; t <= AimController.steadySeconds; t += 1.0 / 60) {
        expect(aim.visualWobble(t), 0, reason: 'at ${t}s');
      }
    });

    test('a soft putt holds still, however long it is held', () {
      final aim = AimController(wobbleAmplitude: 0.035);
      for (var t = 0.0; t <= 6; t += 1.0 / 60) {
        expect(aim.visualWobble(t, power: AimController.steadyPower), 0);
        expect(aim.visualWobble(t, power: 0.2), 0);
      }
    });

    test('the sway grows with the power', () {
      final aim = AimController(wobbleAmplitude: 0.035);
      double reach(double power) {
        var most = 0.0;
        for (var t = held; t <= held + 2; t += 1.0 / 240) {
          most = math.max(most, aim.visualWobble(t, power: power).abs());
        }
        return most;
      }

      final half = reach(0.7);
      expect(half, greaterThan(0));
      expect(half, lessThan(reach(1)));
      expect(reach(1), moreOrLessEquals(0.035, epsilon: 1e-4));
    });

    test('the pull under way sways by its own power', () {
      final aim = AimController(maxDragLength: 8, wobbleAmplitude: 0.035);
      expect(aim.swayNow(3), 0, reason: 'no pull, no sway');
      aim.begin(const Vec2(0, 0));
      aim.update(const Vec2(0, 8)); // full power
      expect(aim.swayNow(held + 0.2), aim.visualWobble(held + 0.2));
      aim.update(const Vec2(0, 0.5)); // a nudge
      expect(aim.swayNow(held + 0.2), 0);
    });

    test('pure: the same elapsed always gives the same sway', () {
      final aim = AimController(wobbleAmplitude: 0.03);
      expect(aim.visualWobble(2.37), aim.visualWobble(2.37));
    });
  });
}
