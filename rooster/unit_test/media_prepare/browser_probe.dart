import 'dart:typed_data';

/// Not in a browser: the web-only tests are skipped before reaching this.
Future<Uint8List> canvasPhotoJpeg(int width, int height) =>
    throw UnsupportedError("browser only");

Future<Uint8List> canvasTransparentPng(int width, int height) =>
    throw UnsupportedError("browser only");

class LongTaskObserver {
  LongTaskObserver.start() {
    throw UnsupportedError("browser only");
  }

  Future<List<double>> stop() => throw UnsupportedError("browser only");
}

void busyFor(Duration duration) => throw UnsupportedError("browser only");
