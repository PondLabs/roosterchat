import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:flutter/widgets.dart';

class ErrorUtils {
  /// [title] falls back to "Error", translated ([AdaptiveDialog.showError]).
  static Future<void> tryRun(BuildContext context, Future<void> function(),
      {Future<void> Function()? onError, String? title}) async {
    try {
      await function();
    } catch (e, s) {
      Log.onError(e, s);
      AdaptiveDialog.showError(context, e, s, title: title);
      if (onError != null) {
        await onError();
      }
    }
  }
}
