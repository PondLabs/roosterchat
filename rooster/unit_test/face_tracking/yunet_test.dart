import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/face_tracking/frame_code.dart';
import 'package:rooster/client/components/face_tracking/yunet.dart';

/// YuNet's outputs for an input of [width] x [height] with nothing in it,
/// and a way to put a face at one cell.
class _Outputs {
  _Outputs(this.width, this.height)
      : layers = {
          for (final stride in Yunet.strides)
            stride: (
              cls: Float32List(width ~/ stride * (height ~/ stride)),
              obj: Float32List(width ~/ stride * (height ~/ stride)),
              kps: Float32List(width ~/ stride * (height ~/ stride) * 10),
            ),
        };

  final int width;
  final int height;
  final Map<int, YunetLayer> layers;

  /// A face of [score] at column [column], row [row] of the [stride] grid,
  /// with its eyes [rightEye] and [leftEye] in cells from that cell.
  void face(int stride, int column, int row, double score,
      {Offset rightEye = const Offset(0.2, 0.3),
      Offset leftEye = const Offset(0.8, 0.3)}) {
    final layer = layers[stride]!;
    final i = row * (width ~/ stride) + column;
    layer.cls[i] = score;
    layer.obj[i] = score;
    layer.kps
      ..[i * 10] = rightEye.dx
      ..[i * 10 + 1] = rightEye.dy
      ..[i * 10 + 2] = leftEye.dx
      ..[i * 10 + 3] = leftEye.dy;
  }

  YunetFace? best() => Yunet.bestFace(layers, inputWidth: width);
}

void main() {
  group('Yunet.bestFace', () {
    test('an empty picture has no face', () {
      expect(_Outputs(128, 128).best(), isNull);
    });

    test('the eyes are in pixels of the input: cell plus offset, by stride',
        () {
      final outputs = _Outputs(320, 256)..face(16, 5, 3, 0.9);

      final face = outputs.best()!;
      expect(face.rightEye.dx, closeTo((5 + 0.2) * 16, 1e-4));
      expect(face.rightEye.dy, closeTo((3 + 0.3) * 16, 1e-4));
      expect(face.leftEye.dx, closeTo((5 + 0.8) * 16, 1e-4));
      expect(face.leftEye.dy, closeTo((3 + 0.3) * 16, 1e-4));
      expect(face.score, closeTo(0.9, 1e-6));
    });

    test('rows wrap at the width of the grid of each stride', () {
      final outputs = _Outputs(320, 256)..face(32, 0, 2, 0.9);

      expect(outputs.best()!.rightEye.dy, closeTo((2 + 0.3) * 32, 1e-4));
      expect(outputs.best()!.rightEye.dx, closeTo(0.2 * 32, 1e-4));
    });

    test('the score is the geometric mean of class and objectness', () {
      final outputs = _Outputs(128, 128)..face(8, 1, 1, 0.9);
      outputs.layers[8]!.obj[1 * 16 + 1] = 0.64;

      expect(outputs.best()!.score, closeTo(0.759, 1e-3));
    });

    test('a face scored under 0.6 is not a face', () {
      expect((_Outputs(128, 128)..face(8, 1, 1, 0.59)).best(), isNull);
      expect((_Outputs(128, 128)..face(8, 1, 1, 0.61)).best(), isNotNull);
    });

    test('scores past 1 count as 1', () {
      final outputs = _Outputs(128, 128)..face(8, 1, 1, 1.4);

      expect(outputs.best()!.score, 1);
    });

    test('of several faces, the surest', () {
      final outputs = _Outputs(128, 128)
        ..face(8, 1, 1, 0.7)
        ..face(32, 2, 3, 0.95)
        ..face(16, 4, 4, 0.8);

      expect(outputs.best()!.score, closeTo(0.95, 1e-6));
      expect(outputs.best()!.rightEye.dx, closeTo((2 + 0.2) * 32, 1e-4));
    });
  });

  group('readFrameCode', () {
    // The cells of tools/face_tracking/frame_code.py, as 0 and 255.
    List<double> cells(int code) {
      final bits = [
        for (var shift = 15; shift >= 0; shift--) code >> shift & 1
      ];
      final parity = bits.fold(0, (a, b) => a + b) & 1;
      return [1, 0, ...bits, parity, 0].map((b) => b * 255.0).toList();
    }

    test('reads the frame number', () {
      for (final code in [0, 1, 34, 1145, 0xFFFF]) {
        expect(readFrameCode(cells(code)), code);
      }
    });

    test('reads a code dimmed and washed out by the video codec', () {
      final seen = cells(731).map((v) => v * 0.6 + 40).toList();

      expect(readFrameCode(seen), 731);
    });

    test('a frame without the white and black start has no code', () {
      expect(readFrameCode(List.filled(20, 128)), isNull);
      final seen = cells(731)..[0] = 50;
      expect(readFrameCode(seen), isNull);
    });

    test('a wrong parity or a white end is no code', () {
      final parity = cells(731)..[18] = 255 - cells(731)[18];
      expect(readFrameCode(parity), isNull);
      final end = cells(731)..[19] = 255;
      expect(readFrameCode(end), isNull);
    });
  });
}
