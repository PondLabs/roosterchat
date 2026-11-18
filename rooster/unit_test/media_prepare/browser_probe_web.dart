import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:web/web.dart' as web;

/// A photo-like JPEG drawn in a canvas: a gradient with noise over it, so
/// it is several megabytes like a camera's, and gets a thumbnail.
Future<Uint8List> canvasPhotoJpeg(int width, int height) async {
  final canvas = web.OffscreenCanvas(width, height);
  final context =
      canvas.getContext("2d") as web.OffscreenCanvasRenderingContext2D;
  final gradient = context.createLinearGradient(0, 0, width, height);
  gradient.addColorStop(0, "#c8553d");
  gradient.addColorStop(0.5, "#f2d0a4");
  gradient.addColorStop(1, "#28536b");
  context.fillStyle = gradient;
  context.fillRect(0, 0, width, height);

  // A 256 px tile of soft noise, laid over the whole picture.
  const tile = 256;
  final random = Random(5);
  final noise = Uint8ClampedList(tile * tile * 4);
  for (var i = 0; i < noise.length; i += 4) {
    noise[i] = random.nextInt(256);
    noise[i + 1] = random.nextInt(256);
    noise[i + 2] = random.nextInt(256);
    noise[i + 3] = 60;
  }
  final tileCanvas = web.OffscreenCanvas(tile, tile);
  (tileCanvas.getContext("2d") as web.OffscreenCanvasRenderingContext2D)
      .putImageData(web.ImageData(noise.toJS, tile, tile.toJS), 0, 0);
  for (var y = 0; y < height; y += tile) {
    for (var x = 0; x < width; x += tile) {
      context.drawImage(tileCanvas, x, y);
    }
  }
  // A white square at the top left, to tell the corners apart.
  context.fillStyle = "#ffffff".toJS;
  context.fillRect(0, 0, width / 8, height / 8);

  final blob = await canvas
      .convertToBlob(web.ImageEncodeOptions(type: "image/jpeg", quality: 0.92))
      .toDart;
  final buffer = await blob.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}

/// A noisy PNG whose top-left quarter is fully transparent.
Future<Uint8List> canvasTransparentPng(int width, int height) async {
  final random = Random(9);
  final pixels = Uint8ClampedList(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      pixels[i] = random.nextInt(256);
      pixels[i + 1] = random.nextInt(256);
      pixels[i + 2] = random.nextInt(256);
      pixels[i + 3] = x < width ~/ 4 && y < height ~/ 4 ? 0 : 255;
    }
  }
  final canvas = web.OffscreenCanvas(width, height);
  (canvas.getContext("2d") as web.OffscreenCanvasRenderingContext2D)
      .putImageData(web.ImageData(pixels.toJS, width, height.toJS), 0, 0);
  final blob = await canvas
      .convertToBlob(web.ImageEncodeOptions(type: "image/png"))
      .toDart;
  final buffer = await blob.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}

/// Collects the `longtask` entries (tasks of the page's main thread over
/// 50 ms) while it runs.
class LongTaskObserver {
  LongTaskObserver.start() {
    _observer = web.PerformanceObserver(
        ((web.PerformanceObserverEntryList list, web.PerformanceObserver _) {
      for (final entry in list.getEntries().toDart) {
        _durations.add(entry.duration);
      }
    }).toJS);
    _observer.observe(web.PerformanceObserverInit(type: "longtask"));
  }

  late final web.PerformanceObserver _observer;
  final List<double> _durations = [];

  /// The long tasks seen, in milliseconds. Waits a moment first: entries
  /// are delivered after their task ends.
  Future<List<double>> stop() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final entry in _observer.takeRecords().toDart) {
      _durations.add(entry.duration);
    }
    _observer.disconnect();
    return _durations;
  }
}

/// Holds the main thread for [duration], as a long task would.
void busyFor(Duration duration) {
  final watch = Stopwatch()..start();
  while (watch.elapsed < duration) {}
}
