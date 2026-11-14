// What a game hands the call's stage, and what the stage hands the game:
// the Flutter half of the CallActivity descriptor's hooks (the contracts in
// call_activity_component.dart stay free of widgets). The call view knows no
// game: it asks the descriptor for a controller, and the controller for the
// view that fills the stage.
import 'package:flutter/widgets.dart';

import 'package:rooster/client/components/voip/voip_stream.dart';

import 'call_activity_session.dart';

/// What the call gives a game's controller: the session it plays, and the
/// people of the call it is played in.
class CallActivityCallContext {
  const CallActivityCallContext({
    required this.session,
    required this.nameOf,
    required this.avatarOf,
    required this.cameraOf,
    required this.onEnded,
  });

  /// The session this controller plays, launched or joined.
  final CallActivitySession session;

  /// A call identity's display name (the roster's identities are LiveKit
  /// identities: a matrix user id with a device suffix).
  final String Function(String identity) nameOf;

  /// A call identity's avatar, when it has one.
  final ImageProvider? Function(String identity) avatarOf;

  /// The camera of the participant with [identity] (the roster's
  /// currency), live from the call: null while they have none on. Asked
  /// again on each build - the call replaces a stream when a camera is
  /// turned off and on. A game that draws the players' videos itself
  /// ([CallActivity.drawsPlayerVideos]) renders them from here.
  final VoipStream? Function(String identity) cameraOf;

  /// The session ended under us (the host closed it, or nobody is left):
  /// the stage should go. The controller calls it at most once.
  final VoidCallback onEnded;
}

/// One client's live game of one session, on the call's stage. Built by
/// [CallActivity.createController] when we launch, join, or come back to a
/// session we hold a seat in; the call view listens to it and rebuilds the
/// stage when it notifies.
abstract class CallActivityController implements Listenable {
  /// The launcher's start: take the host seat ([CallActivitySession.launch])
  /// and set the game up from [options], the value
  /// [CallActivity.launchOptions] returned (null when the descriptor has no
  /// launch options).
  Future<void> hostStart(Object? options);

  /// The view that fills the stage under the header. Null while there is
  /// nothing to show yet (the first state has not come): the stage shows
  /// its "Loading" placeholder. [onLeave] is the game's own way out (its
  /// menu's leave); the stage's exit button does the same.
  Widget? buildStage(BuildContext context, {required VoidCallback onLeave});

  /// Out of the session: the session knows first (the host hands its seat
  /// over), the game follows.
  Future<void> leave();

  /// Releases everything the game holds - its timers, its sound - once the
  /// stage is gone. Called once, after [leave] or with the call view.
  Future<void> dispose();
}
