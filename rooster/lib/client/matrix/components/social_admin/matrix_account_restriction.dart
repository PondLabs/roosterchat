import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/alert.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/matrix/auth/matrix_token_refresher.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/main.dart';

/// Why the homeserver refuses the account (Matrix v1.8 `M_USER_LOCKED`,
/// v1.12 `M_USER_SUSPENDED`).
enum AccountRestriction { locked, suspended }

/// Watches one account's sync and homeserver responses for a lock or a
/// suspension. Neither is a soft logout: the session and its keys stay.
///
/// For a lock (`M_USER_LOCKED`), the sync loop of that account (and only that
/// one) stops instead of asking again every few seconds, and comes back after
/// [firstRetry], then twice as long each time up to [maxRetry], or when
/// [checkAgain] is called (only while [canResume] allows it, e.g. the token
/// refresher is still active). The first sync that goes through clears it.
///
/// For a suspension (`M_USER_SUSPENDED`, Matrix v1.12), the account keeps
/// syncing so the person can still read, and the banner stays until
/// [checkAgain] is called or the restriction changes.
class AccountRestrictionWatcher {
  AccountRestrictionWatcher({
    required Stream<matrix.SyncStatusUpdate> syncStatus,
    required void Function(bool enabled) setBackgroundSync,
    Stream<matrix.MatrixError>? restrictionErrors,
    bool Function()? canResume,
    this.firstRetry = const Duration(minutes: 1),
    this.maxRetry = const Duration(minutes: 30),
  })  : _setBackgroundSync = setBackgroundSync,
        _canResume = canResume ?? _alwaysResume,
        _nextRetry = firstRetry {
    _subscription = syncStatus.listen(_onSyncStatus);
    _errorSubscription = restrictionErrors?.listen(_onRestrictionError);
  }

  static bool _alwaysResume() => true;

  final Duration firstRetry;
  final Duration maxRetry;
  final void Function(bool enabled) _setBackgroundSync;
  final bool Function() _canResume;
  late final StreamSubscription<matrix.SyncStatusUpdate> _subscription;
  StreamSubscription<matrix.MatrixError>? _errorSubscription;

  /// The restriction last reported, or null while the account works.
  final ValueNotifier<AccountRestriction?> restriction = ValueNotifier(null);

  Timer? _retry;
  Duration _nextRetry;
  bool _syncStopped = false;

  static AccountRestriction? restrictionOfError(matrix.MatrixError error) =>
      switch (error) {
        matrix.MatrixError.M_USER_LOCKED => AccountRestriction.locked,
        matrix.MatrixError.M_USER_SUSPENDED => AccountRestriction.suspended,
        _ => null,
      };

  static AccountRestriction? restrictionOf(Object? error) {
    if (error is! matrix.MatrixException) return null;
    return restrictionOfError(error.error);
  }

  void _onRestrictionError(matrix.MatrixError error) {
    final kind = restrictionOfError(error);
    if (kind != null) report(kind);
  }

  void _onSyncStatus(matrix.SyncStatusUpdate update) {
    if (update.status == matrix.SyncStatus.finished) {
      _retry?.cancel();
      _retry = null;
      _nextRetry = firstRetry;
      _syncStopped = false;
      if (restriction.value == AccountRestriction.locked) {
        restriction.value = null;
      }
      return;
    }
    if (update.status != matrix.SyncStatus.error) return;
    final kind = restrictionOf(update.error?.exception);
    if (kind != null) report(kind);
  }

  /// Records a restriction. For a lock, stops the sync of this account and
  /// plans the next attempt unless one is already planned. For a suspension,
  /// leaves sync running so the person can still read (Matrix v1.12).
  void report(AccountRestriction kind) {
    restriction.value = kind;
    if (kind == AccountRestriction.suspended) {
      if (_syncStopped) {
        _retry?.cancel();
        _retry = null;
        _syncStopped = false;
        if (_canResume()) _setBackgroundSync(true);
      }
      return;
    }
    _syncStopped = true;
    _setBackgroundSync(false);
    if (_retry != null) return;
    _retry = Timer(_nextRetry, checkAgain);
    final doubled = _nextRetry * 2;
    _nextRetry = doubled > maxRetry ? maxRetry : doubled;
  }

  /// Tries the sync again now (only when [canResume] allows it), or clears a
  /// suspension banner whose sync stayed on.
  void checkAgain() {
    _retry?.cancel();
    _retry = null;
    if (restriction.value == AccountRestriction.suspended && !_syncStopped) {
      restriction.value = null;
      return;
    }
    if (!_canResume()) return;
    _syncStopped = false;
    _setBackgroundSync(true);
  }

  void dispose() {
    _retry?.cancel();
    _subscription.cancel();
    _errorSubscription?.cancel();
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
          restrictionErrors: client.tokenRefresher.onRestriction,
          canResume: () =>
              client.tokenRefresher.state.value == TokenRefreshState.active,
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
