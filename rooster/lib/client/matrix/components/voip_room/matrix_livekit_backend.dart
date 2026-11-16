import 'dart:convert';

import 'package:rooster/client/matrix/components/voip_room/call_join.dart';
import 'package:rooster/client/matrix/components/voip_room/call_token_service.dart';
import 'package:rooster/client/matrix/components/voip_room/livekit_join_room.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/voip_room/matrix_call_membership.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/components/voip/webrtc_default_devices.dart';
import 'package:rooster/client/components/voip/audio_processing/audio_processing_manager.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_encryption_key_provider.dart';
import 'package:rooster/client/matrix/components/voip_room/livekit_microphone.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/matrix_room_permissions.dart';
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart';

class MatrixLivekitBackend implements CallJoinHost<MatrixLivekitVoipSession> {
  MatrixRoom room;
  lk.Room? livekitRoom;
  MatrixLivekitBackend(this.room);

  static String get errorCallNoLivekitService =>
      Intl.message("Failed to find a valid LiveKit service",
          name: "errorCallNoLivekitService",
          desc: "Why joining a voice channel's call failed, shown under 'Could "
              "not join the call': the homeserver names no LiveKit service to "
              "hold calls. LiveKit is a name");

  static String get errorCallFocusNotHttps => Intl.message(
      "Selected focus JWT does not use HTTPS",
      name: "errorCallFocusNotHttps",
      desc: "Why joining a voice channel's call failed, shown under 'Could "
          "not join the call': the call's server (its focus, which hands out "
          "JWT tokens) is not on HTTPS. Technical; JWT and HTTPS are names");

  static String errorCallSfuHttp(int status) =>
      Intl.message("Failed to get sfu! HTTP Error $status",
          name: "errorCallSfuHttp",
          args: [status],
          desc: "Why joining a voice channel's call failed, shown under 'Could "
              "not join the call': the call's media server (the SFU) answered "
              "with an HTTP error, whose number follows");

  /// The server's discovery document. The spec puts it on the domain's
  /// HTTPS root and the SDK's discovery asks exactly there - a homeserver
  /// this client already logs into over plain HTTP on the same host (a
  /// developer's or the integration one) then answers via its own base
  /// URL: same box, same trust, same file (Synapse serves it from
  /// `extra_well_known_client_content`).
  Future<matrix.DiscoveryInformation> _wellKnown() async {
    final client = room.matrixRoom.client;
    try {
      return await client.getWellknown();
    } catch (e, s) {
      Log.onError(e, s,
          content: 'matrixrtc: the standard well-known did not answer');
    }
    final base = client.homeserver;
    if (base == null) {
      throw CallJoinException("Could not discover the homeserver's well-known",
          errorCallNoLivekitService);
    }
    final uri =
        base.replace(path: "/.well-known/matrix/client").normalizePath();
    // Through the account's client, so it is in the speed log.
    final response =
        await client.httpClient.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw CallJoinException(
          "The homeserver's well-known answered HTTP ${response.statusCode}",
          errorCallNoLivekitService);
    }
    return matrix.DiscoveryInformation.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>);
  }

  Future<List<Uri>> getFociUrl() async {
    final selectedFocus = findSelectedFocus();

    var wellKnown = await _wellKnown();
    final livekitJwtServiceUrl = wellKnown
        .additionalProperties["org.matrix.msc4143.rtc_foci"] as List<dynamic>?;

    if (livekitJwtServiceUrl == null) {
      return [
        if (selectedFocus != null) selectedFocus,
      ];
    }

    Uri? fociUrl;
    for (var focus in livekitJwtServiceUrl) {
      Log.d("Focus: ${focus}");
      final data = focus as Map<String, dynamic>;
      if (data["type"] != "livekit") {
        continue;
      }

      final url = data["livekit_service_url"] as String;
      fociUrl = Uri.parse(url);

      return [
        if (selectedFocus != null) selectedFocus,
        if (selectedFocus != fociUrl) fociUrl,
      ];
    }

    return [
      if (selectedFocus != null) selectedFocus,
    ];
  }

  Uri? findSelectedFocus() {
    final states =
        room.matrixRoom.states[MatrixVoipRoomComponent.callMemberStateEvent];
    if (states == null) {
      return null;
    }

    final values = states.values.map((event) => event as Event).toList();
    // By join time: our own memberships are rewritten when streams change
    // (issue #9), which must not move them down the oldest_membership order.
    DateTime joinedAt(Event e) =>
        MatrixCallMembership.joinedAt(e.content, e.originServerTs)!;
    values.sort((a, b) => joinedAt(a).compareTo(joinedAt(b)));

    for (var entry in values) {
      final focusActive =
          entry.content.tryGet<Map<String, dynamic>>("focus_active");

      if (focusActive == null) {
        continue;
      }

      if (focusActive['type'] != "livekit") {
        Log.e("Unknown focus type: ${focusActive['type']}");
        continue;
      }

      if (focusActive['focus_selection'] != "oldest_membership") {
        Log.e(
            "Unknown focus selection algorithm: ${focusActive['focus_selection']}");
        continue;
      }

      final fociPreferred =
          entry.content.tryGet<List<dynamic>>("foci_preferred");
      Log.e("Selecting focus");
      if (fociPreferred == null) {
        continue;
      }

      for (var item in fociPreferred) {
        final map = item as Map<String, dynamic>;
        if (map['type'] != "livekit") continue;
        if (map['livekit_alias'] != room.identifier) continue;
        return Uri.parse(map['livekit_service_url']);
      }
    }

    return null;
  }

  /// Joins the call. [leavePrevious] hangs up the call we are in; it runs
  /// beside the token requests. [hangUp] completing hangs up the join itself
  /// (see [CallJoin.run]).
  Future<VoipSession?> join(
      {Future<void> Function()? leavePrevious, Future<void>? hangUp}) async {
    final session = await CallJoin<MatrixLivekitVoipSession>(
      host: this,
      tokens: CallTokenService.forClient(room.matrixRoom.client),
    ).run(leavePrevious: leavePrevious, hangUp: hangUp);
    livekitRoom = session.livekitRoom;
    // In the browser the pick only reaches LiveKit's own audio elements.
    if (kIsWeb) {
      session.applyAudioOutput().catchError((Object e, StackTrace s) {
        Log.onError(e, s, content: "Could not use the picked speakers");
      });
    }
    return session;
  }

  @override
  bool get canWriteMembership => room.matrixRoom
      .canChangeState(MatrixVoipRoomComponent.callMemberStateEvent);

  @override
  Future<void> selectOutputDevice() async {
    await WebrtcDefaultDevices.selectOutputDevice();
  }

  @override
  Future<List<Uri>> foci() => getFociUrl();

  @override
  Future<matrix.OpenIdCredentials> openIdToken() => room.matrixRoom.client
      .requestOpenIdToken(room.matrixRoom.client.userID!, {});

  @override
  String get deviceId => room.matrixRoom.client.deviceID!;

  @override
  String get roomId => room.matrixRoom.id;

  @override
  String get membershipKey => _ownMembershipKey;

  @override
  Future<void> writeMembership(List<Uri> foci) =>
      room.matrixRoom.client.setRoomStateWithKey(room.matrixRoom.id,
          MatrixVoipRoomComponent.callMemberStateEvent, _ownMembershipKey, {
        "application": "m.call",
        "call_id": "",
        "device_id": room.matrixRoom.client.deviceID!,
        "expires": 14400000,
        "foci_preferred": foci
            .map((e) => {
                  "type": "livekit",
                  "livekit_alias": room.identifier,
                  "livekit_service_url": e.toString()
                })
            .toList(),
        "focus_active": {
          "focus_selection": "oldest_membership",
          "type": "livekit"
        },
        "scope": "m.room",
        // Rewritten while we share our screen or camera (issue #9).
        MatrixCallMembership.liveMediaKey: <String>[],
      });

  @override
  Future<void> clearMembership() => room.matrixRoom.client.setRoomStateWithKey(
      room.matrixRoom.id,
      MatrixVoipRoomComponent.callMemberStateEvent,
      _ownMembershipKey, {});

  @override
  Future<LivekitJoinRoom> createRoom() async {
    lk.E2EEOptions? e2eeOptions;
    MatrixLivekitEncryptionKeyProvider? provider;

    if (room.isE2EE) {
      provider =
          await MatrixLivekitEncryptionKeyProvider.create(room.matrixRoom);
      e2eeOptions = lk.E2EEOptions(keyProvider: provider);
    }

    final roomOptions = lk.RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        e2eeOptions: e2eeOptions,
        defaultAudioPublishOptions: lk.AudioPublishOptions(
          // What the microphone always had: the SDK used to send this flag
          // inverted, so "red: true" meant no RED (see third_party/README).
          red: false,
          encoding: lk.AudioEncoding(
              maxBitrate:
                  (preferences.streamAudioBitrate.value * 1000).toInt()),
        ));

    // The previous call's room is disposed when it hangs up.
    livekitRoom = null;
    return LkJoinRoom(lk.Room(roomOptions: roomOptions), keyProvider: provider);
  }

  @override
  Future<lk.AudioCaptureOptions> microphoneOptions() => _microphoneOptions();

  @override
  bool get mobileBrowser => Layout.isMobileBrowser;

  @override
  bool get isWeb => kIsWeb;

  @override
  MatrixLivekitVoipSession createSession(
      LivekitJoinRoom joined, Future<void> microphonePublished) {
    final lkRoom = joined as LkJoinRoom;
    return MatrixLivekitVoipSession(room, lkRoom.room,
        keyProvider: lkRoom.keyProvider,
        microphonePublished: microphonePublished);
  }

  String get _ownMembershipKey =>
      "_${room.client.self!.identifier}_${room.matrixRoom.client.deviceID!}_m.call";

  /// A room microphone's capture options, for the default device.
  Future<lk.AudioCaptureOptions> _microphoneOptions() async {
    var device = await WebrtcDefaultDevices.getDefaultMicrophoneId();

    print("Using default device: ${device}");

    return prepareMicrophoneCaptureOptions(
      dsp: AudioProcessingManager.instance,
      noiseSuppressionPreference: preferences.voipNoiseSuppression.value,
      deviceId: device,
    );
  }
}
