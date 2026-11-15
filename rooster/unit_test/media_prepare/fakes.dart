import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';
import 'package:rooster/utils/image/preparation/thumbnail_encoder.dart';

class NoFrames implements FrameSource {
  @override
  void listen(void Function(Duration frame) onFrame) {}
  @override
  void cancel() {}
}

/// One call to the codec factory: what it was asked for.
class DecodeCall {
  DecodeCall(this.bytes, this.targetWidth, this.targetHeight);
  final Uint8List bytes;
  final int? targetWidth;
  final int? targetHeight;
}

/// Stands in for the engine: makes [FakeCodec]s that give a [FakeImage]
/// of [width] by [height] (or the asked size), counting what it creates
/// and what is disposed.
class FakeEngine {
  FakeEngine({
    this.width = 800,
    this.height = 600,
    this.frames = 1,
    this.gate,
    this.failPixels = false,
  });

  final int width;
  final int height;
  final int frames;

  /// When set, a decode waits for it.
  Future<void> Function()? gate;

  /// toByteData throws.
  final bool failPixels;

  final List<DecodeCall> calls = [];
  final List<FakeCodec> codecs = [];
  final List<FakeImage> images = [];

  /// Decodes in progress (from the call until the image is disposed).
  int open = 0;
  int peakOpen = 0;

  Future<ui.Codec> codec(Uint8List bytes,
      {int? targetWidth, int? targetHeight}) async {
    calls.add(DecodeCall(bytes, targetWidth, targetHeight));
    open++;
    if (open > peakOpen) peakOpen = open;
    await gate?.call();
    final codec = FakeCodec(this, targetWidth, targetHeight);
    codecs.add(codec);
    return codec;
  }
}

class FakeCodec implements ui.Codec {
  FakeCodec(this._engine, this._targetWidth, this._targetHeight);
  final FakeEngine _engine;
  final int? _targetWidth;
  final int? _targetHeight;
  int disposed = 0;

  @override
  int get frameCount => _engine.frames;

  @override
  int get repetitionCount => 0;

  @override
  Future<ui.FrameInfo> getNextFrame() async {
    var w = _engine.width;
    var h = _engine.height;
    if (_targetWidth != null) {
      h = (h * _targetWidth / w).round();
      w = _targetWidth;
    } else if (_targetHeight != null) {
      w = (w * _targetHeight / h).round();
      h = _targetHeight;
    }
    final image = FakeImage(_engine, w, h);
    _engine.images.add(image);
    return _FakeFrame(image);
  }

  @override
  void dispose() => disposed++;
}

class _FakeFrame implements ui.FrameInfo {
  _FakeFrame(this.image);
  @override
  final ui.Image image;
  @override
  Duration get duration => Duration.zero;
}

class FakeImage implements ui.Image {
  FakeImage(this._engine, this.width, this.height);
  final FakeEngine _engine;
  @override
  final int width;
  @override
  final int height;
  int disposed = 0;

  @override
  Future<ByteData?> toByteData(
      {ui.ImageByteFormat format = ui.ImageByteFormat.rawRgba}) async {
    if (_engine.failPixels) throw StateError("no pixels");
    final rgba = Uint8List(width * height * 4);
    for (var i = 0; i < rgba.length; i++) {
      rgba[i] = i % 4 == 3 ? 0xFF : (i * 7) & 0xFF;
    }
    return ByteData.sublistView(rgba);
  }

  @override
  void dispose() {
    disposed++;
    _engine.open--;
  }

  @override
  bool get debugDisposed => disposed > 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Returns a fixed thumbnail and blurhash, recording what it was given.
class FakeEncoder implements ThumbnailEncoder {
  final List<ThumbnailRequest> requests = [];

  @override
  Future<ThumbnailResult> encode(ThumbnailRequest request) async {
    requests.add(request);
    final maxSide = request.maxSide;
    if (maxSide == null) return const ThumbnailResult(blurhash: "LKO2?U%2Tw=w");
    final (w, h) = fitWithin(request.width, request.height, maxSide);
    return ThumbnailResult(
      blurhash: "LKO2?U%2Tw=w",
      thumbnail: PreparedThumbnail(
          bytes: Uint8List(10), mimeType: "image/jpeg", width: w, height: h),
    );
  }
}

ImagePreparer fakePreparer(FakeEngine engine,
        {FakeEncoder? encoder, SpeedLog? log}) =>
    ImagePreparer(
      codecFactory: engine.codec,
      encoder: encoder ?? FakeEncoder(),
      log: log ?? SpeedLog(frames: NoFrames()),
    );

/// A JPEG's header (SOI, an Exif APP1 when [orientation] is given, SOF0)
/// padded with zeros to [length] bytes: enough for the header reader, not
/// a picture any decoder would draw.
Uint8List fakeJpegHeader(int width, int height,
    {int? orientation, int length = 400 * 1000}) {
  final bytes = <int>[0xFF, 0xD8];
  if (orientation != null) {
    final tiff = [
      0x4D, 0x4D, 0, 42, 0, 0, 0, 8, 0, 1, //
      0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, orientation, 0, 0, 0, 0, 0, 0,
    ];
    final payload = [..."Exif".codeUnits, 0, 0, ...tiff];
    bytes.addAll([0xFF, 0xE1, 0, payload.length + 2, ...payload]);
  }
  bytes.addAll([
    0xFF, 0xC0, 0, 11, 8, height >> 8, height & 0xFF, width >> 8, //
    width & 0xFF, 1, 1, 0x11, 0,
  ]);
  final out = Uint8List(length < bytes.length ? bytes.length : length);
  out.setAll(0, bytes);
  return out;
}
