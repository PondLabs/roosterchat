import 'dart:async';

import 'package:rooster/client/components/voip_room/voip_room_component.dart';
import 'package:rooster/client/matrix/components/voip_room/call_join.dart';
import 'package:rooster/client/matrix/components/voip_room/call_token_service.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:rooster/debug/log.dart';

/// What a voice join needs from the network, fetched before the click:
/// when a voice channel's page opens, or the pointer or focus rests on a
/// join button (on the page and in Who's around).
///
/// It opens the connection to the call's token service (`GET /healthz`,
/// any answer will do), and asks for the account's OpenID token and this
/// room's call token (`/sfu/get`), which [CallTokenService] holds in memory
/// for the join that follows. Each is asked for only when none is held, so
/// opening a channel again sends no new token request.
///
/// It opens no microphone, no camera and no LiveKit connection, and
/// nothing it does is shown: an error is logged (never a token) and the
/// join asks again.
class CallWarmUp {
  CallWarmUp({required this.host, required this.tokens});

  final CallJoinHost<Object?> host;
  final CallTokenService tokens;

  /// Never fails.
  Future<void> run() async {
    try {
      // A member who may not join gets no tokens: the join stops before it
      // would use them.
      if (!host.canWriteMembership || tokens.isClosed) return;
      final foci = await host.foci();
      if (foci.isEmpty) return;
      final focus = foci.first;
      // The OpenID token goes only where a join would send it.
      CallJoin.checkFocus(focus);
      // Beside the tokens, not before them. Never fails.
      final connection = tokens.warmConnection(focus);
      try {
        await tokens.sfuGrant(focus,
            roomId: host.roomId,
            deviceId: host.deviceId,
            openId: () => tokens.openId(host.openIdToken, ahead: true),
            ahead: true);
      } finally {
        await connection;
      }
    } catch (e) {
      // The error's type only: a token service's answer may quote the
      // request.
      Log.d("Voice warm-up: no tokens ahead (${e.runtimeType})");
    }
  }

  /// Warms [voip]'s call, when it is a Matrix voice channel (the only kind
  /// with a call token service). Never fails.
  static void warm(VoipRoomComponent voip) {
    if (voip is MatrixVoipRoomComponent) unawaited(voip.warmUp());
  }
}
