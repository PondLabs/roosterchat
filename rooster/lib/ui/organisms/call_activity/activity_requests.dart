import 'dart:async';

import 'package:rooster/client/components/voip/voip_session.dart';

/// What the sidebar's rocket asks of a call's view, which owns the
/// activity's stage (as DjBooths does for the booth panel).
class CallActivityRequests {
  CallActivityRequests._();

  /// Calls whose shelf of activities someone asked to see, until the call
  /// view takes the request. Kept, not only broadcast: the call view may
  /// not be showing yet.
  static final Set<VoipSession> _shelfWanted = {};
  static final StreamController<VoipSession> _shelfRequests =
      StreamController.broadcast();
  static Stream<VoipSession> get onShelfRequested => _shelfRequests.stream;

  /// Asks the call view of [session] to open its shelf of activities.
  static void showShelf(VoipSession session) {
    _shelfWanted.add(session);
    _shelfRequests.add(session);
  }

  /// Whether the shelf of [session] was asked for, clearing the ask.
  static bool takeShelfRequest(VoipSession session) =>
      _shelfWanted.remove(session);

  /// How the call view showing [session] leaves its stage (the game's view
  /// and sound go with it); absent while no call view shows the call.
  static final Map<VoipSession, Future<void> Function()> stageExits = {};
}
