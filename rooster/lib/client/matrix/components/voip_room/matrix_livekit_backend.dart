import 'dart:convert';

import 'package:rooster/client/matrix/components/voip_room/call_membership_writes.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_call_membership.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/components/voip/webrtc_default_devices.dart';
import 'package:rooster/client/components/voip/audio_processing/audio_processing_manager.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_encryption_key_provider.dart';
import 'package:rooster/client/matrix/components/voip_room/livekit_microphone.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart';

class MatrixLivekitBackend {
  MatrixRoom room;
  lk.Room? livekitRoom;
  MatrixLivekitBackend(this.room);

  Future<List<Uri>> getFociUrl() async {
    final selectedFocus = findSelectedFocus();

    var wellKnown = await room.matrixRoom.client.getWellknown();
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

  Future<VoipSession?> join() async {
    // Awaited: joining while this is still running leaves the call on
    // whatever device the system chose.
    await WebrtcDefaultDevices.selectOutputDevice();

    final fociUrl = await getFociUrl();

    if (fociUrl.isEmpty) {
      throw Exception("Failed to find a valid LiveKit service");
    }

    final selectedFocus = fociUrl.first;
    Log.d("Got Foci Url: ${fociUrl}");

    // Bounded: the Join button is disabled while this runs, so a request
    // that never answers left no way to try again.
    final token = await room.matrixRoom.client.requestOpenIdToken(
        room.matrixRoom.client.userID!,
        {}).timeout(const Duration(seconds: 15));

    if (selectedFocus.scheme != "https") {
      throw Exception("Selected focus JWT does not use HTTPS");
    }

    Log.d("Received token from homeserver: ${token}");
    final uri = Uri.parse(selectedFocus.toString() + "/sfu/get");

    final body = {
      "device_id": room.matrixRoom.client.deviceID!,
      "room": room.matrixRoom.id,
      "openid_token": {
        "matrix_server_name": token.matrixServerName,
        "access_token": token.accessToken,
        "expires_in": token.expiresIn,
      }
    };

    var result = await http
        .post(uri, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    if (result.statusCode != 200) {
      throw Exception("Failed to get sfu! HTTP Error ${result.statusCode}");
    }

    var data = jsonDecode(result.body) as Map<String, dynamic>;

    final sfuUrl = data["url"];
    Log.d("Got sfu: ${sfuUrl}");
    final jwt = data["jwt"];
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
    final lkRoom = lk.Room(roomOptions: roomOptions);

    // Local, not a field: two joins can overlap (two views of one room).
    var wroteMembership = false;
    lk.LocalAudioTrack? earlyMicrophone;
    try {
      return await _connect(lkRoom, sfuUrl, jwt, fociUrl, provider,
          onMembershipWritten: () => wroteMembership = true,
          onMicrophoneOpened: (track) => earlyMicrophone = track);
    } catch (_) {
      // Don't leave a membership for a call we never got into, nor a room
      // that keeps its connectivity listener and timers alive (issue #48).
      // The membership first: it is what other people see.
      provider?.dispose();
      if (wroteMembership) {
        try {
          await room.matrixRoom.client.setRoomStateWithKey(
              room.matrixRoom.id,
              MatrixVoipRoomComponent.callMemberStateEvent,
              _ownMembershipKey, {});
        } catch (e, s) {
          Log.onError(e, s, content: "Could not clear call membership");
        }
      }
      await lkRoom.dispose();
      // Nor a microphone opened ahead of a room that never connected,
      // capturing with nothing left that could stop it.
      try {
        await earlyMicrophone?.stop();
      } catch (e, s) {
        Log.onError(e, s, content: "Could not close the microphone");
      }
      rethrow;
    }
  }

  String get _ownMembershipKey =>
      "_${room.client.self!.identifier}_${room.matrixRoom.client.deviceID!}_m.call";

  Future<VoipSession> _connect(lk.Room lkRoom, String sfuUrl, String jwt,
      List<Uri> fociUrl, MatrixLivekitEncryptionKeyProvider? provider,
      {required void Function() onMembershipWritten,
      required void Function(lk.LocalAudioTrack track)
          onMicrophoneOpened}) async {
    // In a phone's browser, before anything of the call plays: see
    // openMicrophoneBeforePlayback. Before the membership too, so nobody is
    // told we are in while a permission prompt is still up.
    final early = await openMicrophoneBeforePlayback(
        needed: Layout.isMobileBrowser, options: _microphoneOptions);
    final earlyTrack = early.track;
    if (earlyTrack != null) onMicrophoneOpened(earlyTrack);

    await lkRoom.prepareConnection(sfuUrl, jwt);

    // A clear from the previous call may still be in flight, and would
    // erase what we write now (issue #48).
    await CallMembershipWrites.settled(_ownMembershipKey);

    onMembershipWritten();
    await room.matrixRoom.client.setRoomStateWithKey(room.matrixRoom.id,
        MatrixVoipRoomComponent.callMemberStateEvent, _ownMembershipKey, {
      "application": "m.call",
      "call_id": "",
      "device_id": room.matrixRoom.client.deviceID!,
      "expires": 14400000,
      "foci_preferred": fociUrl
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

    // The session subscribes to tracks itself, so screen shares only play
    // for people who opt in to watching them (issue #50).
    await lkRoom.connect(sfuUrl, jwt,
        connectOptions: const lk.ConnectOptions(autoSubscribe: false));

    if (earlyTrack != null) {
      // Not awaited either, and handed over: from here a publish that
      // fails closes it itself.
      _publishMicrophone(lkRoom, earlyTrack);
    } else if (early.retry) {
      final micOptions = await _microphoneOptions();
      lkRoom.localParticipant
          ?.setMicrophoneEnabled(true, audioCaptureOptions: micOptions)
          .catchError((Object e, StackTrace s) {
        // Not awaited on purpose (joining muted is still joining), but a
        // denied microphone must not end up as an unhandled error.
        Log.onError(e, s, content: "Could not enable the microphone");
        return null;
      });
    }

    final session =
        MatrixLivekitVoipSession(room, lkRoom, keyProvider: provider);
    livekitRoom = lkRoom;
    return session;
  }

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

  /// Publishes a microphone that was opened ahead of the room. Never fails:
  /// joining without a microphone is still joining.
  Future<void> _publishMicrophone(
      lk.Room lkRoom, lk.LocalAudioTrack track) async {
    try {
      final participant = lkRoom.localParticipant;
      if (participant == null) {
        await track.stop();
        return;
      }
      await participant.publishAudioTrack(track);
    } catch (e, s) {
      Log.onError(e, s, content: "Could not enable the microphone");
      try {
        // The room went away meanwhile: nothing else would stop it.
        await track.stop();
      } catch (e, s) {
        Log.onError(e, s, content: "Could not close the microphone");
      }
    }
  }
}
