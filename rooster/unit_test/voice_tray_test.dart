import 'dart:io';

import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/utils/voice_controls/voice_controls.dart';
import 'package:rooster/utils/voice_tray.dart';
import 'package:test/test.dart';

class _Session implements VoipSession {
  _Session(this.state,
      {this.isMicrophoneMuted = false, this.isDeafened = false});

  @override
  final VoipState state;
  @override
  final bool isMicrophoneMuted;
  @override
  final bool isDeafened;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group("Tray icon", () {
    test("the logo when not in a call", () {
      expect(VoiceTray.statusOf([]), VoiceTrayStatus.idle);
    });

    test("a ringing or ended call is not being in a call", () {
      expect(
          VoiceTray.statusOf(
              [_Session(VoipState.incoming), _Session(VoipState.ended)]),
          VoiceTrayStatus.idle);
    });

    test("a mic while heard", () {
      expect(VoiceTray.statusOf([_Session(VoipState.connected)]),
          VoiceTrayStatus.live);
    });

    test("a muted mic while muted", () {
      expect(
          VoiceTray.statusOf(
              [_Session(VoipState.connected, isMicrophoneMuted: true)]),
          VoiceTrayStatus.muted);
    });

    test("a muted mic while deafened", () {
      expect(
          VoiceTray.statusOf([_Session(VoipState.connected, isDeafened: true)]),
          VoiceTrayStatus.muted);
    });

    test("heard in any call counts as heard", () {
      expect(
          VoiceTray.statusOf([
            _Session(VoipState.connected, isMicrophoneMuted: true),
            _Session(VoipState.connecting),
          ]),
          VoiceTrayStatus.live);
    });
  });

  group("Tray menu", () {
    List<String> menu(VoiceCallState state) => VoiceTray.menuOf(state)
        .items!
        .map((item) => item.type == "separator" ? "-" : item.label!)
        .toList();

    test("open and quit when not in a call", () {
      expect(menu(VoiceCallState.idle), ["Open Rooster", "-", "Quit"]);
    });

    test("the call controls, disconnect included, while in a call", () {
      expect(
          menu(
              const VoiceCallState(inCall: true, muted: true, deafened: false)),
          [
            "Open Rooster",
            "-",
            "Unmute",
            "Deafen",
            "Disconnect",
            "-",
            "Quit",
          ]);
    });
  });

  // KDE Plasma's tray takes the icon file's name and looks it up in the
  // icon theme before it reads the file: with idle.png and live.png, themes
  // like MacTahoe, WhiteSur and Papirus showed Python's IDLE and Outlook in
  // place of our logo and mic.
  group("Tray icon files", () {
    for (final windows in [false, true]) {
      final platform = windows ? "Windows" : "Linux";

      for (final status in VoiceTrayStatus.values) {
        final asset = VoiceTray.iconAsset(status, windows: windows);

        test("$platform, ${status.name}: the file is there", () {
          expect(File(asset).existsSync(), isTrue, reason: asset);
          expect(asset, endsWith(windows ? ".ico" : ".png"));
        });

        test("$platform, ${status.name}: a name no icon theme has", () {
          final name = asset.split("/").last.split(".").first;
          expect(name, startsWith("rooster_tray_"));
          // Theme lookups fall back from "a-b-c" to "a-b" and "a", which
          // could land on another icon.
          expect(name, isNot(contains("-")));
        });
      }
    }

    test("a different icon for each status", () {
      expect({
        for (final status in VoiceTrayStatus.values)
          VoiceTray.iconAsset(status, windows: false)
      }, hasLength(VoiceTrayStatus.values.length));
    });
  });
}
