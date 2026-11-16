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
/// opening a channel again sends no new token request, and while the
/// room's call token is held it does not fetch the well-known either.
///
/// It talks only to the token service the account's homeserver names in
/// its well-known: the room's oldest call membership names the call's
/// service, and any member of the room writes it. When that names another
/// service, nothing is sent before the click, and the join asks for
/// everything then.
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
      // Held already: the join needs nothing more, not even the
      // well-known (nor the OpenID token, which only buys a call token).
      if (tokens.holdsGrant(host.roomId, host.deviceId)) return;
      final homeserver = await host.homeserverFocus();
      if (homeserver == null) return;
      final room = host.roomFocus();
      if (room != null && !sameService(room, homeserver)) return;
      // The service the join will use, as it names it: the token is held
      // under that name.
      final focus = room ?? homeserver;
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

  /// Whether [a] and [b] name the same token service: the same scheme,
  /// host and port (a port left out is the scheme's default), the same
  /// path once dot segments and trailing slashes are dropped, and the same
  /// user info, query and fragment. Host names compare without case. Not a
  /// likeness of hosts: `jwt.example.org` is not `jwt.example.org.evil`.
  static bool sameService(Uri a, Uri b) {
    String path(Uri uri) =>
        uri.normalizePath().path.replaceFirst(RegExp(r'/+$'), '');
    return a.host.isNotEmpty &&
        a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
        a.host.toLowerCase() == b.host.toLowerCase() &&
        a.port == b.port &&
        a.userInfo == b.userInfo &&
        path(a) == path(b) &&
        a.query == b.query &&
        a.fragment == b.fragment;
  }

  /// Warms [voip]'s call, when it is a Matrix voice channel (the only kind
  /// with a call token service). Never fails.
  static void warm(VoipRoomComponent voip) {
    if (voip is MatrixVoipRoomComponent) unawaited(voip.warmUp());
  }
}
