// Criterion 3: M_USER_LOCKED and M_USER_SUSPENDED show a translated banner,
// stop the sync loop of that account (not a soft logout, nothing deleted)
// and try again with a growing wait.
@TestOn('vm')
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/social_admin/matrix_account_restriction.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/ui/pages/settings/categories/account/account_state/account_restriction_banner.dart';

import '../matrix_phase0/test_helpers.dart';
import '../matrix_room_directory/fakes.dart';

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
  Harness() {
    watcher = AccountRestrictionWatcher(
        syncStatus: status.stream, setBackgroundSync: syncSwitch.add);
  }
  final status = StreamController<matrix.SyncStatusUpdate>.broadcast();
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

void main() {
  setUpAll(prepareTests);

  for (final (errcode, kind) in [
    ('M_USER_LOCKED', AccountRestriction.locked),
    ('M_USER_SUSPENDED', AccountRestriction.suspended),
  ]) {
    test('$errcode stops the sync and retries after 1, 2, 4 minutes', () {
      fakeAsync((time) {
        final h = Harness();
        h.status.add(syncError(errcode));
        time.flushMicrotasks();
        expect(h.watcher.restriction.value, kind);
        expect(h.syncSwitch, [false]);

        // The loop already queued one more request: it fails again, and no
        // other attempt is planned for it.
        h.status.add(syncError(errcode));
        time.elapse(const Duration(seconds: 59));
        expect(h.syncSwitch, [false, false]);
        time.elapse(const Duration(seconds: 1));
        expect(h.syncSwitch, [false, false, true]);

        h.status.add(syncError(errcode));
        time.elapse(const Duration(seconds: 119));
        expect(h.syncSwitch.last, isFalse);
        time.elapse(const Duration(seconds: 1));
        expect(h.syncSwitch.last, isTrue);

        h.status.add(syncError(errcode));
        time.elapse(const Duration(minutes: 4));
        expect(h.syncSwitch.where((on) => on), hasLength(3));
      });
    });
  }

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

      h.status.add(syncError('M_USER_SUSPENDED'));
      await tester.pump();
      expect(
          find.text(locale == 'pt'
              ? 'Sua conta está suspensa'
              : 'Your account is suspended'),
          findsOneWidget);

      await tester.tap(find.byKey(AccountRestrictionBanner.checkAgainKey));
      expect(h.syncSwitch, [false, false, true]);
    });
  }
}
