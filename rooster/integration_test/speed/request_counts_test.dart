// Requests per route of three operations a person waits on, read from the
// app's speed log (docs/speed-log.md) against the CI's Synapse and LiveKit:
// sending a text, sending a photo, joining a voice call. Each number is one
// a task of the network speed work pinned in a unit test against a fake
// server; the task is named beside it. Here the same numbers are held
// against a real homeserver, so a regression names its route.
//
// The sends go through the seams the composer calls (TextSendTrace.send
// around the room's sendMessage; sendMatrixAttachment with an
// AttachmentSend and its file_send span), the join through the voice
// channel's page and its Join button.
//
// Only the routes those tasks fixed are asserted. Every other route a
// scenario made (a sync, a membership write) is printed, not asserted: no
// unit test fixes it.
//
// Without the homeserver (HOMESERVER) each test skips with a reason, and
// the call test also without LiveKit (LIVEKIT_URL), so a checkout without
// Docker keeps its integration runs green.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/user_presence/user_presence_component.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/media/async_photo_send.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';
import 'package:rooster/diagnostic/speed_log/file_send_trace.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/diagnostic/speed_log/text_send_trace.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/organisms/call_view/call_view.dart';
import 'package:rooster/ui/organisms/voip_room_view/voip_room_view.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:rooster/utils/rng.dart';

import '../extensions/common_flows.dart';
import '../extensions/request_counts.dart';
import '../extensions/wait_for.dart';

const _textRoutes = [sendEvent, keysQuery, keysClaim, sendToDevice];
const _photoRoutes = [reserveMxc, sendEvent, uploadToMxc, uploadMedia];
const _tokenRoutes = [openIdToken, sfuGet, healthz];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('speed log: requests per route of a text send', (tester) async {
    if (await _skipped(tester)) return;
    final app = await _signIn(tester);
    final client = app.clientManager.clients.first;

    // T6.13 (acceptance 14, the owner's decision): with typing notices off
    // nothing readies an encrypted room's session before Send. The setting
    // is the account's, on the server: put back for the tests that follow.
    final presence = client.getComponent<UserPresenceComponent>()!;
    await presence.setTypingIndicatorEnabled(false);
    addTearDown(() => presence.setTypingIndicatorEnabled(true));
    await tester.waitFor(() => !presence.typingIndicatorEnabled,
        skipPumpAndSettle: true, timeout: const Duration(seconds: 30));

    final room = await client.createRoom(CreateRoomArgs(
      name: 'Speed text ${RandomUtils.getRandomString(8)}',
      visibility: RoomVisibilityPrivate(),
      enableE2EE: true,
    )) as MatrixRoom;
    await tester.waitFor(() => room.matrixRoom.encrypted,
        skipPumpAndSettle: true, timeout: const Duration(seconds: 30));

    // What the composer calls on the first keystroke, a paste or a file:
    // no one-time key claimed and no room key sent (T6.13, acceptance 14).
    // keys/query is left out: the sync loop asks it on its own.
    final typed = SpeedLog.instance.now();
    room.prepareToSend();
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(_outboundSession(room), isNull, reason: 'nothing readied');
    expect(countRoutes(requestsSince(typed), [keysClaim, sendToDevice]),
        {label(keysClaim): 0, label(sendToDevice): 0});

    // The first text makes the session at Send (T4.1, acceptance 7; T6.13,
    // acceptance 14): one PUT /send, and its key requests are the ones the
    // span counts. How many depends on how many devices alice has on the
    // CI's Synapse (each earlier login left one), so it is not fixed.
    final first = await _sendText(room, 'Speed log, first text');
    final firstRoutes = countRoutes(requestsOf(first), _textRoutes);
    _print('text, no session yet', first, firstRoutes);
    expect(first.outcome, SpeedOutcome.ok);
    expect(firstRoutes[label(sendEvent)], 1);
    final keyRequests = requestsOf(first).where(TextSendTrace.isKeyRequest);
    expect(_session(first), {
      SpeedValue.sessionCreated: 1,
      SpeedValue.sessionWaited: 0,
      SpeedValue.keyRequests: keyRequests.length,
    });

    // The second finds the session ready (T4.1, acceptance 7; T2.3: Send
    // sends the text at once): one PUT /send, no key request.
    final second = await _sendText(room, 'Speed log, second text');
    final secondRoutes = countRoutes(requestsOf(second), _textRoutes);
    _print('text, session ready', second, secondRoutes);
    expect(second.outcome, SpeedOutcome.ok);
    expect(secondRoutes, {
      label(sendEvent): 1,
      label(keysQuery): 0,
      label(keysClaim): 0,
      label(sendToDevice): 0,
    });
    expect(_session(second), {
      SpeedValue.sessionCreated: 0,
      SpeedValue.sessionWaited: 0,
      SpeedValue.keyRequests: 0,
    });
  });

  testWidgets('speed log: requests per route of a photo send', (tester) async {
    if (await _skipped(tester)) return;
    final app = await _signIn(tester);
    final client = app.clientManager.clients.first;

    // A room without encryption: the photo's counts do not depend on the
    // room's session (a new login has none), and T5.2's order is the same
    // in both kinds of room.
    final room = await client.createRoom(CreateRoomArgs(
      name: 'Speed photo ${RandomUtils.getRandomString(8)}',
      visibility: RoomVisibilityPrivate(),
      enableE2EE: false,
    )) as MatrixRoom;

    final photo = _photo(room);
    expect(sendsByAsyncUpload(photo), isTrue);
    final id = await sendMatrixAttachment(room.matrixRoom, photo);
    expect(id, isNotNull);
    final span = photo.send.trace!.span;
    await tester.waitFor(() => span.isFinished,
        skipPumpAndSettle: true, timeout: const Duration(seconds: 60));
    final routes = countRoutes(requestsOf(span), _photoRoutes);
    _print('photo', span, routes);
    expect(span.outcome, SpeedOutcome.ok);

    // Synapse serves MSC2246's POST /_matrix/media/v1/create (stable since
    // Matrix 1.7), so the CI's matrixdotorg/synapse:latest is expected to
    // reserve both mxcs. That cannot be confirmed without running it, so a
    // refused reservation is accepted too, with that path's own counts.
    // On either path, one PUT /send for the photo (T2.4, acceptance 7) and
    // nothing sent again: an upload the server answers at once goes once
    // (T2.6, acceptance 1). Each path checks the attempt numbers by route.
    final photoRequests = [
      for (final r in requestsOf(span))
        if (_photoRoutes.any((route) => goesTo(r, route))) r
    ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final attempts = attemptsByRoute(photoRequests, _photoRoutes);

    final steps = span.steps.map((s) => s.name).toSet();
    if (steps.contains(SpeedStep.asyncUpload)) {
      // T5.2 (acceptance 1): two reservations, one after the other, then
      // the event, then the thumbnail and the file to their reserved mxcs;
      // no POST /upload.
      expect(routes, {
        label(reserveMxc): 2,
        label(sendEvent): 1,
        label(uploadToMxc): 2,
        label(uploadMedia): 0,
      });
      expect(
          photoRequests.take(3).map((r) => r.method), ['POST', 'POST', 'PUT']);
      expect(goesTo(photoRequests[2], sendEvent), isTrue,
          reason: 'the event third, before any upload');
      // The two reservations are two requests, but the same one on the
      // wire (POST /media/v1/create, same URL, no body), and the speed
      // log's attempt rule (docs/speed-log.md, "Attempts") cannot tell them
      // apart: the second reads attempt 2. Everything else is attempt 1:
      // the uploads go to different mxcs.
      expect(attempts, {
        label(reserveMxc): [1, 2],
        label(sendEvent): [1],
        label(uploadToMxc): [1, 1],
        label(uploadMedia): <int>[],
      });
    } else {
      // T5.2 (acceptance 4): a refused reservation sends the photo upload
      // first: one reservation asked for (none once the homeserver said it
      // has no such endpoint) and refused, the thumbnail and the file by
      // POST /upload, then the event.
      expect(steps, contains(SpeedStep.uploadFirst));
      expect(routes[label(reserveMxc)], lessThanOrEqualTo(1));
      expect(
          requestsOf(span).where((r) => goesTo(r, reserveMxc)).map(
                (r) => r.status,
              ),
          everyElement(isNot(200)));
      expect({...routes}..remove(label(reserveMxc)), {
        label(sendEvent): 1,
        label(uploadToMxc): 0,
        label(uploadMedia): 2,
      });
      // Every request attempt 1: at most one reservation, and the two
      // POST /upload differ in their body's length (thumbnail and file).
      expect(attempts.values.expand((a) => a), everyElement(1));
    }
  });

  testWidgets(
      'speed log: requests per route of opening a voice channel '
      'and joining its call', (tester) async {
    if (await _skipped(tester, livekit: true)) return;
    final app = await _signIn(tester, keepCleanUp: true);
    final client = app.clientManager.clients.first;
    // The call goes down before the app's own shutdown, as in the Sunny
    // Side Putt e2e: a process that ends with the WebRTC stack up fails.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
      await app.clientManager.callManager
          .disconnect()
          .timeout(const Duration(seconds: 20))
          .catchError((Object _) {});
      await app.clientManager.close();
      await tester.clean();
    });

    final channel = await client.createRoom(CreateRoomArgs(
      name: 'Speed call ${RandomUtils.getRandomString(8)}',
      roomType: RoomType.voipRoom,
      visibility: RoomVisibilityPublic(),
      enableE2EE: false,
    ));

    // Opening the channel's page fetches what a join needs (T3.3,
    // acceptance 1; T6.11, acceptance 3): one OpenID token, one /sfu/get
    // and one GET /healthz to the call token service the well-known names.
    // The channel is new, so no membership names another service.
    final opened = SpeedLog.instance.now();
    EventBus.doOpenRoom(channel.identifier, clientId: client.identifier);
    await tester.waitFor(() => find.byType(VoipRoomView).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30));
    await tester.waitFor(
        () => countRoutes(requestsSince(opened), _tokenRoutes)
            .values
            .every((n) => n >= 1),
        timeout: const Duration(seconds: 30));
    // Time for a second request of any of them to show, were there one.
    await Future<void>.delayed(const Duration(seconds: 2));
    final warmUp = countRoutes(requestsSince(opened), _tokenRoutes);
    // ignore: avoid_print
    print('speed log, opening the channel: $warmUp; every route: '
        '${allRoutes(requestsSince(opened))}');
    expect(
        warmUp, {label(openIdToken): 1, label(sfuGet): 1, label(healthz): 1});

    // The join asks for no token: it uses the ones held (T3.3, acceptance
    // 1), and asks again only when the SFU refuses a held one (T6.11,
    // acceptance 4), which the CI's LiveKit, handed a fresh one, does not.
    final clicked = SpeedLog.instance.now();
    final join = find.widgetWithText(tiamat.Button, CommonStrings.promptJoin);
    await tester.waitFor(() => join.evaluate().isNotEmpty);
    await tester.tap(join.first);
    final joinError = find.text(VoipRoomView.errorCallJoinFailed);
    await tester.waitFor(
        () =>
            find.byType(CallView).evaluate().isNotEmpty ||
            joinError.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60));
    expect(joinError, findsNothing, reason: 'the join failed');

    // The voice_join span ends once the microphone and the first remote
    // audio are settled; alone in the call, the latter after 30 s.
    final joins = <SpeedSpan>[];
    await tester.waitFor(() {
      joins
        ..clear()
        ..addAll(SpeedLog.instance.spans.toList().where((span) =>
            span.name == SpeedOperation.voiceJoin && span.startedAt >= opened));
      return joins.isNotEmpty;
    }, timeout: const Duration(seconds: 60));
    expect(joins, hasLength(1), reason: 'one join');
    final span = joins.single;
    _print('call join', span, countRoutes(requestsOf(span), _tokenRoutes));
    expect(span.outcome, SpeedOutcome.ok);
    expect(countRoutes(requestsSince(clicked), _tokenRoutes),
        {label(openIdToken): 0, label(sfuGet): 0, label(healthz): 0});
  });
}

/// True, with the reason printed, when the integration stack is not up.
Future<bool> _skipped(WidgetTester tester, {bool livekit = false}) async {
  final reason =
      await integrationStackSkipReason(tester.homeserver, livekit: livekit);
  // ignore: avoid_print
  if (reason != null) print(reason);
  return reason != null;
}

/// The app on screen with alice signed in, taken down when the test ends
/// unless [keepCleanUp] (the test registers its own).
Future<App> _signIn(WidgetTester tester, {bool keepCleanUp = false}) async {
  await tester.clearUserData();
  final app = await tester.setupApp();
  if (!keepCleanUp) {
    addTearDown(() async {
      await app.clientManager.close();
      await tester.clean();
    });
  }
  await tester.pumpWidget(app);
  await tester.login(app);
  await tester.pumpAndSettle();
  return app;
}

/// Sends [text] the way the composer does, and returns its span once
/// finished.
Future<SpeedSpan> _sendText(MatrixRoom room, String text) async {
  final trace = TextSendTrace.forComposer(
      sendPressed: TextSendTrace.now(), message: text, hasAttachments: false)!;
  await TextSendTrace.send(trace, () => room.sendMessage(message: text));
  return trace.span;
}

Object? _outboundSession(MatrixRoom room) =>
    room.matrixRoom.client.encryption?.keyManager
        .getOutboundGroupSession(room.matrixRoom.id);

Map<String, num> _session(SpeedSpan span) =>
    span.steps.singleWhere((s) => s.name == SpeedStep.outboundSession).values;

/// A 640 x 480 JPEG photo and its 160 x 120 thumbnail, held in memory, with
/// the [AttachmentSend] and file_send span the composer gives one.
TrackedMatrixAttachment _photo(MatrixRoom room) {
  List<int> jpeg(int width, int height) =>
      img.encodeJpg(img.fill(img.Image(width: width, height: height),
          color: img.ColorRgb8(230, 160, 40)));
  final send = AttachmentSend(
    roomKey: room.localId,
    attachment: null,
    trace: FileSendTrace.start(sendPressed: FileSendTrace.now()),
  );
  AttachmentSends.instance.add(send);
  return TrackedMatrixAttachment(
    matrix.MatrixImageFile(
        bytes: Uint8List.fromList(jpeg(640, 480)),
        name: 'speed.jpg',
        mimeType: 'image/jpeg',
        width: 640,
        height: 480),
    send,
    thumbnailFile: matrix.MatrixImageFile(
        bytes: Uint8List.fromList(jpeg(160, 120)),
        name: 'thumbnail.jpg',
        mimeType: 'image/jpeg',
        width: 160,
        height: 120),
  );
}

void _print(String scenario, SpeedSpan span, Map<String, int> asserted) {
  // ignore: avoid_print
  print('speed log, $scenario: ${span.name} outcome=${span.outcome}, '
      'asserted routes $asserted; every route of the span: '
      '${allRoutes(requestsOf(span))}');
}
