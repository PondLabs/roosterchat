import 'dart:async';

import 'package:flutter/widgets.dart';
import 'dart:ui' as ui;

class ImageUtils {
  /// The decoded [provider], or an error when it cannot be decoded (a 404,
  /// a corrupt file, no network).
  ///
  /// The listener is taken off the stream either way: left on, it kept the
  /// decoded image alive in the image cache for ever and, for an animated
  /// image, kept the frames ticking off screen. Without the error path a
  /// caller waited for ever, which is what froze a sticker send or a Linux
  /// notification on one bad image. [timeout] bounds a stream that never
  /// reports either way.
  static Future<ui.Image> imageProviderToImage(ImageProvider provider,
      {Duration? timeout}) {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, synchronousCall) {
      stream.removeListener(listener);
      if (!completer.isCompleted) {
        completer.complete(info.image);
      } else {
        info.dispose();
      }
    }, onError: (error, stackTrace) {
      stream.removeListener(listener);
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    });
    stream.addListener(listener);
    var future = completer.future;
    if (timeout != null) {
      future = future.timeout(timeout, onTimeout: () {
        stream.removeListener(listener);
        throw TimeoutException(
            'the image did not decode in ${timeout.inSeconds} s');
      });
    }
    return future;
  }
}
