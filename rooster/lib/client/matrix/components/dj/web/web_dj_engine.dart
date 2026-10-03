// The DJ's player in the browser. A song plays in an <audio> element (so it
// streams instead of being decoded whole into memory, which a phone can't
// spare), wired through Web Audio to two places: a MediaStream published as
// the same music track desktop DJs publish
// (MatrixLivekitVoipStream.musicTrackName), and the DJ's own speakers at their
// monitor volume.
//
// It plays files the DJ picked in this browser and direct links to audio
// files whose server lets web pages read them (CORS). Songs from source
// extensions (YouTube, SoundCloud) need the desktop app.
import 'dart:async';
import 'dart:js_interop';

import 'package:dart_webrtc/dart_webrtc.dart' show MediaStreamWeb;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:rooster/client/components/dj/dj_engine.dart';
import 'package:rooster/client/components/dj/dj_models.dart';
import 'package:rooster/client/matrix/components/dj/web/web_dj_files.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:rooster/debug/log.dart';
import 'package:web/web.dart' as web;

class WebDjEngine implements DjPlaybackEngine {
  WebDjEngine(this.room, {double monitorVolume = 1})
      : _monitorVolume = monitorVolume;

  final lk.Room room;
  double _monitorVolume;

  web.AudioContext? _ctx;
  web.HTMLAudioElement? _audio;
  web.GainNode? _monitor;
  lk.LocalAudioTrack? _lkTrack;

  /// What [prepare] found to play, by track id.
  final Map<String, String> _urls = {};
  String? _loadedId;
  bool _buffering = false;
  String? _error;

  /// A position asked for before the song's length was known, applied once
  /// it is: browsers drop a seek made that early.
  double? _pendingSeek;

  Future<void>? _starting;
  bool _shutDown = false;

  @override
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    final participant = room.localParticipant;
    if (participant == null) throw StateError('Not connected to the call');

    final ctx = _ctx = web.AudioContext();
    final audio = _audio = web.HTMLAudioElement()
      // A direct link from another site only reaches Web Audio (and the
      // room) when its server allows it; without this it would be silence.
      ..crossOrigin = 'anonymous'
      ..preload = 'auto';
    audio.addEventListener(
        'waiting', ((web.Event _) => _buffering = true).toJS);
    for (final ready in ['playing', 'canplay', 'pause']) {
      audio.addEventListener(ready, ((web.Event _) => _buffering = false).toJS);
    }
    audio.addEventListener(
        'loadedmetadata',
        ((web.Event _) {
          final seek = _pendingSeek;
          _pendingSeek = null;
          if (seek != null) audio.currentTime = seek;
        }).toJS);
    audio.addEventListener(
        'error',
        ((web.Event _) {
          _buffering = false;
          _error = _describe(audio.error);
        }).toJS);

    final source = ctx.createMediaElementSource(audio);
    final destination = ctx.createMediaStreamDestination();
    source.connect(destination);
    final monitor = _monitor = ctx.createGain()..gain.value = _monitorVolume;
    source.connect(monitor);
    monitor.connect(ctx.destination);

    final stream = MediaStreamWeb(destination.stream, 'local');
    final track = stream.getAudioTracks().first;
    if (_shutDown) return;

    // ignore: invalid_use_of_internal_member
    final lkTrack = _lkTrack = lk.LocalAudioTrack(
        lk.TrackSource.unknown, stream, track, const lk.AudioCaptureOptions());
    await participant.publishAudioTrack(lkTrack,
        publishOptions: const lk.AudioPublishOptions(
          name: MatrixLivekitVoipStream.musicTrackName,
          // As on desktop: music has no pauses for DTX, and RED doubles
          // 128 kbps for little.
          dtx: false,
          red: false,
          stereo: true,
          encoding: lk.AudioEncoding(maxBitrate: 128000),
        ));
  }

  static String _describe(web.MediaError? error) => switch (error?.code) {
        // MEDIA_ERR_NETWORK, MEDIA_ERR_SRC_NOT_SUPPORTED
        2 => 'The song stopped downloading',
        4 => 'This browser can\'t play that song, or its site doesn\'t let web '
            'pages play it',
        _ => 'The song couldn\'t be played',
      };

  @override
  Future<void> shutdown() async {
    if (_shutDown) return;
    _shutDown = true;
    await _starting?.catchError((_) {});

    _audio?.pause();
    final lkTrack = _lkTrack;
    final participant = room.localParticipant;
    if (lkTrack != null && participant != null) {
      for (final publication in participant.trackPublications.values
          .where((pub) => identical(pub.track, lkTrack))
          .toList()) {
        try {
          await participant.removePublishedTrack(publication.sid);
        } catch (e, s) {
          Log.onError(e, s, content: 'DJ booth: could not unpublish the music');
        }
      }
    }
    try {
      await lkTrack?.stop();
    } catch (_) {}
    final audio = _audio;
    if (audio != null) {
      audio.removeAttribute('src');
      audio.load();
    }
    try {
      await _ctx?.close().toDart;
    } catch (_) {}
    _audio = null;
    _ctx = null;
  }

  @override
  Future<DjTrackInfo> prepare(DjTrack track, {bool whole = false}) async {
    final String url;
    if (track.isLocalFile) {
      // Only in the browser that picked it.
      url = WebDjFiles.instance.urlOf(track.source) ??
          (throw const DjTrackUnavailable(
              'A file on someone else\'s computer'));
    } else if (track.extensionId != null) {
      throw const DjTrackUnavailable(
          'Songs from YouTube, SoundCloud and other sites play from the '
          'desktop app');
    } else {
      final uri = Uri.tryParse(track.source);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw const DjTrackUnavailable('Not a link to an audio file');
      }
      url = track.source;
    }
    _urls[track.id] = url;
    return const DjTrackInfo();
  }

  @override
  void load(DjTrack track, {required int positionMs, required bool paused}) {
    final url = _urls[track.id];
    final audio = _audio;
    if (url == null) throw StateError('the song was not fetched');
    if (audio == null || _shutDown) throw StateError('the booth is closed');
    _error = null;
    _buffering = true;
    _loadedId = track.id;
    _pendingSeek = positionMs > 0 ? positionMs / 1000 : null;
    audio.src = url;
    if (paused) {
      audio.pause();
    } else {
      _play();
    }
  }

  void _play() {
    final ctx = _ctx;
    // Browsers start an audio context suspended until the page has been
    // clicked; taking the decks was a click.
    if (ctx != null && ctx.state == 'suspended') ctx.resume();
    _audio?.play().toDart.catchError((Object e) {
      Log.w('DJ booth: the browser would not start the song: $e');
      return null;
    });
  }

  @override
  void setPaused(bool paused) {
    if (paused) {
      _audio?.pause();
    } else {
      _play();
    }
  }

  @override
  Future<void> seek(int positionMs) async {
    final audio = _audio;
    if (audio == null) return;
    if (audio.readyState < 1) {
      _pendingSeek = positionMs / 1000;
    } else {
      audio.currentTime = positionMs / 1000;
    }
  }

  @override
  void unload() {
    final audio = _audio;
    _loadedId = null;
    _error = null;
    _buffering = false;
    if (audio == null) return;
    audio.pause();
    audio.removeAttribute('src');
    audio.load();
  }

  @override
  DjEngineStatus get status {
    final audio = _audio;
    final loaded = _loadedId;
    if (audio == null || loaded == null || _shutDown) {
      return DjEngineStatus.idle;
    }
    final duration = audio.duration;
    final state = _error != null
        ? DjEngineState.error
        : audio.ended
            ? DjEngineState.ended
            : _buffering
                ? DjEngineState.buffering
                : audio.paused
                    ? DjEngineState.paused
                    : DjEngineState.playing;
    return DjEngineStatus(
      state: state,
      trackId: loaded,
      positionMs: (audio.currentTime * 1000).round(),
      durationMs: duration.isFinite ? (duration * 1000).round() : 0,
      error: _error,
    );
  }

  @override
  set monitorVolume(double volume) {
    _monitorVolume = volume;
    _monitor?.gain.value = volume;
  }
}
