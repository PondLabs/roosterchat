import 'dart:typed_data';

import 'package:blurhash_dart/blurhash_dart.dart';
import 'package:image/image.dart' as img;
import 'package:rooster/utils/image/preparation/thumbnail_encoder.dart';

/// The blurhash of straight RGBA pixels, computed from a copy at most
/// [blurhashSourceSide] on its long side (4 by 3 components, as the Matrix
/// SDK computes it).
String blurhashOfRgba(Uint8List rgba, int width, int height) {
  final (small, w, h) = downsampleRgba(rgba, width, height, blurhashSourceSide);
  final image = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: small.buffer,
      bytesOffset: small.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba);
  return BlurHash.encode(image, numCompX: 4, numCompY: 3).hash;
}
