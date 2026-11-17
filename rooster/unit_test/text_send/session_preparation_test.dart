@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/account_switch_prefix/account_switch_prefix.dart';
import 'package:rooster/client/components/typing_indicators/typing_indicator_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/ui/molecules/message_input.dart';
import 'package:rooster/utils/clipboard/pasted_file.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import '../media_prepare/fakes.dart';
import '../pending_media/chat_harness.dart';
import '../speed_log/fake_account.dart';
import 'text_send_fakes.dart';

/// R7: an encrypted room's outbound session is prepared on the first input
/// into an empty composer and when a file is attached, never on focus, one
/// preparation in flight per room, and only while typing notices are on
/// (the owner's decision of 2026-11-17: off, nothing is readied before
/// Send, since the key sent ahead tells others as much). The
/// preparation is [MatrixRoom.prepareOutboundSession], replaced here by a
/// counter, so these tests need no vodozemac.
void main() {
  late PreparationSpy spy;
  final appPreparer = ImagePreparer.instance;
  var accounts = 0;

  setUp(() {
    sent.clear();
    spy = PreparationSpy();
  });

  tearDown(() {
    spy.restore();
    ImagePreparer.instance = appPreparer;
    AttachmentSends.instance.clear();
  });

  /// A chat on a real [MatrixRoom] (encrypted when [encrypted]), made in
  /// [tester.runAsync]: a client made in the fake zone hangs its close.
  Future<(MatrixClient, PreparingRoom)> openChat(WidgetTester tester,
      {required bool encrypted, TypingIndicatorComponent? typing}) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
    final (client, room) = (await tester.runAsync(() async {
      final client = await fakeAccount(
          'session_preparation_${accounts++}', FakeTransport());
      final mx = client.getMatrixClient();
      mx.backgroundSync = false;
      await mx.oneShotSync();
      return (client, await joinedRoom(client, encrypted: encrypted));
    }))!;
    final preparer = fakePreparer(FakeEngine(width: 400, height: 300));
    ImagePreparer.instance = preparer;
    final chatRoom = PreparingRoom(FakeClient('a'), fakeRoomId,
        preparer: preparer, target: room, typing: typing);
    await tester.pumpWidget(chatApp(chatRoom));
    await tester.pump();
    return (client, chatRoom);
  }

  Future<void> close(WidgetTester tester, MatrixClient client) async {
    // The composer clears its keyboard override 1 s after it gains focus,
    // and does not cancel that when disposed.
    await tester.pump(const Duration(seconds: 2));
    await closeChat(tester);
    await tester.runAsync(client.close);
  }

  Finder composer() => find.byType(EditableText).first;

  /// A file the composer attaches as it would a picked, pasted or dropped
  /// one.
  Future<void> attachFile(WidgetTester tester) async {
    chatState(tester).addAttachment(PendingFileAttachment(
        name: 'notes.pdf', data: Uint8List(10), mimeType: 'application/pdf'));
    await tester.pump();
  }

  testWidgets(
      'opening the room and focusing the composer, without typing, prepares '
      'nothing', (tester) async {
    final (client, _) = await openChat(tester, encrypted: true);

    await tester.showKeyboard(composer());
    await tester.tap(composer());
    await tester.pump(const Duration(seconds: 1));

    expect(tester.widget<EditableText>(composer()).focusNode.hasFocus, isTrue);
    expect(spy.count, 0);
    await close(tester, client);
  });

  testWidgets(
      'the first keystroke into an empty composer prepares the session; ten '
      'more keystrokes and a file, the first still running, prepare nothing '
      'more', (tester) async {
    final (client, _) = await openChat(tester, encrypted: true);
    await tester.showKeyboard(composer());

    await tester.enterText(composer(), 'h');
    await tester.pump();
    expect(spy.rooms, [fakeRoomId]);

    var text = 'h';
    for (final letter in 'ello there'.split('')) {
      text += letter;
      await tester.enterText(composer(), text);
      await tester.pump();
    }
    await attachFile(tester);
    expect(spy.count, 1, reason: 'one preparation in flight per room');

    // Once it ended, the next draft prepares again (a send clears the
    // composer without a keystroke).
    spy.finish();
    await tester.pump();
    chatState(tester).removeAttachment(chatState(tester).attachments.single);
    await typeAndSend(tester, 'hello there');
    expect(sent.single.message, 'hello there');
    expect(spy.count, 1, reason: 'Send prepares nothing itself');
    await tester.enterText(composer(), 'a');
    await tester.pump();
    expect(spy.count, 2);
    spy.finish();
    await tester.pump();
    await close(tester, client);
  });

  testWidgets('attaching a file to an empty composer prepares the session',
      (tester) async {
    final (client, _) = await openChat(tester, encrypted: true);

    await attachFile(tester);
    expect(spy.count, 1);
    // Typing into the composer while it runs adds none.
    await tester.enterText(composer(), 'here');
    await tester.pump();
    expect(spy.count, 1);
    spy.finish();
    await tester.pump();
    await close(tester, client);
  });

  for (final on in [false, true]) {
    testWidgets(
        'typing notices ${on ? 'on' : 'off'}: typing, a paste and a file '
        "${on ? 'ready' : 'never ready'} the session before Send",
        (tester) async {
      final (client, _) = await openChat(tester, encrypted: true);
      await tester.runAsync(() => setTypingNotices(client, on));
      await tester.showKeyboard(composer());

      await tester.enterText(composer(), 'h');
      await tester.pump();
      final afterTyping = spy.count;
      if (on) spy.finish();
      await tester.pump();

      // A paste: the composer's attachment dialog, then the file.
      final input = tester.state<MessageInputState>(find.byType(MessageInput));
      final pasted = input.onFilesPasted([
        PastedFile(Uint8List(10),
            name: 'notes.pdf', mimeType: 'application/pdf')
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Add File'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await pasted;
      final afterPaste = spy.count;
      if (on) spy.finish();
      await tester.pump();

      await attachFile(tester);
      final afterFile = spy.count;
      if (on) spy.finish();
      await tester.pump();

      print('typing notices ${on ? 'on' : 'off'}: preparations after typing '
          '$afterTyping, after the paste $afterPaste, after the file '
          '$afterFile');
      expect(chatState(tester).attachments, hasLength(2));
      expect([afterTyping, afterPaste, afterFile], on ? [1, 2, 3] : [0, 0, 0]);
      await close(tester, client);
    });
  }

  testWidgets('in a room without encryption, never', (tester) async {
    final (plain, _) = await openChat(tester, encrypted: false);
    await tester.enterText(composer(), 'h');
    await tester.pump();
    await attachFile(tester);
    expect(spy.count, 0);
    await close(tester, plain);
  });

  testWidgets(
      'a prefix that sends as another account readies the room of that '
      "account, not the chat's", (tester) async {
    final (clientA, chatRoom) = await openChat(tester, encrypted: true);
    final clientB = (await tester.runAsync(() async {
      final client = await fakeAccount(
          'session_preparation_other_${accounts++}', FakeTransport());
      final mx = client.getMatrixClient();
      mx.backgroundSync = false;
      await mx.oneShotSync();
      await joinedRoom(client, encrypted: true);
      return client;
    }))!;
    chatRoom.client.components[AccountSwitchPrefix] = _Prefix('+b ', clientB);
    await tester.showKeyboard(composer());

    for (final text in ['+', '+b', '+b ', '+b hello']) {
      await tester.enterText(composer(), text);
      await tester.pump();
    }

    print("prepared for: ${spy.accounts}; the chat's account "
        '${clientA.getMatrixClient().clientName}, the sender '
        '${clientB.getMatrixClient().clientName}');
    expect(spy.accounts, [clientB.getMatrixClient().clientName]);
    spy.finish();
    await tester.pump();
    await close(tester, clientA);
    await tester.runAsync(clientB.close);
  });

  testWidgets(
      "a first keystroke that only looks like a prefix readies the chat's "
      'room once it is plain text', (tester) async {
    final (clientA, chatRoom) = await openChat(tester, encrypted: true);
    chatRoom.client.components[AccountSwitchPrefix] = _Prefix('+b ', null);
    await tester.showKeyboard(composer());

    await tester.enterText(composer(), '+');
    await tester.pump();
    expect(spy.count, 0, reason: 'who sends is not known yet');
    await tester.enterText(composer(), '+1');
    await tester.pump();

    expect(spy.accounts, [clientA.getMatrixClient().clientName]);
    spy.finish();
    await tester.pump();
    await close(tester, clientA);
  });

  group('MatrixRoom.prepareToSend', () {
    late MatrixClient client;

    setUp(() async {
      client = await fakeAccount(
          'session_preparation_room_${accounts++}', FakeTransport());
      client.getMatrixClient().backgroundSync = false;
      await client.getMatrixClient().oneShotSync();
    });

    tearDown(() => client.close());

    test('joins the preparation in flight, then starts a new one', () async {
      final room = await joinedRoom(client, encrypted: true);
      for (var i = 0; i < 11; i++) {
        room.prepareToSend();
      }
      await Future<void>.delayed(Duration.zero);
      expect(spy.count, 1);

      spy.finish();
      await Future<void>.delayed(Duration.zero);
      room.prepareToSend();
      await Future<void>.delayed(Duration.zero);
      expect(spy.count, 2);
      spy.finish();
    });

    test('a failed preparation is dropped, and the next one runs', () async {
      final room = await joinedRoom(client, encrypted: true);
      room.prepareToSend();
      await Future<void>.delayed(Duration.zero);
      spy.finish(StateError('no keys'));
      await Future<void>.delayed(Duration.zero);

      room.prepareToSend();
      await Future<void>.delayed(Duration.zero);
      expect(spy.count, 2);
      spy.finish();
    });

    test('a room without encryption prepares nothing', () async {
      final room = await joinedRoom(client, encrypted: false);
      room.prepareToSend();
      await Future<void>.delayed(Duration.zero);
      expect(spy.count, 0);
    });

    test(
        "the app's preparation, without vodozemac, does nothing and does not "
        'fail', () async {
      spy.restore();
      final room = await joinedRoom(client, encrypted: true);
      expect(client.getMatrixClient().encryptionEnabled, isFalse);
      await MatrixRoom.prepareOutboundSession(room.matrixRoom);
      room.prepareToSend();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
  });
}

/// The account prefix [prefix]: text that starts with it is sent as
/// [other] (a fake that knows no other account when null).
class _Prefix implements AccountSwitchPrefix<Client> {
  _Prefix(this.prefix, this.other);

  final String prefix;
  final Client? other;

  @override
  (Client, String)? getPrefixedAccount(String string, Room currentRoom) =>
      other != null && string.startsWith(prefix) ? (other!, prefix) : null;

  @override
  bool isPossiblyUsingPrefix(String currentText) =>
      currentText.startsWith(prefix) || prefix.startsWith(currentText);

  @override
  String? get clientPrefix => prefix;

  @override
  String removePrefix(String string, Room currentRoom) =>
      string.startsWith(prefix) ? string.substring(prefix.length) : string;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
