// The dialog the first launch after an update shows: says which version
// it is, offers the release's notes, and closes with a button that says so,
// not with the "No, thanks" Commet left from a donation request.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/ui/organisms/update_installed_dialog/update_installed_dialog.dart';
import 'package:rooster/utils/update_checker.dart';
import 'package:tiamat/config/style/theme_dark.dart';

Future<void> open(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeDark.theme,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const Dialog(child: UpdateInstalledDialog()),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('says thanks, offers what is new, and closes with Let\'s go',
      (tester) async {
    await open(tester, const Size(800, 600));

    // A test build has no release tag, so no version to name.
    expect(
        find.text(
            'Thank you for updating! You are now running the latest version.'),
        findsOneWidget);
    expect(find.text("See what's new"), findsOneWidget);
    expect(find.text('No, thanks'), findsNothing);

    await tester.tap(find.text("Let's go"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(UpdateInstalledDialog), findsNothing);
  });

  testWidgets('the buttons fit a phone, one over the other if they must',
      (tester) async {
    // Any overflow fails the test.
    await open(tester, const Size(300, 600));
    expect(find.text("Let's go"), findsOneWidget);
  });

  test('a release links to its own notes', () {
    expect(UpdateChecker.releaseNotesUrl('v1.21.0'),
        'https://github.com/PondLabs/roosterchat/releases/tag/v1.21.0');
    expect(UpdateInstalledDialog.messageUpdateInstalled('Rooster', 'v1.21.0'),
        'Rooster is now on v1.21.0. Thanks for updating!');
  });
}
