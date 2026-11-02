// Browser: our own presses go to the call on a track of their own, the way
// the web DJ booth's music does (web_dj_engine.dart): every press plays
// into one MediaStreamAudioDestinationNode, which mixes them, and that
// stream is the track. Published on the first press and kept until the call
// ends.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dart_webrtc/dart_webrtc.dart' show MediaStreamWeb;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:rooster/client/components/soundboard/soundboard_constraints.dart';
import 'package:rooster/client/components/soundboard/soundboard_engine.dart';
import 'package:rooster/client/matrix/components/soundboard/soundboard_player_factory.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:rooster/debug/log.dart';
import 'package:web/web.dart' as web;

SoundboardBroadcast? createSoundboardBroadcast(
  lk.Room room, {
  required SoundResolver resolveSound,
  required UriResolver resolvePlayableUri,
  required BytesLoader loadBytes,
}) =>
    _WebSoundboardBroadcast(room, resolveSound, loadBytes);

class _WebSoundboardBroadcast implements SoundboardBroadcast {
  _WebSoundboardBroadcast(this.room, this.resolveSound, this.loadBytes);

  final lk.Room room;
  final SoundResolver resolveSound;
  final BytesLoader loadBytes;

  web.AudioContext? _ctx;
  web.MediaStreamAudioDestinationNode? _destination;
  lk.LocalAudioTrack? _lkTrack;
  Future<void>? _starting;
  bool _shutDown = false;

  /// Decoded once per file.
  final Map<String, web.AudioBuffer> _buffers = {};

  /// Presses still playing or on their way; a stop before the sound is
  /// decoded leaves a null.
  final Map<String, web.AudioBufferSourceNode?> _playing = {};

  @override
  void play(String instanceId, String soundId) {
    _playing[instanceId] = null;
    // Synchronously, in the click: browsers only let an AudioContext start
    // from a user gesture.
    _ctx ??= web.AudioContext();
    _play(instanceId, soundId).catchError((Object e, StackTrace s) {
      _playing.remove(instanceId);
      Log.onError(e, s, content: 'Soundboard: could not send $soundId');
    });
  }

  Future<void> _play(String instanceId, String soundId) async {
    final sound = resolveSound(soundId);
    if (sound == null) return;
    await (_starting ??= _start());
    final ctx = _ctx, destination = _destination;
    if (ctx == null || destination == null) return;
    if (ctx.state == 'suspended') await ctx.resume().toDart;

    final key = '${sound.soundId}\n${sound.mediaUri}';
    var buffer = _buffers[key];
    if (buffer == null) {
      // decodeAudioData detaches the buffer it gets; hand it a copy.
      final bytes = Uint8List.fromList(await loadBytes(sound));
      buffer = await ctx.decodeAudioData(bytes.buffer.toJS).toDart;
      if (_buffers.length >= SoundboardConstraints.maxCachedSounds) {
        _buffers.remove(_buffers.keys.first);
      }
      _buffers[key] = buffer;
    }
    // Stopped, or the call ended, while it was decoding.
    if (!_playing.containsKey(instanceId) || _shutDown) return;

    final gain = ctx.createGain()..gain.value = sound.gain;
    final source = ctx.createBufferSource()..buffer = buffer;
    source.connect(gain);
    gain.connect(destination);
    source.onended = ((web.Event _) {
      gain.disconnect();
      if (identical(_playing[instanceId], source)) _playing.remove(instanceId);
    }).toJS;
    _playing[instanceId] = source;
    source.start(0, 0, SoundboardConstraints.maxPlaybackMs / 1000);
  }

  @override
  void stop(String instanceId) {
    if (!_playing.containsKey(instanceId)) return;
    try {
      _playing.remove(instanceId)?.stop();
    } catch (_) {}
  }

  Future<void> _start() async {
    final participant = room.localParticipant;
    if (participant == null) throw StateError('Not connected to the call');
    final destination = _destination = _ctx!.createMediaStreamDestination();
    final stream = MediaStreamWeb(destination.stream, 'local');
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
    for (final source in _playing.values) {
      try {
        source?.stop();
      } catch (_) {}
    }
    _playing.clear();

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
    try {
      await lkTrack?.stop();
    } catch (_) {}
    try {
      await _ctx?.close().toDart;
    } catch (_) {}
    _ctx = null;
  }
}
