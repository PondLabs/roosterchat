// Desktop: our own presses go to the call on a track of their own, the way
// the DJ booth's music does (native_dj_engine.dart). The clip is decoded by
// rust/dj_audio (src/clip.rs) and mixed by its board (src/board.rs), which
// flutter-webrtc's custom source pulls from every 10 ms, so overlapping
// presses are one track. Published on the first press, so only people who
// use the soundboard send one, and kept until the call ends.
import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:rooster/client/components/soundboard/soundboard_constraints.dart';
import 'package:rooster/client/components/soundboard/soundboard_engine.dart';
import 'package:rooster/client/matrix/components/soundboard/native/soundboard_clip_codec.dart';
import 'package:rooster/client/matrix/components/soundboard/soundboard_player_factory.dart';
import 'package:rooster/client/matrix/components/voip_room/livekit_microphone.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:rooster/config/rust_library.dart';
import 'package:rooster/debug/log.dart';
// ignore: implementation_imports
import 'package:flutter_webrtc/src/native/media_stream_impl.dart'
    show MediaStreamNative;

typedef _NewNative = Pointer<Void> Function();
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _Free = void Function(Pointer<Void>);
typedef _PlayNative = Int32 Function(
    Pointer<Void>, Uint64, Pointer<Float>, Size, Float);
typedef _Play = int Function(Pointer<Void>, int, Pointer<Float>, int, double);
typedef _StopNative = Void Function(Pointer<Void>, Uint64);
typedef _Stop = void Function(Pointer<Void>, int);
typedef _PullNative = Size Function(
    Pointer<Void>, Pointer<Int16>, Size, Size, Int32);

class _Board {
  static const abiVersion = 1;

  final Pointer<Void> Function() create;
  final _Free free;
  final _Play play;
  final _Stop stop;
  final int pullAddress;

  _Board._(this.create, this.free, this.play, this.stop, this.pullAddress);

  static _Board? _instance;
  static bool _tried = false;

  /// Null when the library is missing (Android, macOS) or predates the
  /// board.
  static _Board? load() {
    if (_tried) return _instance;
    _tried = true;
    if (!(Platform.isLinux || Platform.isWindows)) return null;
    final lib = openRustLibrary();
    if (lib == null) return null;
    try {
      final version = lib.lookupFunction<Uint32 Function(), int Function()>(
          'rooster_board_abi_version')();
      if (version != abiVersion) return null;
      return _instance = _Board._(
        lib.lookupFunction<_NewNative, _NewNative>('rooster_board_new'),
        lib.lookupFunction<_FreeNative, _Free>('rooster_board_free'),
        lib.lookupFunction<_PlayNative, _Play>('rooster_board_play'),
        lib.lookupFunction<_StopNative, _Stop>('rooster_board_stop'),
        lib.lookup<NativeFunction<_PullNative>>('rooster_board_pull').address,
      );
    } catch (e) {
      Log.w('Soundboard: no board in the Rust library: $e');
      return null;
    }
  }
}

/// Null where the sounds cannot be sent: the call keeps hearing them only
/// in Rooster.
SoundboardBroadcast? createSoundboardBroadcast(
  lk.Room room, {
  required SoundResolver resolveSound,
  required UriResolver resolvePlayableUri,
  required BytesLoader loadBytes,
}) {
  final board = _Board.load();
  if (board == null || !SoundboardClipCodec.available) return null;
  return _NativeSoundboardBroadcast(
      room, board, resolveSound, resolvePlayableUri);
}

class _NativeSoundboardBroadcast implements SoundboardBroadcast {
  _NativeSoundboardBroadcast(
      this.room, this.board, this.resolveSound, this.resolvePlayableUri);

  final lk.Room room;
  final _Board board;
  final SoundResolver resolveSound;
  final UriResolver resolvePlayableUri;

  Pointer<Void>? _handle;
  Future<void>? _starting;
  bool _shutDown = false;
  String? _feederTrackId;
  bool _feederStarted = false;
  MediaStreamNative? _stream;
  lk.LocalAudioTrack? _lkTrack;

  /// The board's id for each press still playing or on its way.
  final Map<String, int> _ids = {};
  int _nextId = 1;

  @override
  void play(String instanceId, String soundId) {
    final id = _ids[instanceId] = _nextId++;
    if (_ids.length > SoundboardConstraints.maxDedupEntries) {
      _ids.remove(_ids.keys.first);
    }
    _play(instanceId, id, soundId).catchError((Object e, StackTrace s) {
      Log.onError(e, s, content: 'Soundboard: could not send $soundId');
    });
  }

  Future<void> _play(String instanceId, int id, String soundId) async {
    final sound = resolveSound(soundId);
    if (sound == null) return;
    await (_starting ??= _start());
    final pcm = await SoundboardClipCodec.decode(
        await resolvePlayableUri(sound),
        startMs: 0,
        maxMs: SoundboardConstraints.maxPlaybackMs);
    final handle = _handle;
    // Stopped, or the call ended, while it was decoding.
    if (_ids[instanceId] != id || _shutDown || handle == null) return;

    final left = pcm.channels.first;
    final right = pcm.channels.length > 1 ? pcm.channels[1] : left;
    final len = pcm.frames * 2;
    final buffer = malloc<Float>(len);
    try {
      final samples = buffer.asTypedList(len);
      for (var i = 0; i < pcm.frames; i++) {
        samples[2 * i] = left[i];
        samples[2 * i + 1] = right[i];
      }
      board.play(handle, id, buffer, len, sound.gain);
    } finally {
      malloc.free(buffer);
    }
  }

  @override
  void stop(String instanceId) {
    final id = _ids.remove(instanceId);
    final handle = _handle;
    if (id != null && handle != null && !_shutDown) board.stop(handle, id);
  }

  Future<void> _start() async {
    final participant = room.localParticipant;
    if (participant == null) throw StateError('Not connected to the call');
    final handle = _handle = board.create();
    if (handle == nullptr) throw StateError('No soundboard mixer');

    final response = await rtc.WebRTC.invokeMethod(
        'roosterCreateMusicTrack', <String, dynamic>{
      'ctx': handle.address,
      'pull': board.pullAddress,
      // As the DJ booth: the sender writes these onto the processing it
      // shares with the microphone, so they are the microphone's own.
      'noiseSuppression': microphonePublication(participant)
              ?.track
              ?.currentOptions
              .noiseSuppression ??
          false,
    });
    if (response == null) throw StateError('No soundboard track');
    final audio = response['audioTracks'];
    _feederTrackId = audio is List && audio.isNotEmpty && audio.first is Map
        ? (audio.first as Map)['id'] as String?
        : null;
    _feederStarted = true;
    final stream = _stream = MediaStreamNative(response['streamId'], 'local')
      ..setMediaTracks(response['audioTracks'], response['videoTracks']);
    final track = stream.getAudioTracks().first;
    if (_shutDown) return;

    // ignore: invalid_use_of_internal_member
    final lkTrack = _lkTrack = lk.LocalAudioTrack(
        lk.TrackSource.unknown, stream, track, const lk.AudioCaptureOptions());
    await participant.publishAudioTrack(lkTrack,
        publishOptions: const lk.AudioPublishOptions(
          name: MatrixLivekitVoipStream.soundboardTrackName,
          // Silent between presses, which is most of the call.
          dtx: true,
          red: false,
          stereo: true,
          encoding: lk.AudioEncoding(maxBitrate: 96000),
        ));
  }

  @override
  Future<void> shutdown() async {
    if (_shutDown) return;
    _shutDown = true;
    await _starting?.catchError((_) {});

    final lkTrack = _lkTrack;
    final participant = room.localParticipant;
    if (lkTrack != null && participant != null) {
      for (final publication in participant.trackPublications.values
          .where((pub) => identical(pub.track, lkTrack))
          .toList()) {
        try {
          await participant.removePublishedTrack(publication.sid);
        } catch (e, s) {
          Log.onError(e, s, content: 'Soundboard: could not unpublish');
        }
      }
    }

    // The pacing thread must be gone before the board is freed.
    var feederStopped = !_feederStarted;
    final feeder = _feederTrackId;
    if (feeder != null) {
      try {
        await rtc.WebRTC.invokeMethod(
            'roosterStopMusicTrack', <String, dynamic>{'trackId': feeder});
        feederStopped = true;
      } catch (e, s) {
        Log.onError(e, s, content: 'Soundboard: could not stop the track');
      }
    }
    try {
      await lkTrack?.stop();
      await _stream?.dispose();
    } catch (_) {}
    final handle = _handle;
    _handle = null;
    // Leaked on purpose when the feeder may still pull from it.
    if (handle != null && feederStopped) board.free(handle);
  }
}
