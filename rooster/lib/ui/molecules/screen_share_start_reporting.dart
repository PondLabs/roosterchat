import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/debug/log.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Picks what to share and starts sharing it in [session], and tells the
/// user when that cannot be done.
///
/// The share control lives on two surfaces, the voice panel and the call
/// view, and the tiamat buttons that host them call their callback as a bare
/// [Function] without awaiting it. The call view's start had no error
/// handling of its own: where the screen cannot be captured (a phone's
/// browser) or the capture failed, the button did nothing at all. Both
/// surfaces go through this helper, like stopScreenshareOrReportFailure.
Future<void> startScreenshareOrReportFailure(
    BuildContext context, VoipSession session) async {
  // Looked up before the await: the picker can outlive the surface that
  // asked for it, and looking an ancestor up on a disposed context throws.
  final messenger = context.mounted ? ScaffoldMessenger.maybeOf(context) : null;

  if (!session.supportsScreenshare) {
    _report(messenger, messageScreenShareUnsupported);
    return;
  }

  try {
    final source = await session.pickScreenCapture(context);
    if (source == null) return;
    await session.setScreenShare(source);
  } catch (e, s) {
    // Closing the browser's own picker is an answer, not a failure.
    if (isScreenCaptureDismissed(e)) return;
    Log.onError(e, s, content: "Could not start screen sharing");
    _report(messenger, messageCouldNotShareScreen);
  }
}

/// Whether [error] is the browser saying its screen picker was closed
/// without a choice. It reports that as `NotAllowedError`, the same name it
/// gives a capture the operating system refused ("Permission denied by
/// system" in Chrome, when macOS has not been told the browser may record
/// the screen), which is a failure the user has to hear about.
bool isScreenCaptureDismissed(Object error) {
  final text = error.toString();
  return text.contains('NotAllowedError') && !text.contains('by system');
}

void _report(ScaffoldMessengerState? messenger, String message) {
  // A messenger that went away with the app has no user left to tell, and
  // showing a SnackBar on a disposed one would throw.
  if (messenger == null || !messenger.mounted) return;
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

String get messageCouldNotShareScreen =>
    Intl.message("Could not share your screen.",
        name: "messageCouldNotShareScreen",
        desc: "Shown when starting a screen share fails");

String get messageScreenShareUnsupported => Intl.message(
    "This browser can't share your screen. Use the Rooster app, or a "
    "browser on a computer.",
    name: "messageScreenShareUnsupported",
    desc: "Shown where the browser has no screen capture at all, as on "
        "phones and tablets");
