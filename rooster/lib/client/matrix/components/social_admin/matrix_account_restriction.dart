import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/alert.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/main.dart';

/// Why the homeserver refuses the account (Matrix v1.8 `M_USER_LOCKED`,
/// v1.12 `M_USER_SUSPENDED`).
enum AccountRestriction { locked, suspended }

/// Watches one account's sync for a lock or a suspension. Neither is a soft
/// logout: the session and its keys stay. The sync loop of that account (and
/// only that one) stops instead of asking again every few seconds, and comes
/// back after [firstRetry], then twice as long each time up to [maxRetry], or
/// when [checkAgain] is called. The first sync that goes through clears it.
class AccountRestrictionWatcher {
  AccountRestrictionWatcher({
    required Stream<matrix.SyncStatusUpdate> syncStatus,
    required void Function(bool enabled) setBackgroundSync,
    this.firstRetry = const Duration(minutes: 1),
    this.maxRetry = const Duration(minutes: 30),
  })  : _setBackgroundSync = setBackgroundSync,
        _nextRetry = firstRetry {
    _subscription = syncStatus.listen(_onSyncStatus);
  }

  final Duration firstRetry;
  final Duration maxRetry;
  final void Function(bool enabled) _setBackgroundSync;
  late final StreamSubscription<matrix.SyncStatusUpdate> _subscription;

  /// The restriction last reported, or null while the account works.
  final ValueNotifier<AccountRestriction?> restriction = ValueNotifier(null);

  Timer? _retry;
  Duration _nextRetry;

  static AccountRestriction? restrictionOf(Object? error) {
    if (error is! matrix.MatrixException) return null;
    return switch (error.error) {
      matrix.MatrixError.M_USER_LOCKED => AccountRestriction.locked,
      matrix.MatrixError.M_USER_SUSPENDED => AccountRestriction.suspended,
      _ => null,
    };
  }

  void _onSyncStatus(matrix.SyncStatusUpdate update) {
    if (update.status == matrix.SyncStatus.finished) {
      _retry?.cancel();
      _retry = null;
      _nextRetry = firstRetry;
      restriction.value = null;
      return;
    }
    if (update.status != matrix.SyncStatus.error) return;
    final kind = restrictionOf(update.error?.exception);
    if (kind != null) report(kind);
  }

  /// Stops the sync of this account and plans the next attempt, unless one
  /// is already planned.
  void report(AccountRestriction kind) {
    restriction.value = kind;
    _setBackgroundSync(false);
    if (_retry != null) return;
    _retry = Timer(_nextRetry, checkAgain);
    final doubled = _nextRetry * 2;
    _nextRetry = doubled > maxRetry ? maxRetry : doubled;
  }

  /// Tries the sync again now.
  void checkAgain() {
    _retry?.cancel();
    _retry = null;
    _setBackgroundSync(true);
  }

  void dispose() {
    _retry?.cancel();
    _subscription.cancel();
    restriction.dispose();
  }
}

/// Puts an alert on the Home screen while the account is locked or
/// suspended; the account settings show the same with a "Check again".
class MatrixAccountRestrictionComponent extends Component<MatrixClient> {
  MatrixAccountRestrictionComponent(super.client)
      : watcher = AccountRestrictionWatcher(
          syncStatus: client.getMatrixClient().onSyncStatus.stream,
          setBackgroundSync: (enabled) =>
              client.getMatrixClient().backgroundSync = enabled,
        ) {
    watcher.restriction.addListener(_updateAlert);
  }

  final AccountRestrictionWatcher watcher;
  Alert? _alert;

  static String get labelAccountLocked => Intl.message("Your account is locked",
      name: "labelAccountLocked",
      desc: "Title of the banner shown when the homeserver locked the "
          "user's account (Matrix error M_USER_LOCKED)");

  static String messageAccountLocked(String account) => Intl.message(
      "The administrators of your server locked $account. Rooster stopped "
      "syncing it and checks again from time to time. You are still signed "
      "in and nothing was deleted.",
      name: "messageAccountLocked",
      args: [account],
      desc: "Banner shown when the homeserver locked the user's account; "
          "account is the Matrix ID");

  static String get labelAccountSuspended =>
      Intl.message("Your account is suspended",
          name: "labelAccountSuspended",
          desc: "Title of the banner shown when the homeserver suspended the "
              "user's account (Matrix error M_USER_SUSPENDED)");

  static String messageAccountSuspended(String account) => Intl.message(
      "The administrators of your server suspended $account. You can still "
      "read, but you can't send messages, join rooms or change your profile. "
      "Rooster checks again from time to time.",
      name: "messageAccountSuspended",
      args: [account],
      desc: "Banner shown when the homeserver suspended the user's account; "
          "account is the Matrix ID");

  static String titleOf(AccountRestriction kind) =>
      kind == AccountRestriction.locked
          ? labelAccountLocked
          : labelAccountSuspended;

  static String messageOf(AccountRestriction kind, String account) =>
      kind == AccountRestriction.locked
          ? messageAccountLocked(account)
          : messageAccountSuspended(account);

  String get account => client.getMatrixClient().userID ?? client.identifier;

  void _updateAlert() {
    final alerts = clientManager?.alertManager;
    if (watcher.restriction.value == null) {
      final alert = _alert;
      _alert = null;
      if (alert != null) alerts?.clearAlert(alert);
      return;
    }
    if (_alert != null) return;
    final kind = () => watcher.restriction.value ?? AccountRestriction.locked;
    final alert = _alert = Alert(AlertType.warning,
        titleGetter: () => titleOf(kind()),
        messageGetter: () => messageOf(kind(), account));
    alerts?.addAlert(alert);
  }
}
