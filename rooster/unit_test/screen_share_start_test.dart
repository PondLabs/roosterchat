// Screen share from the PWA on a phone: the button was there and did
// nothing. No browser on a phone can capture the screen, and the call
// view's start had no error handling, so the failure went nowhere.
import 'dart:async';

import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/components/voip/voip_stream.dart';
import 'package:rooster/ui/molecules/screen_share_start_reporting.dart';
import 'package:rooster/ui/organisms/call_view/call_control_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

class _Source implements ScreenCaptureSource {
  @override
  bool get captureAudio => true;
}

class _Session implements VoipSession {
  _Session({this.supportsScreenshare = true});

  @override
  final bool supportsScreenshare;

  /// What starting the share throws, if anything.
  Object? failure;
  int picks = 0;
  int shares = 0;

  @override
  Future<ScreenCaptureSource?> pickScreenCapture(BuildContext context) async {
    picks++;
    return _Source();
  }

  @override
  Future<void> setScreenShare(ScreenCaptureSource source) async {
    final failure = this.failure;
    if (failure != null) throw failure;
    shares++;
  }

  @override
  bool get isSharingScreen => false;

  @override
  bool get isMicrophoneMuted => false;

  @override
  bool get isDeafened => false;

  @override
  bool get isCameraEnabled => false;

  @override
  List<VoipStream> get streams => const [];

  @override
  Stream<void> get onStateChanged => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<BuildContext> pumpApp(WidgetTester tester, {Widget? child}) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: Builder(builder: (c) {
          context = c;
          return child ?? const SizedBox();
        }),
      ),
    ));
    return context;
  }

  testWidgets('where the browser cannot capture the screen, it says so',
      (tester) async {
    final session = _Session(supportsScreenshare: false);
    final context = await pumpApp(tester);

    await startScreenshareOrReportFailure(context, session);
    await tester.pump();

    expect(find.text(messageScreenShareUnsupported), findsOneWidget);
    expect(session.picks, 0, reason: 'nothing to pick from');
  });

  testWidgets('a share that fails to start is reported', (tester) async {
    final session = _Session()..failure = StateError('no capture');
    final context = await pumpApp(tester);

    await startScreenshareOrReportFailure(context, session);
    await tester.pump();

    expect(find.text(messageCouldNotShareScreen), findsOneWidget);
  });

  testWidgets("closing the browser's picker is not a failure", (tester) async {
    final session = _Session()
      ..failure = Exception('NotAllowedError: Permission denied');
    final context = await pumpApp(tester);

    await startScreenshareOrReportFailure(context, session);
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
  });

  test('a capture the system refused is one', () {
    expect(
        isScreenCaptureDismissed(
            Exception('NotAllowedError: Permission denied by system')),
        isFalse);
    expect(isScreenCaptureDismissed(StateError('no capture')), isFalse);
  });

  testWidgets('a share that starts says nothing', (tester) async {
    final session = _Session();
    final context = await pumpApp(tester);

    await startScreenshareOrReportFailure(context, session);
    await tester.pump();

    expect(session.shares, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  group("the call's buttons on a phone", () {
    Future<void> openMore(WidgetTester tester, _Session session) async {
      await pumpApp(tester,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: CallControlButtons(
              session: session,
              actions: CallControlActions(
                pickScreenshareSource: () => startScreenshareOrReportFailure(
                    tester.element(find.byType(CallControlButtons)), session),
              ),
              radius: 24,
              compact: true,
            ),
          ));
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
    }

    const shareTile = ValueKey('callControls_shareScreen');

    testWidgets('say why the screen cannot be shared, and do not offer it',
        (tester) async {
      final session = _Session(supportsScreenshare: false);
      await openMore(tester, session);

      expect(find.text(messageScreenShareUnsupported), findsOneWidget);
      expect(tester.widget<ListTile>(find.byKey(shareTile)).enabled, isFalse);

      await tester.tap(find.byKey(shareTile), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(session.picks, 0);
    });

    testWidgets('share the screen where it can be', (tester) async {
      final session = _Session();
      await openMore(tester, session);

      expect(find.text(messageScreenShareUnsupported), findsNothing);
      await tester.tap(find.byKey(shareTile));
      await tester.pumpAndSettle();

      expect(session.shares, 1);
    });
  });
}
