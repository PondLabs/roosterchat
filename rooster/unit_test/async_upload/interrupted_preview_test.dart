// The failed message left for a photo the app's closing cut short is the
// room's last message: the room list's panel and the quick switcher show
// it in the app's language, never its stored English body.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/media/interrupted_photo_uploads.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/ui/atoms/room_panel.dart';
import 'package:rooster/ui/navigation/quick_switcher.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import '../speed_log/fake_account.dart';
import 'async_fakes.dart';

const _stored = "A photo didn't finish uploading before Rooster closed";

void main() {
  for (final (locale, said) in const [
    (
      'en',
      "A photo didn't finish uploading before Rooster closed. The others "
          "won't see it"
    ),
    (
      'pt',
      'Uma foto não terminou de subir antes de o Rooster fechar. Os outros '
          'não vão vê-la'
    ),
  ]) {
    testWidgets(
        'the room list and the quick switcher say it in the app\'s language '
        '($locale)', (tester) async {
      late MatrixClient client;
      late MatrixRoom room;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
      await tester.runAsync(() async {
        await initializeMessages(locale);
        client =
            await fakeAccount('interrupted_preview_$locale', AsyncTransport());
        client.getMatrixClient().backgroundSync = false;
        room = await plainRoom(client);
        await room.matrixRoom.showFailedMessage('interrupted', {
          'msgtype': 'm.notice',
          'body': _stored,
          interruptedPhotoKey: r'$photo',
        });
        await until(() => room.lastMessage?.eventId == 'interrupted');
      });
      intl.Intl.defaultLocale = locale;
      addTearDown(() => intl.Intl.defaultLocale = null);

      expect(room.lastMessage!.plainTextBody, said);

      await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: Column(children: [
              RoomPanel(room),
              Builder(
                  builder: (context) =>
                      QuickSwitcherSearchItemRoom(room, id: 'room')
                          .build(context)),
            ]),
          ),
        ),
      ));
      await tester.pump();
      expect(find.textContaining(said, findRichText: true), findsNWidgets(2));
      // In English the stored body is the start of the sentence; in
      // Portuguese nothing of it shows.
      if (locale == 'pt') {
        expect(find.textContaining('Rooster closed', findRichText: true),
            findsNothing);
      }

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      await tester.runAsync(() => client.close());
    });
  }
}
