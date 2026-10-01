// The room's state in Developer settings is pasted into bug reports: it
// has a copy button, and it copies the whole state.
import 'package:cockhouse/client/room.dart';
import 'package:cockhouse/ui/pages/settings/categories/room/developer/room_developer_settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

class _Room implements Room {
  @override
  String get developerInfo => '{"m.room.name": {"": {"name": "canal de voz"}}}';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('the room state has a copy button that copies all of it',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
          body:
              SingleChildScrollView(child: RoomDeveloperSettingsView(_Room()))),
    ));
    await tester.tap(find.text('Room State'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();

    expect(copied, _Room().developerInfo);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
