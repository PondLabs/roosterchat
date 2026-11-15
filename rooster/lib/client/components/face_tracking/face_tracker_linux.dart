import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:ffi' as ffi show Size;
import 'dart:isolate';
import 'dart:ui' show Offset, Size;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_webrtc/flutter_webrtc.dart' show WebRTC;
import 'package:rooster/config/rust_library.dart';
import 'package:rooster/debug/log.dart';

import 'face_anchor.dart';
import 'face_tracker.dart';

/// Face tracking on Linux: YuNet on tract, in Rooster's Rust library
/// (rust/face_tracking), fed by flutter-webrtc's video renderer: every
/// renderer showing a tracked track hands each frame it draws to the engine
/// (docs/adr/0006-face-tracking.md).
const FaceTrackerPlatform linuxFaceTracker = LinuxFaceTracker();

class LinuxFaceTracker implements FaceTrackerPlatform {
  const LinuxFaceTracker();

  /// Stands in for the Rust library in a test: null for "not there".
  @visibleForTesting
  static FaceTrackingNative? Function()? debugNative;

  static FaceTrackingNative? get _native =>
      debugNative != null ? debugNative!() : FfiFaceTrackingNative.load();

  @override
  bool get isSupported => _native != null;

  @override
  FaceTracker start(FaceVideoSource source, {required bool readFrameCode}) {
    final native = _native;
    if (native == null) {
      throw UnsupportedError('Rooster cannot track faces without its library');
    }
    return NativeFaceTracker(native, source, readFrameCode: readFrameCode);
  }
}

/// One tracker's newest observation, as the engine reports it
/// (`FaceObservation` in rust/face_tracking/src/ffi.rs).
class NativeObservation {
  const NativeObservation({
    required this.seq,
    this.framesDelivered = 0,
    this.width = 0,
    this.height = 0,
    this.found = false,
    this.frameCode = -1,
    this.rightEye = Offset.zero,
    this.leftEye = Offset.zero,
  });

  /// How many frames the engine has analysed: 0 before the first.
  final int seq;

  /// How many frames the video's renderers handed over.
  final int framesDelivered;

  /// The upright frame's size, which the eyes are in.
  final int width;
  final int height;
  final bool found;
  final int frameCode;
  final Offset rightEye;
  final Offset leftEye;
}

/// The engine, as Dart sees it: what [NativeFaceTracker] calls.
abstract class FaceTrackingNative {
  /// Starts the engine, once for the whole app. False when it cannot.
  Future<bool> start();

  /// A new tracker's handle, or 0.
  int newTracker({required bool readFrameCode});

  /// Only once [untap] of [handle] has returned.
  void freeTracker(int handle);

  NativeObservation poll(int handle);

  /// Has the renderers showing [trackId] hand their frames to [handle].
  Future<void> tap(String trackId, int handle);

  /// After this, no frame goes to [handle].
  Future<void> untap(int handle);
}

/// Follows a face through the engine: starts it, taps the video's track,
/// reads the newest observation on every frame the interface could draw.
class NativeFaceTracker implements FaceTracker {
  NativeFaceTracker(this._native, this.source, {required this.readFrameCode}) {
    ready = _start();
  }

  final FaceTrackingNative _native;
  final FaceVideoSource source;
  final bool readFrameCode;

  /// Completes once the track is tapped, or tracking could not start.
  @visibleForTesting
  late final Future<void> ready;

  final _observation = ValueNotifier<FaceObservation?>(null);
  int _handle = 0;
  int _seq = 0;
  int _framesDelivered = 0;
  bool _disposed = false;
  Timer? _timer;

  @override
  ValueListenable<FaceObservation?> get observation => _observation;

  /// How many frames of the video the renderers handed over so far.
  int get framesDelivered => _framesDelivered;

  Future<void> _start() async {
    try {
      if (!await _native.start() || _disposed) return;
      final handle = _native.newTracker(readFrameCode: readFrameCode);
      if (handle == 0) return;
      _handle = handle;
      await _native.tap(source.track.id!, handle);
      if (_disposed) return;
      _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => poll());
    } catch (e) {
      // No observation ever comes: the plaque stays where "no face" puts it.
      Log.w('Face tracking: could not start a tracker: $e');
    }
  }

  /// Reads the engine's newest observation: what the timer does.
  @visibleForTesting
  void poll() {
    if (_handle == 0 || _disposed) return;
    final latest = _native.poll(_handle);
    _framesDelivered = latest.framesDelivered;
    if (latest.seq == _seq) return;
    _seq = latest.seq;
    _observation.value = observationOf(latest, readFrameCode: readFrameCode);
  }

  @visibleForTesting
  static FaceObservation observationOf(
    NativeObservation latest, {
    required bool readFrameCode,
  }) {
    return FaceObservation(
      videoSize: Size(latest.width.toDouble(), latest.height.toDouble()),
      anchor: latest.found
          ? FaceAnchor.fromEyes(
              rightEye: latest.rightEye,
              leftEye: latest.leftEye,
            )
          : null,
      frameCode:
          readFrameCode && latest.frameCode >= 0 ? latest.frameCode : null,
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _observation.dispose();
    // The handle goes once the plugin stops handing it frames: after the
    // start that made it, and after the untap.
    unawaited(ready.whenComplete(() async {
      final handle = _handle;
      if (handle == 0) return;
      _handle = 0;
      try {
        await _native.untap(handle);
        _native.freeTracker(handle);
      } catch (e) {
        // The plugin did not answer: better a handle kept than one freed
        // while it may still get frames.
        Log.w('Face tracking: could not stop a tracker: $e');
      }
    }));
  }
}

/// Mirrors `FaceObservation` in rust/face_tracking/src/ffi.rs.
final class _FaceObservationStruct extends Struct {
  @Uint64()
  external int seq;
  @Uint64()
  external int framesDelivered;
  @Uint32()
  external int width;
  @Uint32()
  external int height;
  @Uint32()
  external int found;
  @Int32()
  external int frameCode;
  @Float()
  external double rightX;
  @Float()
  external double rightY;
  @Float()
  external double leftX;
  @Float()
  external double leftY;
}

/// The engine in librust_lib_rooster, through its C ABI.
class FfiFaceTrackingNative implements FaceTrackingNative {
  FfiFaceTrackingNative._(DynamicLibrary lib)
      : _newTracker = lib.lookupFunction<Pointer<Void> Function(Uint8),
            Pointer<Void> Function(int)>('rooster_face_tracker_new'),
        _freeTracker = lib.lookupFunction<Void Function(Pointer<Void>),
            void Function(Pointer<Void>)>('rooster_face_tracker_free'),
        _poll = lib.lookupFunction<
            Void Function(Pointer<Void>, Pointer<_FaceObservationStruct>),
            void Function(Pointer<Void>,
                Pointer<_FaceObservationStruct>)>('rooster_face_tracker_poll'),
        _frameAddress = lib
            .lookup<
                NativeFunction<
                    Void Function(
                        Pointer<Void>,
                        Int32,
                        Int32,
                        Int32,
                        Pointer<Uint8>,
                        Int32,
                        Pointer<Uint8>,
                        Int32,
                        Pointer<Uint8>,
                        Int32)>>('rooster_face_frame')
            .address;

  /// Bump with `ABI_VERSION` in rust/face_tracking/src/ffi.rs.
  static const abiVersion = 1;

  /// How many threads detect, for every tracker of the app: eight videos
  /// following faces take about one (docs/adr/0006-face-tracking.md).
  static const workers = 2;

  static const modelAsset =
      'assets/face_tracking/face_detection_yunet_2023mar_dynamic.onnx';

  static FfiFaceTrackingNative? _instance;
  static bool _tried = false;

  /// Null when the library is missing or has no face tracking.
  static FfiFaceTrackingNative? load() {
    if (_tried) return _instance;
    _tried = true;
    final lib = openRustLibrary();
    if (lib == null) return null;
    try {
      final version = lib.lookupFunction<Uint32 Function(), int Function()>(
          'rooster_face_abi_version')();
      if (version != abiVersion) {
        Log.w('Face tracking: library ABI $version, expected $abiVersion');
        return null;
      }
      return _instance = FfiFaceTrackingNative._(lib);
    } catch (e) {
      Log.w('Face tracking: not in the Rust library: $e');
      return null;
    }
  }

  final Pointer<Void> Function(int) _newTracker;
  final void Function(Pointer<Void>) _freeTracker;
  final void Function(Pointer<Void>, Pointer<_FaceObservationStruct>) _poll;
  final int _frameAddress;
  final Pointer<_FaceObservationStruct> _out = calloc<_FaceObservationStruct>();

  Future<bool>? _started;

  @override
  Future<bool> start() => _started ??= _start();

  Future<bool> _start() async {
    final data = await rootBundle.load(modelAsset);
    final model =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    // Building the model's plans takes a moment: off the interface's thread.
    final result = await Isolate.run(() => _startEngine(model));
    if (result < 0) {
      Log.w('Face tracking: the engine did not start ($result)');
      return false;
    }
    return true;
  }

  static int _startEngine(Uint8List model) {
    final lib = openRustLibrary();
    if (lib == null) return -3;
    final start = lib.lookupFunction<
        Int32 Function(Pointer<Uint8>, ffi.Size, Uint32),
        int Function(Pointer<Uint8>, int, int)>('rooster_face_engine_start');
    final bytes = malloc<Uint8>(model.length);
    try {
      bytes.asTypedList(model.length).setAll(0, model);
      return start(bytes, model.length, workers);
    } finally {
      malloc.free(bytes);
    }
  }

  @override
  int newTracker({required bool readFrameCode}) =>
      _newTracker(readFrameCode ? 1 : 0).address;

  @override
  void freeTracker(int handle) => _freeTracker(Pointer.fromAddress(handle));

  @override
  NativeObservation poll(int handle) {
    _poll(Pointer.fromAddress(handle), _out);
    final out = _out.ref;
    return NativeObservation(
      seq: out.seq,
      framesDelivered: out.framesDelivered,
      width: out.width,
      height: out.height,
      found: out.found != 0,
      frameCode: out.frameCode,
      rightEye: Offset(out.rightX, out.rightY),
      leftEye: Offset(out.leftX, out.leftY),
    );
  }

  @override
  Future<void> tap(String trackId, int handle) async {
    await WebRTC.invokeMethod('roosterTapVideoTrack', <String, dynamic>{
      'trackId': trackId,
      'ctx': handle,
      'frame': _frameAddress,
    });
  }

  @override
  Future<void> untap(int handle) async {
    await WebRTC.invokeMethod(
        'roosterUntapVideoTrack', <String, dynamic>{'ctx': handle});
  }
}
