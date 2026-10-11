// What the in-game overlay draws: pixels the runner can put straight into a
// layered window (windows/runner/game_overlay.cpp).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/utils/game_overlay/overlay_painter.dart';

const _members = [
  OverlayMember(name: "Ana", talking: true),
  OverlayMember(name: "Bo, whose name is long enough to need cutting short",
      muted: true),
];

int _alpha(OverlayImage image, int x, int y) =>
    image.rgba[(y * image.width + x) * 4 + 3];

/// Premultiplied, as UpdateLayeredWindow blends: no colour brighter than
/// its alpha. Straight alpha would light up every soft edge.
bool _premultiplied(Uint8List rgba) {
  for (var i = 0; i < rgba.length; i += 4) {
    final a = rgba[i + 3];
    if (rgba[i] > a || rgba[i + 1] > a || rgba[i + 2] > a) return false;
  }
  return true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("one pill per person, a long name cut short", () async {
    final image = await drawVoicePanel(_members, scale: 1);
    expect(image.height, 2 * 32 + 4);
    // Avatar, name at most 200 wide, badge, padding.
    expect(image.width, lessThanOrEqualTo(32 + 4 + 200 + 20 + 12));
    expect(image.rgba.length, image.width * image.height * 4);
  });

  test("drawn at the screen's scale", () async {
    final small = await drawVoicePanel(_members, scale: 1);
    final large = await drawVoicePanel(_members, scale: 2);
    expect(large.height, small.height * 2);
    expect((large.width - small.width * 2).abs(), lessThanOrEqualTo(2));
  });

  test("see-through around the pills, premultiplied inside", () async {
    final image = await drawVoicePanel(_members, scale: 1);
    expect(_alpha(image, 0, 0), 0);
    expect(_alpha(image, 16, 16), greaterThan(0));
    expect(_premultiplied(image.rgba), isTrue);
  });

  test("the count of the rest gets a pill of its own", () async {
    final image = await drawVoicePanel(_members, more: "4 more", scale: 1);
    expect(image.height, 3 * 32 + 2 * 4);
  });

  test("toasts are as wide as each other, and stack", () async {
    final one = await drawToasts(
        [OverlayToast(sender: "Ana", room: "general", body: "gg")],
        scale: 1);
    final two = await drawToasts([
      OverlayToast(sender: "Ana", room: "general", body: "gg"),
      OverlayToast(sender: "Bo", body: "a message\nthat goes on " * 10),
    ], scale: 1);
    expect(one.width, 320);
    expect(two.width, 320);
    expect(two.height, greaterThan(one.height * 2));
    expect(_premultiplied(two.rgba), isTrue);
  });
}
