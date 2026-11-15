import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// The outputs of YuNet for one stride: per cell of its grid, the class and
/// objectness scores and the five landmarks (x and y each, in cells from
/// the cell's corner).
typedef YunetLayer = ({Float32List cls, Float32List obj, Float32List kps});

/// The surest face YuNet found, its eyes in pixels of the detector's input.
/// [rightEye] is the person's right eye, the one on the left of the
/// picture: YuNet's first landmark.
typedef YunetFace = ({Offset rightEye, Offset leftEye, double score});

/// YuNet (OpenCV Zoo's `face_detection_yunet_2023mar`), the face detector of
/// the browser and the desktop (docs/adr/0006-face-tracking.md).
abstract final class Yunet {
  /// The model file, an asset of the app.
  static const asset =
      'assets/face_tracking/face_detection_yunet_2023mar_dynamic.onnx';

  /// The grids it looks at faces on, by the pixels per cell. Its input's
  /// sides are multiples of the largest.
  static const strides = [8, 16, 32];

  /// Below this a face is not taken: OpenCV's own default.
  static const minScore = 0.6;

  /// The face with the best score above [minScore] among [layers], keyed by
  /// stride, for an input [inputWidth] pixels wide; null when there is none.
  static YunetFace? bestFace(
    Map<int, YunetLayer> layers, {
    required int inputWidth,
  }) {
    var best = minScore;
    YunetFace? face;
    for (final MapEntry(key: stride, value: layer) in layers.entries) {
      final columns = inputWidth ~/ stride;
      for (var i = 0; i < layer.cls.length; i++) {
        final score = math
            .sqrt(layer.cls[i].clamp(0.0, 1.0) * layer.obj[i].clamp(0.0, 1.0));
        if (score <= best) continue;
        best = score;
        final column = i % columns, row = i ~/ columns;
        Offset landmark(int k) => Offset(
              (layer.kps[i * 10 + 2 * k] + column) * stride,
              (layer.kps[i * 10 + 2 * k + 1] + row) * stride,
            );
        face = (rightEye: landmark(0), leftEye: landmark(1), score: score);
      }
    }
    return face;
  }
}
