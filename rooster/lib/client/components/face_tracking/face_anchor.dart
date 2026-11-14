import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show BoxFit;

/// Where a plaque is drawn over a video: the middle of the forehead, how
/// wide, and how tilted. In pixels of whatever it was worked out in: the
/// upright video frame ([fromEyes]) or the box the video is shown in
/// ([inBox]).
class FaceAnchor {
  const FaceAnchor({
    required this.center,
    required this.width,
    required this.angle,
  });

  /// How far above the line of the eyes the middle of the forehead is, in
  /// eye distances. Measured on the reference points of the test videos:
  /// 0.56 to 0.60 on three different heads (docs/adr/0006-face-tracking.md).
  static const foreheadRise = 0.58;

  /// How wide a plaque is, in eye distances: about the width of the
  /// forehead.
  static const widthInEyeDistances = 2.2;

  /// The anchor of a face from its two eyes, in pixels of the upright
  /// frame. [rightEye] is the person's right eye, the one on the left of an
  /// unmirrored picture; a face upside down has them the other way round,
  /// and its anchor comes out upside down with it.
  factory FaceAnchor.fromEyes({
    required Offset rightEye,
    required Offset leftEye,
  }) {
    final eyes = leftEye - rightEye;
    final up = Offset(eyes.dy, -eyes.dx);
    return FaceAnchor(
      center: (rightEye + leftEye) / 2 + up * foreheadRise,
      width: eyes.distance * widthInEyeDistances,
      angle: eyes.direction,
    );
  }

  /// The middle of the plaque: the middle of the forehead.
  final Offset center;

  /// The plaque's width.
  final double width;

  /// The plaque's tilt in radians, clockwise on screen: the tilt of the
  /// line of the eyes.
  final double angle;

  /// A point of a frame as the decoder delivered it, in the frame turned
  /// upright. [rotation] is WebRTC's: the degrees (0, 90, 180 or 270) the
  /// frame is to be turned clockwise to be shown upright, as a phone's
  /// camera sends it.
  static Offset uprightPoint(Offset point, Size frameSize, int rotation) {
    return switch (rotation % 360) {
      90 => Offset(frameSize.height - point.dy, point.dx),
      180 => Offset(frameSize.width - point.dx, frameSize.height - point.dy),
      270 => Offset(point.dy, frameSize.width - point.dx),
      _ => point,
    };
  }

  /// The size of a frame once turned upright.
  static Size uprightSize(Size frameSize, int rotation) {
    return rotation % 180 == 90 ? frameSize.flipped : frameSize;
  }

  /// This anchor, worked out in a video of [videoSize], where that video is
  /// shown: in a box of [boxSize], fitted by [fit] around the box's middle,
  /// [mirrored] left to right as our own camera is.
  FaceAnchor inBox({
    required Size videoSize,
    required Size boxSize,
    BoxFit fit = BoxFit.cover,
    bool mirrored = false,
  }) {
    final across = boxSize.width / videoSize.width;
    final down = boxSize.height / videoSize.height;
    final (scaleX, scaleY) = switch (fit) {
      BoxFit.fill => (across, down),
      BoxFit.contain => (math.min(across, down), math.min(across, down)),
      BoxFit.cover => (math.max(across, down), math.max(across, down)),
      BoxFit.fitWidth => (across, across),
      BoxFit.fitHeight => (down, down),
      BoxFit.none => (1.0, 1.0),
      BoxFit.scaleDown => (
          math.min(1.0, math.min(across, down)),
          math.min(1.0, math.min(across, down)),
        ),
    };
    final flip = mirrored ? -1.0 : 1.0;
    // The plaque's own left-to-right direction, through the same stretch.
    final along = Offset(math.cos(angle) * scaleX, math.sin(angle) * scaleY);
    final fromMiddle = center - videoSize.center(Offset.zero);
    return FaceAnchor(
      center: boxSize.center(Offset.zero) +
          Offset(fromMiddle.dx * scaleX * flip, fromMiddle.dy * scaleY),
      width: width * along.distance,
      angle: Offset(along.dx, along.dy * flip).direction,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FaceAnchor &&
      other.center == center &&
      other.width == width &&
      other.angle == angle;

  @override
  int get hashCode => Object.hash(center, width, angle);

  @override
  String toString() => 'FaceAnchor($center, width $width, angle $angle)';
}
