import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui';
import 'dart:ui_web' as ui_web;

import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStreamTrack;
// ignore: implementation_imports
import 'package:flutter_webrtc/src/web/rtc_video_renderer_impl.dart'
    show RTCVideoRenderer;
import 'package:web/web.dart' as web;

import 'face_tracker.dart';
import 'face_tracking_engine.dart';
import 'face_worker_requests.dart';
import 'frame_code.dart' as frame_code;
import 'yunet.dart';

/// Face tracking in the browser: YuNet on ONNX Runtime Web in a worker
/// (web/face_tracking/face_tracker_worker.js), reading the video element
/// the renderer already has (docs/adr/0006-face-tracking.md). The worker,
/// ONNX Runtime and the model are downloaded when the first tracker starts,
/// from the app's own files.
class WebFaceTracker implements FaceTrackerPlatform {
  const WebFaceTracker();

  static FaceTrackingEngine? _engine;
  static _Detector? _detector;

  @override
  bool get isSupported =>
      globalContext.has('Worker') &&
      globalContext.has('OffscreenCanvas') &&
      globalContext.has('WebAssembly') &&
      globalContext.has('createImageBitmap');

  @override
  FaceTracker start(FaceVideoSource source, {required bool readFrameCode}) {
    if (!isSupported) {
      throw UnsupportedError('This browser cannot track faces');
    }
    final detector = _detector ??= _Detector();
    return (_engine ??= FaceTrackingEngine()).track(
        _VideoFrames(source.track, detector),
        readFrameCode: readFrameCode);
  }
}

const FaceTrackerPlatform webFaceTracker = WebFaceTracker();

/// This device's face tracking: in a browser, the browser's.
FaceTrackerPlatform get faceTrackerPlatform => webFaceTracker;

/// The frames of a video track, read from the element that shows it.
class _VideoFrames implements FaceFrameSource {
  _VideoFrames(this.track, this.detector);

  final MediaStreamTrack track;
  final _Detector detector;

  @override
  Future<FaceFrame?> grab() async {
    final id = track.id;
    if (id == null) return null;
    final element = RTCVideoRenderer.videoElementShowing(id);
    if (element == null ||
        element.readyState < web.HTMLMediaElement.HAVE_CURRENT_DATA ||
        element.videoWidth == 0) {
      return null;
    }
    final bitmap = await web.window.createImageBitmap(element).toDart;
    return _BitmapFrame(bitmap, detector);
  }
}

class _BitmapFrame implements FaceFrame {
  _BitmapFrame(this.bitmap, this.detector)
      : size = Size(bitmap.width.toDouble(), bitmap.height.toDouble());

  final web.ImageBitmap bitmap;
  final _Detector detector;

  @override
  final Size size;

  /// Hands the frame to the worker at once: it cuts on the GPU and reads
  /// the pixels back while it detects in the frames before this one.
  @override
  FaceCut cut(FaceCrop crop, {required bool readFrameCode}) {
    final source = crop.source;
    return _WorkerCut(
      crop,
      detector,
      detector.cut(_Message(
        type: 'cut',
        frame: bitmap,
        sx: source.left,
        sy: source.top,
        sw: source.width,
        sh: source.height,
        dw: (source.width * crop.scale).round(),
        dh: (source.height * crop.scale).round(),
        width: crop.input.width.round(),
        height: crop.input.height.round(),
        strip: readFrameCode,
      )),
    );
  }

  @override
  void discard() => bitmap.close();
}

class _WorkerCut implements FaceCut {
  _WorkerCut(this.crop, this.detector, this.id);

  final FaceCrop crop;
  final _Detector detector;

  /// The cut's id in the worker; null when it could not be handed over.
  final int? id;

  @override
  Future<FaceDetection> detect() async {
    final reply = await detector.detect(id);
    final face = Yunet.bestFace({
      for (final layer in reply.layers!.toDart)
        layer.stride: (
          cls: layer.cls.toDart,
          obj: layer.obj.toDart,
          kps: layer.kps.toDart,
        ),
    }, inputWidth: crop.input.width.round());
    final cells = reply.cells?.toDart;
    return FaceDetection(
      eyes: face == null
          ? null
          : (rightEye: face.rightEye, leftEye: face.leftEye),
      frameCode: cells == null
          ? null
          : frame_code
              .readFrameCode([for (final cell in cells) cell.toDartDouble]),
    );
  }

  @override
  void discard() => detector.discard(id);
}

/// The worker, started once and shared by every tracker: frames are cut as
/// the engine hands them over, and detected one at a time, as it asks.
class _Detector {
  _Detector() {
    final base = Uri.parse(web.document.baseURI);
    _worker = web.Worker(
      base.resolve('face_tracking/face_tracker_worker.js').toString().toJS,
      web.WorkerOptions(type: 'module'),
    );
    _requests = FaceWorkerRequests<_Reply>(
        (type, id) => _worker.postMessage(_Message(type: type, id: id)));
    _worker.onmessage = (web.MessageEvent event) {
      final reply = event.data as _Reply;
      _requests.answer(reply.id, reply, error: reply.error);
    }.toJS;
    _worker.onerror = (web.Event event) {
      _requests.fail(StateError(event.isA<web.ErrorEvent>()
          ? (event as web.ErrorEvent).message
          : 'the face tracking worker failed'));
    }.toJS;
    final model =
        base.resolve(ui_web.assetManager.getAssetUrl(Yunet.asset)).toString();
    _requests.load((id) =>
        _worker.postMessage(_Message(type: 'load', id: id, model: model)));
  }

  late final web.Worker _worker;
  late final FaceWorkerRequests<_Reply> _requests;

  /// Hands a frame over to be cut, and gives the cut's id; null when the
  /// worker is gone.
  int? cut(_Message message) {
    final id = _requests.nextCut();
    if (id == null) {
      message.frame?.close();
      return null;
    }
    message.id = id;
    _worker.postMessage(message, [message.frame!].toJS);
    return id;
  }

  Future<_Reply> detect(int? id) => _requests.detect(id);

  void discard(int? id) => _requests.discard(id);
}

extension type _Message._(JSObject _) implements JSObject {
  external factory _Message({
    String type,
    int id,
    String? model,
    web.ImageBitmap? frame,
    double sx,
    double sy,
    double sw,
    double sh,
    int dw,
    int dh,
    int width,
    int height,
    bool strip,
  });

  external set id(int value);
  external web.ImageBitmap? get frame;
}

extension type _Reply._(JSObject _) implements JSObject {
  external int get id;
  external String? get error;
  external JSArray<_Layer>? get layers;
  external JSArray<JSNumber>? get cells;
}

extension type _Layer._(JSObject _) implements JSObject {
  external int get stride;
  external JSFloat32Array get cls;
  external JSFloat32Array get obj;
  external JSFloat32Array get kps;
}
