// Criterion 3: M_USER_LOCKED and M_USER_SUSPENDED show a translated banner;
// a locked account stops the sync loop of that account (not a soft logout,
// nothing deleted) and tries again with a growing wait without overriding a
// token-refresh stop, while a suspended account keeps syncing and reports
// 403 M_USER_SUSPENDED from forbidden actions (Matrix v1.12).
// ignore_for_file: invalid_use_of_visible_for_testing_member
@TestOn('vm')
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' as intl;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/auth/matrix_token_refresher.dart';
import 'package:rooster/client/matrix/components/social_admin/matrix_account_restriction.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/ui/pages/settings/categories/account/account_state/account_restriction_banner.dart';

import '../matrix_phase0/test_helpers.dart';
import '../matrix_room_directory/fakes.dart';
import '../speed_log/fake_account.dart';

matrix.SyncStatusUpdate syncError(String errcode, {bool softLogout = false}) =>
    matrix.SyncStatusUpdate(matrix.SyncStatus.error,
        error: matrix.SdkError(
            exception: matrix.MatrixException.fromJson({
          'errcode': errcode,
          'error': errcode,
          if (softLogout) 'soft_logout': true,
        })));

/// A watcher on a hand-fed sync status, recording what it does to the sync.
class Harness {
  Harness({bool Function()? canResume}) {
    watcher = AccountRestrictionWatcher(
        syncStatus: status.stream,
        setBackgroundSync: syncSwitch.add,
        restrictionErrors: errors.stream,
        canResume: canResume);
  }
  final status = StreamController<matrix.SyncStatusUpdate>.broadcast();
  final errors = StreamController<matrix.MatrixError>.broadcast();
  final syncSwitch = <bool>[];
  late final AccountRestrictionWatcher watcher;
}

/// A logged-in SDK client that counts its soft logouts.
class LockedClient extends matrix.Client {
  LockedClient(String name, this.script, this.softLogouts)
      : super(name,
            httpClient: script.transport,
            database: MemoryCacheDatabase(),
            onSoftLogout: (_) async => softLogouts.add(name)) {
    homeserver = Uri.parse('http://127.0.0.1:9');
    accessToken = 'test-token';
    syncErrorTimeoutSec = 0;
  }
  final Script script;
  final List<String> softLogouts;

  @override
  String? get userID => self;
}

/// An SDK client wired to a real [MatrixTokenRefresher] and optional
/// [TokenRefreshingHttpClient].
class RefreshingClient extends matrix.Client {
  RefreshingClient(
      http.Client httpClient, MatrixTokenRefresher Function() refresher)
      : super('locked_refresh',
            httpClient: httpClient,
            database: MemoryCacheDatabase(),
            onSoftLogout: (c) => refresher().onSoftLogout(c)) {
    homeserver = Uri.parse('http://127.0.0.1:9');
    accessToken = 'test-token';
    syncErrorTimeoutSec = 0;
  }

  @override
  String? get userID => self;
}

void main() {
  setUpAll(prepareTests);

  test('M_USER_LOCKED stops the sync and retries after 1, 2, 4 minutes', () {
    fakeAsync((time) {
      final h = Harness();
      h.status.add(syncError('M_USER_LOCKED'));
      time.flushMicrotasks();
      expect(h.watcher.restriction.value, AccountRestriction.locked);
      expect(h.syncSwitch, [false]);

      // The loop already queued one more request: it fails again, and no
      // other attempt is planned for it.
      h.status.add(syncError('M_USER_LOCKED'));
      time.elapse(const Duration(seconds: 59));
      expect(h.syncSwitch, [false, false]);
      time.elapse(const Duration(seconds: 1));
      expect(h.syncSwitch, [false, false, true]);

      h.status.add(syncError('M_USER_LOCKED'));
      time.elapse(const Duration(seconds: 119));
      expect(h.syncSwitch.last, isFalse);
      time.elapse(const Duration(seconds: 1));
      expect(h.syncSwitch.last, isTrue);

      h.status.add(syncError('M_USER_LOCKED'));
      time.elapse(const Duration(minutes: 4));
      expect(h.syncSwitch.where((on) => on), hasLength(3));
    });
  });

  test('M_USER_SUSPENDED keeps sync running and survives finished syncs', () {
    fakeAsync((time) {
      final h = Harness();
      h.errors.add(matrix.MatrixError.M_USER_SUSPENDED);
      time.flushMicrotasks();
      expect(h.watcher.restriction.value, AccountRestriction.suspended);
      expect(h.syncSwitch, isEmpty);

      // Matrix v1.12: suspended accounts continue syncing; a finished sync
      // must not erase the suspension banner.
      h.status.add(matrix.SyncStatusUpdate(matrix.SyncStatus.finished));
      time.flushMicrotasks();
      expect(h.watcher.restriction.value, AccountRestriction.suspended);
      expect(h.syncSwitch, isEmpty);

      // Tapping "Check again" clears the suspension banner without toggling
      // backgroundSync.
      h.watcher.checkAgain();
      expect(h.watcher.restriction.value, isNull);
      expect(h.syncSwitch, isEmpty);
    });
  });

  test('the wait stops growing at 30 minutes', () {
    fakeAsync((time) {
      final h = Harness();
      for (var i = 0; i < 8; i++) {
        h.status.add(syncError('M_USER_LOCKED'));
        time.elapse(const Duration(minutes: 30));
      }
      expect(h.syncSwitch.where((on) => on), hasLength(8));
    });
  });

  test('a sync that goes through clears it and resets the wait', () {
    fakeAsync((time) {
      final h = Harness();
      h.status.add(syncError('M_USER_LOCKED'));
      time.elapse(const Duration(minutes: 1));
      h.status.add(matrix.SyncStatusUpdate(matrix.SyncStatus.finished));
      time.flushMicrotasks();
      expect(h.watcher.restriction.value, isNull);

      h.status.add(syncError('M_USER_LOCKED'));
      time.elapse(const Duration(minutes: 1));
      expect(h.syncSwitch, [false, true, false, true]);
    });
  });

  test('other errors leave the sync alone', () {
    fakeAsync((time) {
      final h = Harness();
      h.status.add(syncError('M_UNKNOWN'));
      h.status.add(syncError('M_UNKNOWN_TOKEN', softLogout: true));
      h.status.add(matrix.SyncStatusUpdate(matrix.SyncStatus.error,
          error: matrix.SdkError(exception: Exception('offline'))));
      time.elapse(const Duration(hours: 1));
      expect(h.syncSwitch, isEmpty);
      expect(h.watcher.restriction.value, isNull);
    });
  });

  test(
      'a locked account stops asking for /sync and is not soft logged out, '
      'while the sync loop of another account keeps running', () async {
    final softLogouts = <String>[];
    http(Script script, {required bool locked}) => script.routes.add((r) {
          if (r.path.endsWith('/filter')) return json({'filter_id': '1'});
          if (!r.path.endsWith('/sync')) return null;
          return locked
              ? json({
                  'errcode': 'M_USER_LOCKED',
                  'error': 'locked',
                  'soft_logout': true,
                }, status: 401)
              : json({'next_batch': 's${script.seen.length}'});
        });
    final lockedScript = Script(), otherScript = Script();
    http(lockedScript, locked: true);
    http(otherScript, locked: false);
    final locked = LockedClient('locked_account', lockedScript, softLogouts);
    final other = LockedClient('other_account', otherScript, softLogouts);
    final watchers = [
      for (final client in [locked, other])
        AccountRestrictionWatcher(
            syncStatus: client.onSyncStatus.stream,
            setBackgroundSync: (on) => client.backgroundSync = on),
    ];

    locked.backgroundSync = true;
    other.backgroundSync = true;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final lockedSyncs = lockedScript.where('GET', '/sync').length;
    final otherSyncs = otherScript.where('GET', '/sync').length;
    await other.abortSync();
    await locked.abortSync();

    // Without the watcher, a 0 s error timeout asks hundreds of times.
    expect(lockedSyncs, inInclusiveRange(1, 2));
    expect(otherSyncs, greaterThan(5));
    expect(watchers.first.restriction.value, AccountRestriction.locked);
    expect(watchers.last.restriction.value, isNull);
    expect(softLogouts, isEmpty);
    expect(locked.accessToken, 'test-token');
    for (final w in watchers) {
      w.dispose();
    }
  });

  // Review c1-1: a locked account whose token renewal gets 401 M_USER_LOCKED
  // stays active (no soft-logout / sign-in-again prompt) and "Check again"
  // does not start a sync loop while the access token is expired.
  test(
      'c1-1: a locked account whose refresh returns M_USER_LOCKED stays active '
      'and "Check again" does not start a sync loop on the expired token',
      () async {
    var phase = 'locked';
    final script = Script();
    script.routes.add((r) {
      if (r.path.endsWith('/filter')) return json({'filter_id': '1'});
      if (!r.path.endsWith('/sync')) return null;
      return switch (phase) {
        'locked' => json({
            'errcode': 'M_USER_LOCKED',
            'error': 'locked',
            'soft_logout': true,
          }, status: 401),
        // The access token expired meanwhile and was not renewed.
        'expired' => json({
            'errcode': 'M_UNKNOWN_TOKEN',
            'error': 'expired',
            'soft_logout': true,
          }, status: 401),
        _ => json({'next_batch': 'ok1'}),
      };
    });
    late MatrixTokenRefresher refresher;
    final client = RefreshingClient(script.transport, () => refresher);
    // Spec v1.8: a locked account gets 401 M_USER_LOCKED on every endpoint
    // but logout, /refresh included.
    refresher = MatrixTokenRefresher(() => client, renew: (_) async {
      if (phase != 'ok') {
        throw matrix.MatrixException.fromJson({
          'errcode': 'M_USER_LOCKED',
          'error': 'locked',
          'soft_logout': true,
        });
      }
      client.accessToken = 'renewed-token';
    });
    final watcher = AccountRestrictionWatcher(
        syncStatus: client.onSyncStatus.stream,
        setBackgroundSync: (on) => client.backgroundSync = on,
        restrictionErrors: refresher.onRestriction,
        canResume: () => refresher.state.value == TokenRefreshState.active);

    client.backgroundSync = true;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(watcher.restriction.value, AccountRestriction.locked);

    // Renewal while locked is transient: do not move to needsReauthentication.
    phase = 'expired';
    await refresher.refresh();
    expect(refresher.state.value, TokenRefreshState.active);

    final before = script.where('GET', '/sync').length;
    // The watcher's timer, or the banner's "Check again".
    watcher.checkAgain();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final after = script.where('GET', '/sync').length;

    // At most the one attempt "Check again" asked for, not a loop.
    expect(after - before, lessThanOrEqualTo(2),
        reason: 'sync requests after "Check again": ${after - before}');
    expect(refresher.state.value, TokenRefreshState.active);
    expect(watcher.restriction.value, AccountRestriction.locked);

    // Once unlocked, token renewal works again (never stuck in reauth) and
    // "Check again" resumes sync.
    phase = 'ok';
    expect(await refresher.refresh(), 'renewed-token');
    watcher.checkAgain();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(script.where('GET', '/sync').length, greaterThan(after));
    await client.abortSync();
    watcher.dispose();
  });

  // Review c1-1: when the refresher genuinely moved to needsReauthentication
  // (refresh token revoked), "Check again" must not undo the sync stop.
  test(
      'c1-1: when token renewal is refused (needsReauthentication), '
      '"Check again" does not restart the sync loop', () async {
    var phase = 'locked';
    final script = Script();
    script.routes.add((r) {
      if (r.path.endsWith('/filter')) return json({'filter_id': '1'});
      if (!r.path.endsWith('/sync')) return null;
      return phase == 'locked'
          ? json({
              'errcode': 'M_USER_LOCKED',
              'error': 'locked',
              'soft_logout': true,
            }, status: 401)
          : json({
              'errcode': 'M_UNKNOWN_TOKEN',
              'error': 'expired',
              'soft_logout': true,
            }, status: 401);
    });
    late MatrixTokenRefresher refresher;
    final client = RefreshingClient(script.transport, () => refresher);
    refresher = MatrixTokenRefresher(() => client,
        renew: (_) async => throw matrix.MatrixException.fromJson({
              'errcode': 'M_UNKNOWN_TOKEN',
              'error': 'revoked',
              'soft_logout': false,
            }));
    final watcher = AccountRestrictionWatcher(
        syncStatus: client.onSyncStatus.stream,
        setBackgroundSync: (on) => client.backgroundSync = on,
        restrictionErrors: refresher.onRestriction,
        canResume: () => refresher.state.value == TokenRefreshState.active);

    client.backgroundSync = true;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(watcher.restriction.value, AccountRestriction.locked);

    phase = 'expired';
    await refresher.refresh();
    expect(refresher.state.value, TokenRefreshState.needsReauthentication);

    final before = script.where('GET', '/sync').length;
    watcher.checkAgain();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final after = script.where('GET', '/sync').length;
    await client.abortSync();
    watcher.dispose();

    expect(after - before, 0,
        reason: 'sync requests after "Check again": ${after - before}');
  });

  test('c1-1: M_USER_SUSPENDED during token renewal keeps the session active',
      () async {
    final script = Script();
    late MatrixTokenRefresher refresher;
    final client = RefreshingClient(script.transport, () => refresher);
    refresher = MatrixTokenRefresher(() => client,
        renew: (_) async => throw matrix.MatrixException.fromJson({
              'errcode': 'M_USER_SUSPENDED',
              'error': 'suspended',
            }));
    final seen = <matrix.MatrixError>[];
    final sub = refresher.onRestriction.listen(seen.add);

    expect(await refresher.refresh(), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(refresher.state.value, TokenRefreshState.active);
    expect(seen, [matrix.MatrixError.M_USER_SUSPENDED]);
    await sub.cancel();
  });

  // Review c1-3: Matrix v1.12 suspended accounts keep syncing and receive
  // 403 M_USER_SUSPENDED on forbidden actions (sending, joining, profile).
  test(
      'c1-3: 403 M_USER_SUSPENDED on a forbidden action reports suspended '
      'through MatrixClient without stopping sync', () async {
    final script = Script();
    script.routes.add((r) {
      if (r.path.endsWith('/sync')) {
        return json({'next_batch': 's${script.seen.length}'});
      }
      if (r.method == 'PUT' && r.path.contains('/displayname')) {
        return matrixError('M_USER_SUSPENDED', status: 403);
      }
      if (r.method == 'POST' && r.path.contains('/join/')) {
        return matrixError('M_FORBIDDEN', status: 403);
      }
      return null;
    });
    final client = await fakeAccount(
        'suspended_account', ScriptedAccountTransport(script));
    final mx = client.getMatrixClient();
    mx.syncErrorTimeoutSec = 0;
    final component = client.getComponent<MatrixAccountRestrictionComponent>()!;

    // A regular 403 M_FORBIDDEN must not raise the suspension banner.
    await expectLater(
      mx.joinRoom('!forbidden:example.org'),
      throwsA(isA<matrix.MatrixException>()
          .having((e) => e.error, 'error', matrix.MatrixError.M_FORBIDDEN)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(component.watcher.restriction.value, isNull);

    // A forbidden action returning 403 M_USER_SUSPENDED raises the banner
    // while keeping sync running (user can still read).
    mx.backgroundSync = true;
    await expectLater(
      mx.setProfileField(
          mx.userID!, 'displayname', {'displayname': 'Blocked edit'}),
      throwsA(isA<matrix.MatrixException>().having(
          (e) => e.error, 'error', matrix.MatrixError.M_USER_SUSPENDED)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(component.watcher.restriction.value, AccountRestriction.suspended);

    final before = script.where('GET', '/sync').length;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final after = script.where('GET', '/sync').length;
    await mx.abortSync();

    // Sync kept running and completing syncs did not erase the banner.
    expect(after - before, greaterThan(1));
    expect(component.watcher.restriction.value, AccountRestriction.suspended);

    await client.close();
  });

  test(
      'c1-3: 403 M_USER_SUSPENDED returned after a soft-logout retry is still '
      'reported', () async {
    var attempts = 0;
    final script = Script();
    script.routes.add((r) {
      if (r.method == 'PUT' && r.path.contains('/displayname')) {
        attempts++;
        return attempts == 1
            ? json({
                'errcode': 'M_UNKNOWN_TOKEN',
                'error': 'expired',
                'soft_logout': true,
              }, status: 401)
            : matrixError('M_USER_SUSPENDED', status: 403);
      }
      return null;
    });
    late MatrixTokenRefresher refresher;
    late RefreshingClient client;
    refresher = MatrixTokenRefresher(() => client, renew: (_) async {
      client.accessToken = 'fresh-token';
    });
    final httpClient = TokenRefreshingHttpClient(
      inner: script.transport,
      refresher: refresher,
      homeserver: () => client.homeserver,
    );
    client = RefreshingClient(httpClient, () => refresher);
    final watcher = AccountRestrictionWatcher(
      syncStatus: client.onSyncStatus.stream,
      setBackgroundSync: (on) => client.backgroundSync = on,
      restrictionErrors: refresher.onRestriction,
      canResume: () => refresher.state.value == TokenRefreshState.active,
    );

    await expectLater(
      client.setProfileField(
          self, 'displayname', {'displayname': 'After refresh'}),
      throwsA(isA<matrix.MatrixException>().having(
          (e) => e.error, 'error', matrix.MatrixError.M_USER_SUSPENDED)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(attempts, 2);
    expect(watcher.restriction.value, AccountRestriction.suspended);
    watcher.dispose();
  });

  for (final locale in ['en', 'pt']) {
    testWidgets('the banner explains it in $locale and checks again',
        (tester) async {
      await tester.runAsync(() => initializeMessages(locale));
      intl.Intl.defaultLocale = locale;
      addTearDown(() => intl.Intl.defaultLocale = null);
      final h = Harness();
      await tester.pumpWidget(host(
          AccountRestrictionBanner(h.watcher, account: '@me:example.org')));
      expect(find.byKey(AccountRestrictionBanner.checkAgainKey), findsNothing);

      h.status.add(syncError('M_USER_LOCKED'));
      await tester.pump();
      final title = locale == 'pt'
          ? 'Sua conta está bloqueada'
          : 'Your account is locked';
      expect(find.text(title), findsOneWidget);
      expect(find.textContaining('@me:example.org'), findsOneWidget);

      await tester.tap(find.byKey(AccountRestrictionBanner.checkAgainKey));
      expect(h.syncSwitch, [false, true]);

      h.errors.add(matrix.MatrixError.M_USER_SUSPENDED);
      await tester.pump();
      expect(
          find.text(locale == 'pt'
              ? 'Sua conta está suspensa'
              : 'Your account is suspended'),
          findsOneWidget);
      expect(h.syncSwitch, [false, true]);

      await tester.tap(find.byKey(AccountRestrictionBanner.checkAgainKey));
      await tester.pump();
      expect(find.byKey(AccountRestrictionBanner.checkAgainKey), findsNothing);
    });
  }
}
