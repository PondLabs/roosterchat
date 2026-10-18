import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/voip/call_connection.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/ui/molecules/call_connection_status.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

class _Session implements VoipSession, CallConnection {
  @override
  VoipState state = VoipState.connected;
  @override
  bool reconnecting = false;
  @override
  CallConnectionQuality connectionQuality = CallConnectionQuality.excellent;
  @override
  String get roomName => "Cow-Working / Roscas do Lion, the long one";
  @override
  String? get serverName => "livekit.example.org";
  @override
  bool get encrypted => true;
  @override
  final List<CallConnectionSample> connectionHistory = [];
  @override
  Stream<void> get onStateChanged => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget child) => MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomLeft,
          // The sidebar's width.
          child: SizedBox(width: 240, child: child),
        ),
      ),
    );

void main() {
  testWidgets("says how the call is, and opens the details", (tester) async {
    final session = _Session();
    final now = DateTime.now();
    for (var i = 0; i < 120; i++) {
      session.connectionHistory.add(CallConnectionSample(
          now.subtract(Duration(seconds: 120 - i)),
          pingMs: 30.0 + i % 7,
          outboundLoss: 0));
    }
    await tester.pumpWidget(_app(CallConnectionStatus(
        session: session, connection: session, onOpenRoom: () {})));
    expect(find.text("Voice connected"), findsOneWidget);

    session.reconnecting = true;
    await tester.pump(const Duration(seconds: 1));
    expect(find.text("Reconnecting…"), findsOneWidget);

    await tester.tap(find.text("Reconnecting…"));
    await tester.pump();
    expect(find.text("Average ping: 33 ms"), findsOneWidget);
    expect(find.text("Last ping: 30 ms"), findsOneWidget);
    expect(find.text("Outbound packet loss: 0.0%"), findsOneWidget);
    expect(find.text("End-to-end encrypted"), findsOneWidget);
    expect(find.text("livekit.example.org"), findsOneWidget);

    // Its timers stop with it.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
