/// One preparation per attached picture: what sending it needs, worked out
/// once, in the background, from the moment the file is attached.
///
/// ```dart
/// // When a file is attached (chat.dart does this for every attachment):
/// attachment.startImagePreparation();
///
/// // At Send, or later (T2.3's pending message, T5.1's reduced photos):
/// final prepared = await attachment.imagePreparation(); // the same one
/// prepared?.width;      // as displayed, Exif orientation applied
/// prepared?.blurhash;
/// prepared?.thumbnail;  // null: send without one (small or animated)
/// ```
///
/// `ImagePreparer.prepare` underneath does, for one file:
/// 1. reads width, height and orientation from the header
///    (`readImageHeader`), no decode;
/// 2. decodes once with the engine (`ui.instantiateImageCodec`), already at
///    the thumbnail's size ([thumbnailMaxSide] on the long side), or at the
///    blurhash's ([blurhashSourceSide]) when no thumbnail is due; the codec
///    and image are disposed right after the pixels are read;
/// 3. encodes the thumbnail (JPEG at quality 80, PNG with transparency)
///    and the blurhash with [ThumbnailEncoder]: a background isolate on
///    native, the browser's canvas on the web.
///
/// At most [ImagePreparer.maxConcurrent] (2) files are prepared at a time;
/// the others wait their turn. Each preparation is an `image_prepare` span
/// in the speed log, with its steps and sizes (no names, no content).
library;

import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/utils/image/image_header.dart';
import 'package:rooster/utils/image/preparation/thumbnail_encoder.dart';

export 'package:rooster/utils/image/preparation/thumbnail_encoder.dart'
    show
        PreparedThumbnail,
        ThumbnailEncoder,
        blurhashSourceSide,
        thumbnailJpegQuality;

/// A thumbnail is at most this many pixels on its long side.
const int thumbnailMaxSide = 800;

/// A source this size or larger (bytes), and larger than
/// [thumbnailMaxSide] on its long side, gets a thumbnail; a smaller one is
/// sent alone, since a thumbnail would barely save anything.
const int thumbnailMinSourceBytes = 300 * 1000;

/// What sending a picture needs.
class ImagePreparation {
  const ImagePreparation({
    required this.width,
    required this.height,
    required this.frames,
    this.mimeType,
    this.blurhash,
    this.thumbnail,
  });

  /// The size the picture is shown at: the header's, with the sides
  /// swapped when the engine draws it turned a quarter (Exif orientations
  /// 5 to 8, as the engine reads them).
  final int width;
  final int height;

  /// From the header; null when the header could not be read and the
  /// picture was only known from its decode.
  final String? mimeType;

  /// The frames the engine found: more than 1 is an animation, which is
  /// sent without a thumbnail so the timeline plays it.
  final int frames;

  final String? blurhash;

  /// Null for a picture sent without one: at most [thumbnailMaxSide] on
  /// its long side, smaller than [thumbnailMinSourceBytes], animated, or
  /// when the encoder failed (the blurhash is then null too).
  final PreparedThumbnail? thumbnail;

  bool get animated => frames > 1;
}

/// Makes the engine's codec for [bytes], decoding at [targetWidth] or
/// [targetHeight] when given (one of them, the other follows the aspect
/// ratio). Replaced in tests to count decodes.
typedef ImageCodecFactory = Future<ui.Codec> Function(Uint8List bytes,
    {int? targetWidth, int? targetHeight});

Future<ui.Codec> engineImageCodec(Uint8List bytes,
        {int? targetWidth, int? targetHeight}) =>
    ui.instantiateImageCodec(bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
        allowUpscaling: false);

/// Prepares pictures, at most [maxConcurrent] at a time.
class ImagePreparer {
  ImagePreparer({
    ImageCodecFactory? codecFactory,
    ThumbnailEncoder? encoder,
    SpeedLog? log,
    this.maxConcurrent = 2,
  })  : _codecFactory = codecFactory ?? engineImageCodec,
        _encoder = encoder ?? ThumbnailEncoder.platformDefault(),
        _log = log ?? SpeedLog.instance;

  /// The app's preparer: every attachment goes through it, so the limit
  /// holds across chats and accounts.
  static ImagePreparer instance = ImagePreparer();

  final ImageCodecFactory _codecFactory;
  final ThumbnailEncoder _encoder;
  final SpeedLog _log;
  final int maxConcurrent;

  int _running = 0;
  final Queue<Completer<void>> _waiting = Queue();

  /// Preparations under way now (not waiting for a slot).
  int get running => _running;

  /// Prepares [bytes]; null when the engine cannot decode them (the file
  /// is then sent as a plain file, as before). Never throws.
  Future<ImagePreparation?> prepare(Uint8List bytes) async {
    final span = _log.startSpan(SpeedOperation.imagePrepare);
    await _acquire();
    span.mark(SpeedStep.queueWait);
    try {
      final result = await _prepare(bytes, span);
      span.finish(
          outcome: result == null ? SpeedOutcome.failed : SpeedOutcome.ok);
      return result;
    } catch (_) {
      span.finish(outcome: SpeedOutcome.failed);
      return null;
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_running < maxConcurrent) {
      _running++;
      return Future.value();
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    return turn.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      // The slot passes straight to the next one: [_running] stays.
      _waiting.removeFirst().complete();
    } else {
      _running--;
    }
  }

  Future<ImagePreparation?> _prepare(Uint8List bytes, SpeedSpan span) async {
    final header = readImageHeader(bytes);
    span.mark(SpeedStep.header, values: {SpeedValue.bytes: bytes.length});

    // Which side to ask the engine for: the long one as the header shows
    // the picture. Without a header the decode is at full size, the old
    // way, and the size comes from it.
    bool wantsThumbnail(int width, int height) =>
        max(width, height) > thumbnailMaxSide &&
        bytes.length >= thumbnailMinSourceBytes;
    int? targetWidth, targetHeight;
    if (header != null) {
      final long = max(header.width, header.height);
      final side = wantsThumbnail(header.width, header.height)
          ? thumbnailMaxSide
          : min(blurhashSourceSide, long);
      if (side < long) {
        if (header.width >= header.height) {
          targetWidth = side;
        } else {
          targetHeight = side;
        }
      }
    }

    final decoded = await _decode(bytes, targetWidth, targetHeight);
    if (decoded == null) return null;
    final (rgba, drawnWidth, drawnHeight, frames) = decoded;
    span.mark(SpeedStep.decode, values: {
      SpeedValue.width: drawnWidth,
      SpeedValue.height: drawnHeight,
      SpeedValue.frames: frames,
    });

    final (width, height) = header == null
        ? (drawnWidth, drawnHeight)
        : asDrawn(header, drawnWidth, drawnHeight);
    final thumbnail = frames <= 1 && wantsThumbnail(width, height);

    ThumbnailResult encoded;
    try {
      encoded = await _encoder.encode(ThumbnailRequest(
        rgba: rgba,
        width: drawnWidth,
        height: drawnHeight,
        maxSide: thumbnail ? thumbnailMaxSide : null,
        mayHaveAlpha: header?.mimeType != "image/jpeg",
      ));
    } catch (_) {
      // The picture decoded: it still goes as a picture, with its size,
      // only without a thumbnail and a blurhash.
      encoded = const ThumbnailResult();
    }
    span.mark(SpeedStep.encode, values: {
      if (encoded.thumbnail != null) ...{
        SpeedValue.bytes: encoded.thumbnail!.bytes.length,
        SpeedValue.width: encoded.thumbnail!.width,
        SpeedValue.height: encoded.thumbnail!.height,
      },
    });

    return ImagePreparation(
      width: width,
      height: height,
      frames: frames,
      mimeType: header?.mimeType,
      blurhash: encoded.blurhash,
      thumbnail: encoded.thumbnail,
    );
  }

  /// The one decode: the first frame's straight RGBA, its size, and how
  /// many frames there are. The codec and the image are disposed whatever
  /// happens.
  Future<(Uint8List, int, int, int)?> _decode(
      Uint8List bytes, int? targetWidth, int? targetHeight) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await _codecFactory(bytes,
          targetWidth: targetWidth, targetHeight: targetHeight);
      image = (await codec.getNextFrame()).image;
      final data =
          await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (data == null) return null;
      return (
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        image.width,
        image.height,
        codec.frameCount,
      );
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }
}

/// The picture's size as the engine drew it: the header's displayed size,
/// or its sides swapped when the decoded image's aspect ratio says the
/// engine turned it the other way than the header's orientation suggests
/// (a WebP with an `Exif\0\0`-prefixed block, a decoder that ignores a
/// tag). Exact sizes come from the header, the turn from the engine.
(int, int) asDrawn(ImageHeader header, int drawnWidth, int drawnHeight) {
  final w = header.width;
  final h = header.height;
  final asRead = (drawnWidth * h - drawnHeight * w).abs();
  final turned = (drawnWidth * w - drawnHeight * h).abs();
  return turned < asRead ? (h, w) : (w, h);
}
