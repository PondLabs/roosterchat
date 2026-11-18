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
///    blurhash's ([blurhashSourceSide]) when no thumbnail is due, or at the
///    reduced photo's ([photoMaxSide]) for a photo to reduce; a BMP at
///    full size, and the engine encodes that decode as the PNG it is sent
///    as ([ImagePreparation.png]); the codec and image are disposed right
///    after the pixels are read;
/// 3. encodes the thumbnail (JPEG at quality 80, PNG with transparency)
///    and the blurhash with [ThumbnailEncoder]: a background isolate on
///    native, the browser's canvas on the web. A photo to reduce (`reduce`,
///    a JPEG over [photoMaxSide] on its long side) is encoded there too, as
///    a JPEG at [photoJpegQuality] without metadata
///    ([ImagePreparation.reduced]), and its thumbnail made from it. Any
///    other picture is never encoded again: it is sent as attached.
///
/// At most [ImagePreparer.maxConcurrent] (2) files are prepared at a time;
/// the others wait their turn. A [PreparationCancel] drops a preparation
/// nobody needs any more (an attachment removed before Send): out of the
/// queue before its turn, or its result thrown away once it has started. Each preparation is an `image_prepare` span
/// in the speed log, with its steps and sizes (no names, no content), and
/// the outcome `encode_failed` when the thumbnail encoder failed. The
/// encoder's step is `reduce` instead of `encode` for a reduced photo.
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
        ReducedPhoto,
        ThumbnailEncoder,
        blurhashSourceSide,
        photoJpegQuality,
        photoMaxSide,
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
    this.png,
    this.reduced,
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

  /// A BMP as a PNG, encoded by the engine from the preparation's one
  /// decode (at full size for a BMP): it is sent as this PNG, since other
  /// clients do not all draw BMP. Null for any other picture, and when the
  /// engine could not encode it.
  final Uint8List? png;

  /// The photo reduced for sending (see [photoReducedSize]), when it was
  /// asked for and the encoder made it; null for any other picture. Sent
  /// in place of the attached bytes when it is smaller than them.
  final ReducedPhoto? reduced;

  bool get animated => frames > 1;
}

/// The size a picture with [header] is sent at when photos are reduced:
/// a JPEG larger than [photoMaxSide] on its long side, scaled to it, as
/// displayed (orientation applied). Null for any other picture, which is
/// sent at its own size and never encoded again.
(int, int)? photoReducedSize(ImageHeader header) {
  if (header.mimeType != "image/jpeg") return null;
  if (max(header.width, header.height) <= photoMaxSide) return null;
  return fitWithin(header.width, header.height, photoMaxSide);
}

/// Makes the engine's codec for [bytes], decoding at [targetWidth] and
/// [targetHeight] when given: a thumbnail asks for one of them (the other
/// follows the aspect ratio), a photo to reduce for both, its reduced size.
/// Replaced in tests to count decodes.
typedef ImageCodecFactory = Future<ui.Codec> Function(Uint8List bytes,
    {int? targetWidth, int? targetHeight});

Future<ui.Codec> engineImageCodec(Uint8List bytes,
        {int? targetWidth, int? targetHeight}) =>
    ui.instantiateImageCodec(bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
        allowUpscaling: false);

/// Drops one preparation: [cancel] takes it out of the queue when it has
/// not started, and makes it end with null, without its thumbnail being
/// encoded, when it has.
class PreparationCancel {
  bool _cancelled = false;
  void Function()? _leaveQueue;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final leave = _leaveQueue;
    _leaveQueue = null;
    leave?.call();
  }
}

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
  /// is then sent as a plain file, as before), and when [cancel] dropped
  /// it. With [reduce], a photo larger than [photoMaxSide] is also
  /// reduced ([ImagePreparation.reduced]). Never throws.
  Future<ImagePreparation?> prepare(Uint8List bytes,
      {PreparationCancel? cancel, bool reduce = false}) async {
    final span = _log.startSpan(SpeedOperation.imagePrepare);
    if (!await _acquire(cancel)) {
      span.finish(outcome: SpeedOutcome.cancelled);
      return null;
    }
    span.mark(SpeedStep.queueWait);
    try {
      final result = await _prepare(bytes, span, cancel, reduce: reduce);
      if (cancel?.isCancelled == true) {
        span.finish(outcome: SpeedOutcome.cancelled);
        return null;
      }
      span.finish(
          outcome: switch (result) {
        null => SpeedOutcome.failed,
        (_, encodeFailed: true) => SpeedOutcome.encodeFailed,
        _ => SpeedOutcome.ok,
      });
      return result?.$1;
    } catch (_) {
      span.finish(outcome: SpeedOutcome.failed);
      return null;
    } finally {
      _release();
    }
  }

  /// Waits for a slot: true once it has one, false when [cancel] dropped
  /// the preparation first (it never takes a slot then).
  Future<bool> _acquire(PreparationCancel? cancel) {
    if (cancel?.isCancelled == true) return Future.value(false);
    if (_running < maxConcurrent) {
      _running++;
      return Future.value(true);
    }
    final turn = Completer<bool>();
    _waiting.add(turn);
    cancel?._leaveQueue = () {
      if (_waiting.remove(turn)) turn.complete(false);
    };
    return turn.future.whenComplete(() => cancel?._leaveQueue = null);
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      // The slot passes straight to the next one: [_running] stays.
      _waiting.removeFirst().complete(true);
    } else {
      _running--;
    }
  }

  /// The preparation, and whether its thumbnail encoder failed.
  Future<(ImagePreparation, {bool encodeFailed})?> _prepare(
      Uint8List bytes, SpeedSpan span, PreparationCancel? cancel,
      {required bool reduce}) async {
    final header = readImageHeader(bytes);
    span.mark(SpeedStep.header, values: {SpeedValue.bytes: bytes.length});

    // Which side to ask the engine for: the long one as the header shows
    // the picture. Without a header the decode is at full size, the old
    // way, and the size comes from it.
    bool wantsThumbnail(int width, int height) =>
        max(width, height) > thumbnailMaxSide &&
        bytes.length >= thumbnailMinSourceBytes;
    int? targetWidth, targetHeight;
    // A BMP is sent as a PNG of all of it: decoded at full size, and the
    // PNG made from that same decode. Known by its "BM" too when the
    // header reader does not know its info header (OS/2 2.x, 16 to 39
    // bytes), which the engine still decodes.
    final asPng = header?.mimeType == "image/bmp" ||
        (header == null &&
            bytes.length >= 2 &&
            bytes[0] == 0x42 && // B
            bytes[1] == 0x4D); // M
    // A photo to reduce is decoded at exactly the size the attach dialog
    // says it is sent at ([photoReducedSize], both sides given so the
    // engine does not round one of them its own way): the photo, its
    // thumbnail and its blurhash all come from that one decode, and the
    // event's w and h are that size.
    final reducedSize =
        reduce && header != null ? photoReducedSize(header) : null;
    final reduceTo = reducedSize == null ? null : photoMaxSide;
    if (reducedSize != null) {
      (targetWidth, targetHeight) = reducedSize;
    } else if (header != null && !asPng) {
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

    final decoded = await _decode(bytes, targetWidth, targetHeight, png: asPng);
    // Dropped while it decoded: the codec and image are already disposed,
    // and nothing is encoded.
    if (decoded == null || cancel?.isCancelled == true) return null;
    final (rgba, drawnWidth, drawnHeight, frames, png) = decoded;
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
    var encodeFailed = false;
    try {
      encoded = await _encoder.encode(ThumbnailRequest(
        rgba: rgba,
        width: drawnWidth,
        height: drawnHeight,
        maxSide: thumbnail ? thumbnailMaxSide : null,
        mayHaveAlpha: header?.mimeType != "image/jpeg",
        reduceTo: reduceTo,
      ));
    } catch (_) {
      // The picture decoded: it still goes as a picture, with its size,
      // only without a thumbnail and a blurhash.
      encoded = const ThumbnailResult();
      encodeFailed = true;
    }
    if (reduceTo != null) {
      span.mark(SpeedStep.reduce, values: {
        if (encoded.reduced case final reduced?) ...{
          SpeedValue.bytes: reduced.bytes.length,
          SpeedValue.width: reduced.width,
          SpeedValue.height: reduced.height,
        },
      });
    } else {
      span.mark(SpeedStep.encode, values: {
        if (encoded.thumbnail != null) ...{
          SpeedValue.bytes: encoded.thumbnail!.bytes.length,
          SpeedValue.width: encoded.thumbnail!.width,
          SpeedValue.height: encoded.thumbnail!.height,
        },
      });
    }

    return (
      ImagePreparation(
        width: width,
        height: height,
        frames: frames,
        mimeType: header?.mimeType,
        blurhash: encoded.blurhash,
        thumbnail: encoded.thumbnail,
        png: png,
        reduced: encoded.reduced,
      ),
      encodeFailed: encodeFailed,
    );
  }

  /// The one decode: the first frame's straight RGBA, its size, how many
  /// frames there are, and the frame as a PNG when [png] (null when the
  /// engine could not encode it). The codec and the image are disposed
  /// whatever happens.
  Future<(Uint8List, int, int, int, Uint8List?)?> _decode(
      Uint8List bytes, int? targetWidth, int? targetHeight,
      {required bool png}) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await _codecFactory(bytes,
          targetWidth: targetWidth, targetHeight: targetHeight);
      image = (await codec.getNextFrame()).image;
      final data =
          await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (data == null) return null;
      Uint8List? encoded;
      if (png) {
        try {
          final out = await image.toByteData(format: ui.ImageByteFormat.png);
          encoded =
              out?.buffer.asUint8List(out.offsetInBytes, out.lengthInBytes);
        } catch (_) {
          // Sent as the BMP it is.
        }
      }
      return (
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        image.width,
        image.height,
        codec.frameCount,
        encoded,
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
