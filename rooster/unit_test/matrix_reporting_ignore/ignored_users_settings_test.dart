// Criterion 2, in Settings > Account > Preferences: the ignore list is
// listed, someone is ignored by Matrix ID and unignored with a button, and
// our own ID is refused with a sentence.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/ui/organisms/moderation/ignore_user_actions.dart';
import 'package:rooster/ui/pages/settings/categories/account/preferences/preferences_ignored_users.dart';

import 'fakes.dart';

const bob = '@bob:example.org';
const carol = '@carol:example.org';

Future<(Script, matrix.Client)> showPanel(WidgetTester tester,
    {List<String> ignored = const []}) async {
  final script = Script();
  final mx = await tester.runAsync(() async {
    final mx = (await account(script)).matrixClient;
    if (ignored.isNotEmpty) await syncIgnoreList(mx, ignored);
    return mx;
  });
  await tester.pumpWidget(host(IgnoredUsersPreferences(client: mx!)));
  await tester.pump();
  return (script, mx);
}

Future<void> ignoreTyped(WidgetTester tester, String id) async {
  await tester.enterText(find.byKey(IgnoredUsersPreferences.idFieldKey), id);
  await tester.tap(find.byKey(IgnoredUsersPreferences.ignoreKey));
  await settle(tester);
}

void main() {
  setUpAll(prepareTests);

  testWidgets('says when nobody is ignored', (tester) async {
    await showPanel(tester);
    expect(find.text(IgnoredUsersPreferences.labelIgnoredUsersEmpty),
        findsOneWidget);
  });

  testWidgets('lists the users on the list, sorted', (tester) async {
    await showPanel(tester, ignored: [carol, bob]);
    expect(find.text(IgnoredUsersPreferences.labelIgnoredUsersEmpty),
        findsNothing);
    final bobY = tester.getTopLeft(find.text(bob)).dy;
    final carolY = tester.getTopLeft(find.text(carol)).dy;
    expect(bobY, lessThan(carolY));
  });

  testWidgets('ignores the Matrix ID typed and lists it', (tester) async {
    final (script, _) = await showPanel(tester);

    await ignoreTyped(tester, ' $bob ');

    expect(writtenUsers(ignoreListWrites(script).single), {bob: {}});
    expect(find.text(bob), findsOneWidget);
    expect(find.text(IgnoredUsersPreferences.labelIgnoredUsersEmpty),
        findsNothing);
  });

  testWidgets('stops ignoring with the button next to the user',
      (tester) async {
    final (script, _) = await showPanel(tester, ignored: [bob, carol]);

    await tester.tap(find.byKey(const ValueKey('unignore_$bob')));
    await settle(tester);

    expect(writtenUsers(ignoreListWrites(script).single), {carol: {}});
    expect(find.text(bob), findsNothing);
    expect(find.text(carol), findsOneWidget);
  });

  testWidgets('refuses our own ID with a sentence, writing nothing',
      (tester) async {
    final (script, mx) = await showPanel(tester);

    await ignoreTyped(tester, mx.userID!);

    expect(find.text(IgnoreUserActions.errorIgnoreSelf), findsOneWidget);
    expect(ignoreListWrites(script), isEmpty);
    expect(find.text(IgnoredUsersPreferences.labelIgnoredUsersEmpty),
        findsOneWidget);
  });

  testWidgets('refuses what is not a Matrix ID', (tester) async {
    final (script, _) = await showPanel(tester);

    await ignoreTyped(tester, 'bob');

    expect(find.text(IgnoreUserActions.errorIgnoreInvalidId), findsOneWidget);
    expect(ignoreListWrites(script), isEmpty);
  });

  testWidgets('shows a change made by another session', (tester) async {
    final (_, mx) = await showPanel(tester);

    await tester.runAsync(() => syncIgnoreList(mx, [carol]));
    await tester.pump();

    expect(find.text(carol), findsOneWidget);
  });
}
