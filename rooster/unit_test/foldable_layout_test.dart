// A foldable in the browser: a phone while folded, a small tablet once
// opened, and nothing hovers over either. The layout went by the window's
// width alone (a phone on its side got the desktop's three columns), the
// call's buttons by the layout (an unfolded one never showed them), and the
// compact row of them by nothing (it ran off a narrow cover screen).
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/ui/organisms/call_view/call_control_buttons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('which layout a window in a browser gets', () {
    bool phone(double width, double height, {double? screen}) =>
        Layout.isPhoneSized(
            width: width,
            screenShortestSide: screen ?? (width < height ? width : height),
            scale: 1);

    test('a folded foldable and a phone upright: the phone layout', () {
      expect(phone(344, 882), isTrue);
      expect(phone(280, 653), isTrue);
      expect(phone(412, 915), isTrue);
    });

    test('a phone on its side is still a phone', () {
      expect(phone(915, 412), isTrue);
      expect(phone(800, 360), isTrue);
    });

    test('an unfolded foldable gets the desktop layout, upright or turned', () {
      expect(phone(690, 829), isFalse);
      expect(phone(829, 690), isFalse);
      expect(phone(841, 701), isFalse);
    });

    test('the keyboard coming up does not change the layout', () {
      // The window loses half its height; the screen is what it was.
      expect(phone(690, 400, screen: 690), isFalse);
      expect(phone(344, 400, screen: 344), isTrue);
    });

    test('a narrow window on a big screen is a phone: split screen', () {
      expect(phone(345, 829, screen: 690), isTrue);
    });

    test('outside a browser only the width counts, as it always did', () {
      expect(
          Layout.isPhoneSized(width: 800, screenShortestSide: null, scale: 1),
          isFalse);
      expect(
          Layout.isPhoneSized(width: 400, screenShortestSide: null, scale: 1),
          isTrue);
    });

    test('the app scale counts, as it always did', () {
      expect(
          Layout.isPhoneSized(width: 500, screenShortestSide: 500, scale: 1.5),
          isFalse);
    });
  });

  group("the compact row of the call's buttons", () {
    double radius(double width, {int count = 6}) =>
        CallControlButtons.compactRadius(asked: 24, width: width, count: count);

    test('keeps touch-sized buttons where they fit', () {
      expect(radius(396), 24);
      expect(radius(328), 24);
    });

    test('shrinks them to fit a narrow cover screen', () {
      // 280 wide, less the row's padding.
      final fitted = radius(264);
      expect(fitted, lessThan(24));
      expect(fitted * 2 * 6, lessThanOrEqualTo(264));
    });

    test('never to nothing', () {
      expect(radius(60), 12);
    });
  });
}
