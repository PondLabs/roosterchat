import 'dart:async';

import 'package:intl/intl.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/matrix/components/voip_room/call_membership_writes.dart';
import 'package:rooster/client/matrix/components/voip_room/call_token_service.dart';
import 'package:rooster/client/matrix/components/voip_room/livekit_join_room.dart';
import 'package:rooster/client/matrix/components/voip_room/livekit_microphone.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_backend.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/diagnostic/speed_log/call_join_trace.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';

/// The Matrix side of a voice join, for [CallJoin]: what it asks the
/// account, the room and the device. `MatrixLivekitBackend` is the real one.
abstract class CallJoinHost<S> {
  /// Whether our power level lets us write our call membership. Without it
  /// nobody would see us in the call.
  bool get canWriteMembership;

  /// Hands WebRTC the speakers the user picked.
  Future<void> selectOutputDevice();

  /// The call's token services, the one to use first.
  Future<List<Uri>> foci();

  Future<matrix.OpenIdCredentials> openIdToken();

  /// Ours, for `/sfu/get`.
  String get deviceId;

  /// The Matrix room, for `/sfu/get`.
  String get roomId;

  /// The state key of our call membership.
  String get membershipKey;

  Future<void> writeMembership(List<Uri> foci);

  Future<void> clearMembership();

  /// A LiveKit room for the call, encrypted in an encrypted room.
  Future<LivekitJoinRoom> createRoom();

  /// The microphone's capture options, once it is known whether our DSP
  /// runs (bounded, see `prepareMicrophoneCaptureOptions`).
  Future<lk.AudioCaptureOptions> microphoneOptions();

  /// In a phone's browser the microphone opens before anything of the call
  /// plays (see `openMicrophoneBeforePlayback`).
  bool get mobileBrowser;

  bool get isWeb;

  /// The session of the call, over [room] once connected.
  S createSession(LivekitJoinRoom room);
}

/// One voice join, in the order the people in the call see it: the previous
/// call's membership cleared, ours written, the connection, the microphone.
///
/// What nobody else sees runs beside the rest instead of before it:
///
/// - the previous call hangs up ([run]'s `leavePrevious`) while the speakers
///   are picked and the tokens are asked for; our membership is written only
///   once that hang up, and a clear of ours still in flight, are done;
/// - `prepareConnection` is awaited only for a LiveKit Cloud SFU, where it
///   picks the region the connection then uses; for any other SFU it is
///   skipped on native and not waited for on the web;
/// - the microphone's options and capture are prepared during the
///   connection, and published once it is up (a phone's browser opens it
///   before the membership, as before).
///
/// Every step is timed in a `voice_join` span ([CallJoinTrace]).
class CallJoin<S> {
  CallJoin({
    required this.host,
    required this.tokens,
    SpeedLog? log,
    this.remoteAudioWindow = const Duration(seconds: 30),
  }) : log = log ?? SpeedLog.instance;

  final CallJoinHost<S> host;
  final CallTokenService tokens;
  final SpeedLog log;
  final Duration remoteAudioWindow;

  static String get errorCallNoPermission =>
      Intl.message("Your role in this channel does not let you join its calls",
          name: "errorCallNoPermission",
          desc: "Why joining a voice channel's call failed, shown under 'Could "
              "not join the call': the user's power level in the room does not "
              "allow the call membership event, so nobody would see them in "
              "the call. Nothing was sent");

  /// Joins: [leavePrevious] hangs up the call we are in, and is only called
  /// once the join is allowed.
  Future<S> run({Future<void> Function()? leavePrevious}) async {
    // Before anything starts, the previous call's hang up included.
    if (!host.canWriteMembership) {
      throw CallJoinException(
          "Not allowed to send the call membership", errorCallNoPermission);
    }
    final trace = CallJoinTrace(log, remoteAudioWindow: remoteAudioWindow);
    // The previous call's hang up and the new session run here, outside the
    // span: their requests (and the session's timers, for the whole call)
    // are not the join's.
    final outside = Zone.current;
    try {
      return await trace.run(() => _join(trace, outside, leavePrevious));
    } catch (_) {
      trace.failed();
      rethrow;
    }
  }

  Future<S> _join(CallJoinTrace trace, Zone outside,
      Future<void> Function()? leavePrevious) async {
    final leaving = _quiet(trace.time(
        SpeedStep.leavePrevious,
        () => leavePrevious == null
            ? Future.value()
            : outside.run(leavePrevious)));
    // Awaited before the connection: joining while this is still running
    // leaves the call on whatever device the system chose.
    final output = _quiet(
        trace.time(SpeedStep.outputDevice, () => host.selectOutputDevice()));

    final openIdRequest = trace.time(
        SpeedStep.openIdToken, () => host.openIdToken().timeout(_bound));
    // Not left failing unheard when the foci below throw first.
    openIdRequest.ignore();
    final foci = await trace.time(SpeedStep.foci, host.foci);
    if (foci.isEmpty) {
      throw CallJoinException("Failed to find a valid LiveKit service",
          MatrixLivekitBackend.errorCallNoLivekitService);
    }
    final focus = foci.first;
    Log.d("Got Foci Url: $foci");
    final openId = await openIdRequest;

    // A remote service must be HTTPS: the OpenID-backed requests leave
    // this device. A loopback service (a developer's local stack, and the
    // integration one) is trusted by its address.
    final focusLoopback = focus.host == "localhost" ||
        focus.host.startsWith("127.") ||
        focus.host == "::1" ||
        focus.host == "[::1]";
    if (focus.scheme != "https" && !focusLoopback) {
      throw CallJoinException("Selected focus JWT does not use HTTPS",
          MatrixLivekitBackend.errorCallFocusNotHttps);
    }

    final grant = await trace.time(
        SpeedStep.sfuToken,
        () => tokens.requestSfu(focus, {
              "device_id": host.deviceId,
              "room": host.roomId,
              "openid_token": {
                "matrix_server_name": openId.matrixServerName,
                "access_token": openId.accessToken,
                "expires_in": openId.expiresIn,
              }
            }));
    final cloud = isLivekitCloud(Uri.parse(grant.url));
    trace.sfuHost(livekitCloud: cloud);

    await output;
    final room = await host.createRoom();

    // Local, not fields: two joins can overlap (two views of one room).
    var wroteMembership = false;
    JoinMicrophone? earlyMicrophone;
    Future<JoinMicrophone?>? preparedMicrophone;
    try {
      await leaving;

      // In a phone's browser, before anything of the call plays: see
      // openMicrophoneBeforePlayback. Before the membership too, so nobody
      // is told we are in while a permission prompt is still up.
      final early = host.mobileBrowser
          ? await trace.time(
              SpeedStep.microphoneEarly,
              () => openBeforePlayback<JoinMicrophone>(
                  needed: true,
                  options: host.microphoneOptions,
                  open: room.openMicrophone,
                  stop: (microphone) => microphone.stop()))
          : const EarlyMicrophone<JoinMicrophone>();
      earlyMicrophone = early.track;

      if (cloud) {
        // The connection uses a region only if this has chosen it.
        await trace.time(SpeedStep.prepareConnection,
            () => room.prepareConnection(grant.url, grant.jwt));
      } else if (host.isWeb) {
        // DNS and TLS for the browser, not worth waiting for.
        unawaited(_quiet(trace.time(SpeedStep.prepareConnection,
            () => room.prepareConnection(grant.url, grant.jwt))));
      }

      // A clear from the previous call may still be in flight, and would
      // erase what we write now (issue #48).
      await trace.time(SpeedStep.membershipClearWait,
          () => CallMembershipWrites.settled(host.membershipKey));

      if (early.track == null && early.retry) {
        preparedMicrophone = _prepareMicrophone(trace, room);
      }

      wroteMembership = true;
      await trace.time(
          SpeedStep.membershipWrite, () => host.writeMembership(foci));

      await trace.time(
          SpeedStep.connect, () => room.connect(grant.url, grant.jwt));
      trace.connected(room.serverRegion);

      final toPublish = early.track;
      final Future<bool> published;
      if (toPublish != null) {
        // Handed over: from here a publish that fails closes it itself.
        earlyMicrophone = null;
        published = _publish(room, toPublish);
      } else if (preparedMicrophone != null) {
        final prepared = preparedMicrophone;
        preparedMicrophone = null;
        published = prepared.then((microphone) =>
            microphone == null ? false : _publish(room, microphone));
      } else {
        published = Future.value(false);
      }
      // Not awaited: joining muted is still joining.
      trace.microphone(published);
      trace.listenForRemoteAudio(
          room.events.where((event) => event == JoinRoomEvent.remoteSpeaking));

      return outside.run(() => host.createSession(room));
    } catch (_) {
      // Don't leave a membership for a call we never got into, nor a room
      // that keeps its connectivity listener and timers alive (issue #48).
      // The membership first: it is what other people see.
      if (wroteMembership) {
        try {
          await host.clearMembership();
        } catch (e, s) {
          Log.onError(e, s, content: "Could not clear call membership");
        }
      }
      await room.dispose();
      // Nor a microphone opened ahead of a room that never connected,
      // capturing with nothing left that could stop it.
      await _stop(earlyMicrophone);
      unawaited(preparedMicrophone?.then(_stop));
      rethrow;
    }
  }

  static const _bound = Duration(seconds: 15);

  /// Whether [sfu] is LiveKit Cloud, as LiveKit's own `isCloudUrl` (not
  /// exported) tells.
  static bool isLivekitCloud(Uri sfu) =>
      sfu.host.contains('.livekit.cloud') || sfu.host.contains('.livekit.run');

  /// The microphone's options and capture, while the membership is written
  /// and the room connects. Null when it could not be opened (no
  /// permission, no device): joining without a microphone is still joining,
  /// and unmuting asks again.
  Future<JoinMicrophone?> _prepareMicrophone(
      CallJoinTrace trace, LivekitJoinRoom room) async {
    try {
      final options =
          await trace.time(SpeedStep.microphoneOptions, host.microphoneOptions);
      return await trace.time(
          SpeedStep.microphoneOpen, () => room.openMicrophone(options));
    } catch (e, s) {
      Log.onError(e, s, content: "Could not enable the microphone");
      return null;
    }
  }

  /// Publishes a microphone opened ahead of the connection. Never fails:
  /// joining without a microphone is still joining.
  static Future<bool> _publish(
      LivekitJoinRoom room, JoinMicrophone microphone) async {
    try {
      await room.publishMicrophone(microphone);
      return true;
    } catch (e, s) {
      Log.onError(e, s, content: "Could not enable the microphone");
      // The room went away meanwhile: nothing else would stop it.
      await _stop(microphone);
      return false;
    }
  }

  static Future<void> _stop(JoinMicrophone? microphone) async {
    try {
      await microphone?.stop();
    } catch (e, s) {
      Log.onError(e, s, content: "Could not close the microphone");
    }
  }

  /// [future], with its error logged rather than thrown: what runs beside
  /// the join must not fail it, nor fail unheard when the join fails first.
  static Future<void> _quiet(Future<void> future) =>
      future.catchError((Object e, StackTrace s) {
        Log.onError(e, s, content: "Voice join: a step beside the join failed");
      });
}
