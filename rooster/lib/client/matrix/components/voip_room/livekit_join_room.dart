import 'dart:async';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_encryption_key_provider.dart';

/// What a voice join does with LiveKit, and nothing more.
///
/// The join (`CallJoin`, in `call_join.dart`) reaches the SFU only through
/// this interface, so the order of its steps can be tested with a fake room
/// that opens no WebSocket and no WebRTC. [LkJoinRoom] is the real one, over
/// `lk.Room`; once the join succeeds the call session takes that `lk.Room`
/// over ([LkJoinRoom.room]).
abstract class LivekitJoinRoom {
  /// Warms the way to the SFU at [url]: DNS and TLS and, for a LiveKit Cloud
  /// address with a [token], the choice of the nearest region, which
  /// [connect] uses only if this finished first. Never throws.
  Future<void> prepareConnection(String url, String token);

  /// Connects to the SFU. Nothing is subscribed by itself: the session
  /// subscribes to tracks, so screen shares only play for people who opt in
  /// to watching them (issue #50).
  Future<void> connect(String url, String token);

  /// Whether [error], thrown by [connect], is the SFU refusing the token
  /// (an expired or revoked one): the join then asks for a new token, once.
  bool refusedToken(Object error);

  /// Opens a microphone capture with [options], not published yet. This is
  /// where a browser asks for permission.
  Future<JoinMicrophone> openMicrophone(lk.AudioCaptureOptions options);

  /// Publishes [microphone], opened by [openMicrophone], once connected.
  Future<void> publishMicrophone(JoinMicrophone microphone);

  /// The region the SFU reported when [connect] finished; null when it
  /// reports none (a self-hosted SFU says nothing).
  String? get serverRegion;

  /// What happens in the room that the join's timings need.
  Stream<JoinRoomEvent> get events;

  /// Lets go of everything: a join that failed calls this.
  Future<void> dispose();
}

/// A microphone capture opened by [LivekitJoinRoom.openMicrophone].
abstract class JoinMicrophone {
  /// Stops the capture: one that is never published must not keep the
  /// microphone open with nothing left that could stop it.
  Future<void> stop();
}

enum JoinRoomEvent {
  /// Someone else in the call is heard speaking (LiveKit's active speakers).
  remoteSpeaking,
}

/// [LivekitJoinRoom] over a real `lk.Room`.
class LkJoinRoom implements LivekitJoinRoom {
  LkJoinRoom(this.room, {this.keyProvider});

  final lk.Room room;

  /// The end-to-end encryption keys of an encrypted room, handed to the
  /// session with [room] once the join succeeds.
  final MatrixLivekitEncryptionKeyProvider? keyProvider;

  @override
  Future<void> prepareConnection(String url, String token) =>
      room.prepareConnection(url, token);

  @override
  Future<void> connect(String url, String token) => room.connect(url, token,
      connectOptions: const lk.ConnectOptions(autoSubscribe: false));

  /// LiveKit checks the token over HTTP when the WebSocket fails, and
  /// reports a 4xx answer as `NotAllowed`.
  @override
  bool refusedToken(Object error) =>
      error is lk.ConnectException &&
      error.reason == lk.ConnectionErrorReason.NotAllowed;

  @override
  Future<JoinMicrophone> openMicrophone(lk.AudioCaptureOptions options) async =>
      LkJoinMicrophone(await lk.LocalAudioTrack.create(options));

  @override
  Future<void> publishMicrophone(JoinMicrophone microphone) async {
    final participant = room.localParticipant;
    if (participant == null) {
      throw StateError("The room has no local participant to publish with");
    }
    await participant.publishAudioTrack((microphone as LkJoinMicrophone).track);
  }

  @override
  String? get serverRegion => room.serverRegion;

  @override
  Stream<JoinRoomEvent> get events {
    lk.EventsListener<lk.RoomEvent>? listener;
    late final StreamController<JoinRoomEvent> controller;
    controller = StreamController<JoinRoomEvent>(
        onListen: () => listener = room.createListener()
          ..on<lk.ActiveSpeakersChangedEvent>((event) {
            if (event.speakers.any((p) => p is lk.RemoteParticipant)) {
              controller.add(JoinRoomEvent.remoteSpeaking);
            }
          }),
        onCancel: () => listener?.dispose());
    return controller.stream;
  }

  @override
  Future<void> dispose() async {
    keyProvider?.dispose();
    await room.dispose();
  }
}

/// [JoinMicrophone] over a LiveKit microphone track.
class LkJoinMicrophone implements JoinMicrophone {
  LkJoinMicrophone(this.track);

  final lk.LocalAudioTrack track;

  @override
  Future<void> stop() => track.stop();
}
