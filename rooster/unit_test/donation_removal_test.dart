import 'dart:convert';

import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/config/preferences.dart';
import 'package:rooster/ui/organisms/user_profile/user_profile_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

void main() {
  test('initialization clears the retired donation-flow preference', () async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'running_donation_check_flow':
          '{"user":"@alice:example.org","time":1700000000000}',
    });

    final preferences = Preferences();
    await preferences.init();

    final storage = await SharedPreferences.getInstance();
    expect(storage.containsKey('running_donation_check_flow'), isFalse);
  });

  testWidgets('an existing profile badge still renders', (tester) async {
    final image = MemoryImage(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
        '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    final badge = ProfileBadge(
      image,
      body: 'Existing badge',
      id: 'supporter',
      sender: '@awards:data.commet.chat',
      source: const {
        'signed': {'id': 'supporter'},
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
        home: Scaffold(
          body: UserProfileView(
            displayName: 'Alice',
            identifier: '@alice:example.org',
            userColor: Colors.blue,
            isSelf: false,
            showMessageButton: false,
            doSafeArea: false,
            badges: [badge],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image == image,
      ),
      findsOneWidget,
    );
  });

  Future<void> pumpCard(WidgetTester tester, UserProfileView card) {
    return tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
        home: Scaffold(body: SingleChildScrollView(child: card)),
      ),
    );
  }

  testWidgets('your own card has an edit button and no menu', (tester) async {
    await pumpCard(
      tester,
      UserProfileView(
        displayName: 'Alice',
        identifier: '@alice:example.org',
        userColor: Colors.blue,
        isSelf: true,
        doSafeArea: false,
        setPetName: (_) async {},
        setColorOverride: (_) async {},
        onEditProfile: () async {},
      ),
    );

    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('someone else\'s card has a menu, a preview has nothing',
      (tester) async {
    UserProfileView card({required bool preview}) => UserProfileView(
          displayName: 'Bob',
          identifier: '@bob:example.org',
          userColor: Colors.blue,
          isSelf: false,
          doSafeArea: false,
          preview: preview,
          setPetName: (_) async {},
          setColorOverride: (_) async {},
          onMessageButtonClicked: () async {},
        );

    await pumpCard(tester, card(preview: false));
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);

    await pumpCard(tester, card(preview: true));
    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(find.text('Message'), findsNothing);
    expect(find.byIcon(Icons.copy), findsNothing);
  });
}
