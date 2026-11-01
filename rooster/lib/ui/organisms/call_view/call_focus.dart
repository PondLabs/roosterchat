import 'dart:async';

import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/components/voip/voip_stream.dart';

/// Asks a call's view to put someone in the middle of it: a click on them
/// under the voice channel in the sidebar.
abstract final class CallFocus {
  /// Who each call's view was asked to show, until it takes the request.
  /// Kept, not only broadcast: the call view may not be showing yet.
  static final Expando<String> _wanted = Expando();
  static final StreamController<VoipSession> _requests =
      StreamController.broadcast();
  static Stream<VoipSession> get onRequested => _requests.stream;

  /// Asks the call view of [session] to show [userId].
  static void show(VoipSession session, String userId) {
    _wanted[session] = userId;
    _requests.add(session);
  }

  /// Who the call view of [session] was asked to show, clearing the ask.
  static String? takeRequest(VoipSession session) {
    final userId = _wanted[session];
    _wanted[session] = null;
    return userId;
  }

  /// What to show of [userId]: their screen, the sidebar's first choice
  /// too, or else their camera. The other one stays in the grid.
  static VoipStream? streamOf(Iterable<VoipStream> streams, String userId) {
    final theirs = streams.where((s) => s.streamUserId == userId);
    return theirs
            .where((s) => s.type == VoipStreamType.screenshare)
            .firstOrNull ??
        theirs.where((s) => s.type == VoipStreamType.video).firstOrNull;
  }
}
