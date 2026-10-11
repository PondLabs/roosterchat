// The in-game overlay on Windows (docs/game-overlay.md): who is in the call,
// and what Dart tells the runner to show over a game.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/call_manager.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/client_manager.dart';
import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/components/push_notification/notification_content.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/components/voip/voip_stream.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/game_overlay/game_overlay.dart';
import 'package:rooster/utils/game_overlay/overlay_painter.dart';
import 'package:rooster/utils/voice_controls/call_members.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Profile implements Profile {
  _Profile(this.identifier);

  @override
  final String identifier;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements Client {
  @override
  Profile? self = _Profile("@me:example.org");

  @override
  Room? getRoom(String identifier) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Stream implements VoipStream {
  _Stream(this.streamUserId,
      {this.type = VoipStreamType.audio,
      this.audiolevel = 0,
      this.isMuted = false,
      this.isDeafened = false});

  @override
  final String streamUserId;
  @override
  final VoipStreamType type;
  @override
  final double audiolevel;
  @override
  final bool isMuted;
  @override
  final bool isDeafened;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session implements VoipSession {
  @override
  VoipState state = VoipState.connected;
  @override
  bool isMicrophoneMuted = false;
  @override
  bool isDeafened = false;
  @override
  bool isSharingScreen = false;
  @override
  List<VoipStream> streams = [];
  @override
  final Client client = _Client();
  @override
  final String roomId = "!voice:example.org";

  @override
  Future<void> updateStats() async {}

  @override
  Stream<void> get onStateChanged => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RosterSession extends _Session implements CallRoster {
  @override
  Set<String> connectedUserIds = {};
  @override
  bool rosterComplete = true;
}

/// The runner's side of the channel: says no game is in front when started,
/// and keeps what it is told.
class _Runner {
  _Runner(this.channel) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == "start") return {"inFront": false, "scale": 1.0};
      return null;
    });
  }

  final MethodChannel channel;
  final List<MethodCall> calls = [];

  Iterable<String> get methods => calls.map((c) => c.method);

  /// The panels set, as (id, corner).
  List<(int, String)> get panelsSet => [
        for (final call in calls)
          if (call.method == "setPanel")
            ((call.arguments as Map)["id"] as int,
                (call.arguments as Map)["corner"] as String),
      ];

  List<int> get panelsRemoved => [
        for (final call in calls)
          if (call.method == "removePanel")
            (call.arguments as Map)["id"] as int,
      ];

  Future<void> tell(String method, [Object? arguments]) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
              channel.name,
              channel.codec.encodeMethodCall(MethodCall(method, arguments)),
              (_) {});

  Future<void> gameInFront({double scale = 1}) =>
      tell("onGameChanged", {"inFront": true, "scale": scale});

  Future<void> gameGone() =>
      tell("onGameChanged", {"inFront": false, "scale": 1.0});
}

final _blank = OverlayImage(1, 1, Uint8List(4));

MessageNotificationContent _message(
        {String body = "gg", String sender = "Ana"}) =>
    MessageNotificationContent(
      senderName: sender,
      senderId: "@${sender.toLowerCase()}:example.org",
      roomName: "general",
      content: body,
      eventId: "\$event",
      roomId: "!general:example.org",
      clientId: "client-1",
      isDirectMessage: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("Who is in the call", () {
    test("talking is a voice coming through, not a share or the DJ", () {
      final session = _Session()
        ..streams = [
          _Stream("@ana:example.org", audiolevel: 1),
          _Stream("@bo:example.org",
              type: VoipStreamType.screenshareAudio, audiolevel: 1),
          _Stream("@dj:example.org",
              type: VoipStreamType.music, audiolevel: 1),
        ];
      expect(CallMember.of(session).where((m) => m.talking).map((m) => m.userId),
          ["@ana:example.org"]);
    });

    test("someone on two devices is muted only when both are", () {
      final session = _Session()
        ..streams = [
          _Stream("@ana:example.org", isMuted: true),
          _Stream("@ana:example.org"),
          _Stream("@bo:example.org", isMuted: true),
          _Stream("@bo:example.org", isDeafened: true),
        ];
      expect(CallMember.of(session), [
        const CallMember("@ana:example.org"),
        const CallMember("@bo:example.org", muted: true),
      ]);
    });

    test("our own mute and deafen come from the session", () {
      final session = _Session()
        ..isDeafened = true
        ..streams = [_Stream("@me:example.org")];
      expect(CallMember.of(session), [
        const CallMember("@me:example.org", muted: true, deafened: true),
      ]);
    });

    test("someone who publishes nothing is in it, and not muted", () {
      final session = _RosterSession()
        ..streams = [_Stream("@ana:example.org")]
        ..connectedUserIds = {"@ana:example.org", "@bo:example.org"};
      expect(CallMember.of(session), [
        const CallMember("@ana:example.org"),
        const CallMember("@bo:example.org"),
      ]);
    });
  });

  group("Talking to the runner", () {
    late CallManager calls;
    late _Runner runner;
    late GameOverlay overlay;
    late List<List<OverlayMember>> drawnCalls;
    late List<(String?, double, bool)> drawnCallDetails;
    late List<List<OverlayToast>> drawnToasts;
    // Decoded once: a cold decode is a round trip to the engine's threads,
    // which a pumped event queue does not wait for.
    late ui.Image avatar;
    // Whose avatars take their time, until completed.
    late Map<String, Completer<ui.Image>> slowAvatars;

    setUpAll(() async => avatar = await createTestImage(width: 1, height: 1));

    setUp(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await preferences.init();

      calls = CallManager(ClientManager());
      drawnCalls = [];
      drawnCallDetails = [];
      drawnToasts = [];
      slowAvatars = {};
      const channel = MethodChannel("test/overlay");
      runner = _Runner(channel);
      overlay = GameOverlay(
        channel: channel,
        calls: () => calls,
        tick: const Duration(milliseconds: 10),
        toastTime: const Duration(milliseconds: 50),
        drawVoice: (members,
            {String? more, required double scale, bool alignEnd = false}) async {
          drawnCalls.add(members);
          drawnCallDetails.add((more, scale, alignEnd));
          return _blank;
        },
        drawMessages: (toasts, {required double scale}) async {
          drawnToasts.add(toasts);
          return _blank;
        },
        drawAvatar: ({required color, required name, image}) =>
            slowAvatars[name]?.future ?? Future.value(avatar.clone()),
      );
      await overlay.start();
    });

    tearDown(() => overlay.stop());

    _Session joinCall() {
      final session = _Session()
        ..streams = [
          _Stream("@me:example.org", audiolevel: 1),
          _Stream("@ana:example.org", isMuted: true),
        ];
      calls.currentSessions.add(session);
      return session;
    }

    test("starts the runner, and stops it when turned off", () async {
      expect(runner.methods, ["start"]);
      await preferences.gameOverlayEnabled.set(false);
      await pumpEventQueue();
      expect(runner.methods.last, "stop");
    });

    test("draws nothing while no game is in front", () async {
      joinCall();
      await Future.delayed(const Duration(milliseconds: 30));
      expect(runner.panelsSet, isEmpty);
    });

    test("lists the call over a game, at the screen's scale", () async {
      joinCall();
      await runner.gameInFront(scale: 1.5);
      await pumpEventQueue();

      expect(runner.panelsSet.first, (OverlayPanel.voice.index, "topLeft"));
      expect(
          drawnCalls.first.map((m) => (m.name, m.talking, m.muted)).toList(), [
        ("@me:example.org", true, false),
        ("@ana:example.org", false, true),
      ]);
      expect(drawnCallDetails.first, (null, 1.5, false));
    });

    test("draws again only when something changes", () async {
      final session = joinCall();
      await runner.gameInFront();
      await Future.delayed(const Duration(milliseconds: 40));
      expect(drawnCalls, hasLength(1));

      session.streams = [_Stream("@me:example.org")];
      await Future.delayed(const Duration(milliseconds: 30));
      expect(drawnCalls, hasLength(2));
      expect(drawnCalls.last.single.talking, isFalse);
    });

    test("takes the panels down when the game goes", () async {
      joinCall();
      await runner.gameInFront();
      await pumpEventQueue();
      await runner.gameGone();
      await pumpEventQueue();
      expect(runner.panelsRemoved, contains(OverlayPanel.voice.index));
    });

    test("and when the call ends", () async {
      final session = joinCall();
      await runner.gameInFront();
      await pumpEventQueue();
      calls.currentSessions.remove(session);
      await Future.delayed(const Duration(milliseconds: 30));
      expect(runner.panelsRemoved, contains(OverlayPanel.voice.index));
    });

    test("only who is talking, when asked", () async {
      joinCall();
      await preferences.gameOverlayOnlyTalking.set(true);
      await runner.gameInFront();
      await pumpEventQueue();
      expect(drawnCalls.last.map((m) => m.name), ["@me:example.org"]);
    });

    test("in the corner picked, lined up on its side", () async {
      joinCall();
      await runner.gameInFront();
      await pumpEventQueue();
      await preferences.gameOverlayVoiceCorner.set("bottomRight");
      await pumpEventQueue();
      expect(runner.panelsSet.last, (OverlayPanel.voice.index, "bottomRight"));
      expect(drawnCallDetails.last.$3, isTrue);
    });

    test("past eight people, the rest are counted", () async {
      calls.currentSessions.add(_Session()
        ..streams = [
          for (var i = 0; i < 12; i++) _Stream("@p$i:example.org"),
        ]);
      await runner.gameInFront();
      await pumpEventQueue();
      expect(drawnCalls.last, hasLength(GameOverlay.maxMembers));
      expect(drawnCallDetails.last.$1, "4 more");
    });

    test("shows a message over the game, then takes it away", () async {
      await runner.gameInFront();
      await pumpEventQueue();
      overlay.showMessage(_message());
      await pumpEventQueue();

      expect(runner.panelsSet.last,
          (OverlayPanel.messages.index, "bottomRight"));
      final toast = drawnToasts.last.single;
      expect((toast.sender, toast.room, toast.body), ("Ana", "general", "gg"));
      expect(toast.avatar, isNotNull);

      await Future.delayed(const Duration(milliseconds: 80));
      expect(runner.panelsRemoved.last, OverlayPanel.messages.index);
    });

    test("keeps the last three messages", () async {
      await runner.gameInFront();
      await pumpEventQueue();
      for (final body in ["1", "2", "3", "4"]) {
        overlay.showMessage(_message(body: body));
        await pumpEventQueue();
      }
      expect(drawnToasts.last.map((t) => t.body), ["2", "3", "4"]);
    });

    test("in the order they came, a slow avatar filled in when it loads",
        () async {
      slowAvatars["Ana"] = Completer();
      await runner.gameInFront();
      await pumpEventQueue();
      overlay.showMessage(_message(sender: "Ana", body: "first"));
      overlay.showMessage(_message(sender: "Bo", body: "second"));
      await pumpEventQueue();
      expect(drawnToasts.last.map((t) => t.body), ["first", "second"]);
      expect(drawnToasts.last.first.avatar, isNull);

      final drawn = drawnToasts.length;
      slowAvatars["Ana"]!.complete(avatar.clone());
      await pumpEventQueue();
      expect(drawnToasts, hasLength(greaterThan(drawn)));
      expect(drawnToasts.last.first.avatar, isNotNull);
    });

    test("messages already up go when a screen share starts", () async {
      final session = joinCall();
      await runner.gameInFront();
      await pumpEventQueue();
      overlay.showMessage(_message());
      await pumpEventQueue();
      expect(runner.panelsSet.last.$1, OverlayPanel.messages.index);

      session.isSharingScreen = true;
      await Future.delayed(const Duration(milliseconds: 30));
      expect(runner.panelsRemoved, contains(OverlayPanel.messages.index));
    });

    test("no message without a game in front", () async {
      overlay.showMessage(_message());
      await pumpEventQueue();
      expect(drawnToasts, isEmpty);
    });

    test("no message while sharing the screen: it would be in the stream",
        () async {
      joinCall().isSharingScreen = true;
      await runner.gameInFront();
      await pumpEventQueue();
      overlay.showMessage(_message());
      await pumpEventQueue();
      expect(drawnToasts, isEmpty);
    });

    test("no message when messages are off", () async {
      await preferences.gameOverlayMessageCorner.set("off");
      await runner.gameInFront();
      await pumpEventQueue();
      overlay.showMessage(_message());
      await pumpEventQueue();
      expect(drawnToasts, isEmpty);
    });
  });
}
