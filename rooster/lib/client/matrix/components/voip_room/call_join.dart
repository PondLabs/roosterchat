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

  /// The session of the call, over [room] once connected. The join is
  /// still publishing the microphone until [microphonePublished] completes
  /// (it never fails): the session's mute and deafen wait for it, so they
  /// act on that microphone instead of opening a second one.
  S createSession(LivekitJoinRoom room, Future<void> microphonePublished);
}

/// One voice join, in the order the people in the call see it: the previous
/// call's membership cleared, then ours written and the connection side by
/// side, then the microphone.
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
/// The membership write and the connection start together and are both
/// awaited to their end before the join is done or undone. If either fails,
/// or the join is hung up meanwhile, the other is undone too: the membership
/// is cleared only once its write has settled, since a clear sent while the
/// write is in flight can land first and leave the membership behind (issue
/// #48). The microphone is published only once both have succeeded.
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
  /// once the join is allowed. When [hangUp] completes before the join is
  /// done, the join takes back what it sent and fails with [CallJoinHungUp]:
  /// no session and no membership come of it.
  Future<S> run(
      {Future<void> Function()? leavePrevious, Future<void>? hangUp}) async {
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
      return await trace
          .run(() => _join(trace, outside, leavePrevious, _HangUp(hangUp)));
    } catch (_) {
      trace.failed();
      rethrow;
    }
  }

  Future<S> _join(CallJoinTrace trace, Zone outside,
      Future<void> Function()? leavePrevious, _HangUp hangUp) async {
    final leaving = _quiet(trace.time(
        SpeedStep.leavePrevious,
        () => leavePrevious == null
            ? Future.value()
            : outside.run(leavePrevious)));
    // Awaited before the connection: joining while this is still running
    // leaves the call on whatever device the system chose. Its error fails
    // the join there, as before; not left failing unheard if a step below
    // fails first.
    final output =
        trace.time(SpeedStep.outputDevice, () => host.selectOutputDevice());
    output.ignore();

    // Asked for only when no call token of this room is held: a held one
    // (fetched ahead, see CallWarmUp) needs no OpenID token. The OpenID
    // token itself may be held too (CallTokenService).
    Future<matrix.OpenIdCredentials> askOpenId() => trace.time(
        SpeedStep.openIdToken, () => tokens.openId(host.openIdToken));
    final openIdRequest =
        tokens.holdsGrant(host.roomId, host.deviceId) ? null : askOpenId();
    // Not left failing unheard when the foci below throw first.
    openIdRequest?.ignore();
    final foci = await trace.time(SpeedStep.foci, host.foci);
    if (foci.isEmpty) {
      throw CallJoinException("Failed to find a valid LiveKit service",
          MatrixLivekitBackend.errorCallNoLivekitService);
    }
    final focus = foci.first;
    Log.d("Got Foci Url: $foci");
    checkFocus(focus);

    final first = await trace.time(
        SpeedStep.sfuToken,
        () => tokens.sfuGrant(focus,
            roomId: host.roomId,
            deviceId: host.deviceId,
            openId: () => openIdRequest ?? askOpenId()));
    final grant = first.grant;
    final cloud = isLivekitCloud(Uri.parse(grant.url));
    trace.sfuHost(livekitCloud: cloud);

    await output;
    final room = await host.createRoom();

    final joinKey =
        CallMembershipWrites.joinKey(host.roomId, host.membershipKey);
    // Local, not fields: two joins can overlap (two views of one room).
    Object? claim;
    Future<void>? write;
    Future<void>? connection;
    // Done once this join has kept its membership or cleared it.
    final membershipSettled = Completer<void>();
    JoinMicrophone? earlyMicrophone;
    Future<JoinMicrophone?>? preparedMicrophone;
    try {
      await leaving;
      hangUp.check();

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
      // erase what we write now (issue #48). So may an earlier join of this
      // room's, hung up (see below).
      await trace.time(
          SpeedStep.membershipClearWait,
          () => Future.wait([
                CallMembershipWrites.settled(host.membershipKey),
                CallMembershipWrites.settled(joinKey),
              ]));

      // Hung up before anything others see was sent: nothing is, and no
      // capture is opened (in a browser, nor its permission prompt).
      hangUp.check();

      if (early.track == null && early.retry) {
        preparedMicrophone = _prepareMicrophone(trace, room);
      }

      // A join of this room after this one (a quick rejoin) writes our
      // membership only once this one has kept it or cleared it: a clear of
      // ours landing after that write would erase it.
      CallMembershipWrites.clearing(joinKey, membershipSettled.future);
      // That wait is bounded: an earlier join that outlasts it leaves this
      // one's membership alone.
      claim = CallMembershipWrites.claim(joinKey);
      write = trace.time(
          SpeedStep.membershipWrite, () => host.writeMembership(foci));
      connection = trace.time(SpeedStep.connect,
          () => _connect(room, focus, first, askOpenId, hangUp));
      // Both to their end, also when one fails first (Future.wait reports
      // the first error once every future has finished).
      await Future.wait([write, connection]);
      hangUp.check();
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

      final session = outside.run(() => host.createSession(room, published));
      membershipSettled.complete();
      return session;
    } catch (_) {
      // Don't leave a membership for a call we never got into, nor a room
      // that keeps its connectivity listener and timers alive (issue #48).
      // The membership first: it is what other people see. Only once its
      // write has settled, even a write that failed (its request may still
      // have landed): a clear sent before could land first.
      if (write != null && claim != null) {
        await _settledOf(write);
        if (CallMembershipWrites.superseded(joinKey, claim)) {
          // A later join of this room wrote it since, and holds it.
          Log.i("Voice join undone: our membership is a later join's now");
        } else {
          try {
            await host.clearMembership();
          } catch (e, s) {
            Log.onError(e, s, content: "Could not clear call membership");
          }
        }
        CallMembershipWrites.release(joinKey, claim);
      }
      if (!membershipSettled.isCompleted) membershipSettled.complete();
      if (connection != null) await _settledOf(connection);
      await room.dispose();
      // Nor a microphone opened ahead of a room that never connected,
      // capturing with nothing left that could stop it.
      await _stop(earlyMicrophone);
      unawaited(preparedMicrophone?.then(_stop));
      rethrow;
    }
  }

  /// Connects [room] with [first]. A held call token the SFU refuses
  /// (expired or revoked since it was fetched) is dropped, and the join asks
  /// for a new one and connects again, once.
  Future<void> _connect(
      LivekitJoinRoom room,
      Uri focus,
      HeldGrant first,
      Future<matrix.OpenIdCredentials> Function() openId,
      _HangUp hangUp) async {
    try {
      await room.connect(first.grant.url, first.grant.jwt);
    } catch (e) {
      if (!first.held || !room.refusedToken(e)) rethrow;
      Log.i("Voice join: the SFU refused a held call token, asking again");
      tokens.forgetGrant(focus, roomId: host.roomId, deviceId: host.deviceId);
      hangUp.check();
      final again = await tokens.sfuGrant(focus,
          roomId: host.roomId, deviceId: host.deviceId, openId: openId);
      hangUp.check();
      await room.connect(again.grant.url, again.grant.jwt);
    }
  }

  /// Throws unless [focus], the call token service, may be sent our OpenID
  /// token: a remote service must be HTTPS, since the OpenID-backed
  /// requests leave this device. A loopback service (a developer's local
  /// stack, and the integration one) is trusted by its address.
  static void checkFocus(Uri focus) {
    final focusLoopback = focus.host == "localhost" ||
        focus.host.startsWith("127.") ||
        focus.host == "::1" ||
        focus.host == "[::1]";
    if (focus.scheme != "https" && !focusLoopback) {
      throw CallJoinException("Selected focus JWT does not use HTTPS",
          MatrixLivekitBackend.errorCallFocusNotHttps);
    }
  }

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

  /// Done when [future] is, whether it failed or not (its error is the
  /// join's to report, not this wait's).
  static Future<void> _settledOf(Future<void> future) =>
      future.then((_) {}, onError: (_) {});

  /// [future], with its error logged rather than thrown: what runs beside
  /// the join must not fail it, nor fail unheard when the join fails first.
  static Future<void> _quiet(Future<void> future) =>
      future.catchError((Object e, StackTrace s) {
        Log.onError(e, s, content: "Voice join: a step beside the join failed");
      });
}

/// The join was hung up before it was done: what it had sent was taken back.
class CallJoinHungUp implements Exception {
  const CallJoinHungUp();

  @override
  String toString() => "CallJoinHungUp: the join was hung up";
}

/// Whether a join was hung up ([CallJoin.run]'s `hangUp`).
class _HangUp {
  _HangUp(Future<void>? hangUp) {
    hangUp?.then((_) => _hungUp = true, onError: (_) => _hungUp = true);
  }

  bool _hungUp = false;

  /// Stops the join if it was hung up.
  void check() {
    if (_hungUp) throw const CallJoinHungUp();
  }
}
