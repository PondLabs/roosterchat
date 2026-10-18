import 'dart:async';
import 'dart:math';

import 'package:rooster/client/components/voip/call_connection.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/ui/atoms/anchored_popover.dart';
import 'package:rooster/ui/atoms/speaking_indicator.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:tiamat/tiamat.dart' as tiamat;

/// The call panel's top row, like Discord's: whether the call is connected,
/// reconnecting or still connecting, in the color of how good the
/// connection is, and the room under it. Clicking the status opens the
/// connection's details ([CallConnectionDetails]).
class CallConnectionStatus extends StatefulWidget {
  const CallConnectionStatus(
      {required this.session,
      required this.connection,
      required this.onOpenRoom,
      super.key});

  final VoipSession session;
  final CallConnection connection;
  final VoidCallback onOpenRoom;

  static String get labelCallConnected => Intl.message("Voice connected",
      name: "labelCallConnected",
      desc: "Status at the top of the call panel at the bottom of the "
          "sidebar while we are in a voice call");

  static String get labelCallConnecting => Intl.message("Connecting…",
      name: "labelCallConnecting",
      desc: "Status at the top of the call panel while joining a voice call");

  static String get labelCallReconnecting => Intl.message("Reconnecting…",
      name: "labelCallReconnecting",
      desc: "Status at the top of the call panel while the connection to the "
          "voice call dropped (the internet went down) and is being retried");

  static String get tooltipCallConnection => Intl.message("Connection details",
      name: "tooltipCallConnection",
      desc: "Tooltip on the call panel's status, which opens the ping and "
          "packet loss of the voice connection");

  /// Green while fine, amber while poor or getting back, red when lost.
  static Color colorOf(BuildContext context, CallConnection connection,
      VoipSession session) {
    if (connection.reconnecting || session.state != VoipState.connected) {
      return Colors.amber;
    }
    return switch (connection.connectionQuality) {
      CallConnectionQuality.poor => Colors.amber,
      CallConnectionQuality.lost => ColorScheme.of(context).error,
      _ => SpeakingIndicator.color,
    };
  }

  @override
  State<CallConnectionStatus> createState() => _CallConnectionStatusState();
}

class _CallConnectionStatusState extends State<CallConnectionStatus> {
  late final StreamSubscription _sub;

  /// The quality has no event of its own: read again every second.
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _sub = widget.session.onStateChanged.listen((_) => setState(() {}));
    _timer = Timer.periodic(
        const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _sub.cancel();
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connection = widget.connection;
    final color =
        CallConnectionStatus.colorOf(context, connection, widget.session);
    final label = connection.reconnecting
        ? CallConnectionStatus.labelCallReconnecting
        : widget.session.state == VoipState.connected
            ? CallConnectionStatus.labelCallConnected
            : CallConnectionStatus.labelCallConnecting;
    final icon = connection.reconnecting
        ? Icons.signal_cellular_connected_no_internet_0_bar_rounded
        : switch (connection.connectionQuality) {
            CallConnectionQuality.poor =>
              Icons.signal_cellular_alt_2_bar_rounded,
            CallConnectionQuality.lost =>
              Icons.signal_cellular_alt_1_bar_rounded,
            _ => Icons.signal_cellular_alt_rounded,
          };

    return AnchoredPopover(
      alignment: PopoverAlignment.start,
      anchorBuilder: (context, open, toggle) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
        child: Row(
          spacing: 6,
          children: [
            Tooltip(
              message: CallConnectionStatus.tooltipCallConnection,
              child: InkWell(
                onTap: toggle,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(icon, color: color, size: 20),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: toggle,
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(
                                color: color, fontWeight: FontWeight.w600)),
                  ),
                  InkWell(
                    onTap: widget.onOpenRoom,
                    child: Opacity(
                      opacity: 0.7,
                      child: tiamat.Text.labelLow(widget.session.roomName,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      popoverBuilder: (context, close) =>
          CallConnectionDetails(connection: connection),
    );
  }
}

/// The connection's details: the ping over the last minutes, the server,
/// average and last ping, and how much of what we send is lost.
class CallConnectionDetails extends StatefulWidget {
  const CallConnectionDetails({required this.connection, super.key});

  final CallConnection connection;

  static const width = 300.0;

  static String get labelConnectionTitle => Intl.message("Connection",
      name: "labelConnectionTitle",
      desc: "Title of the voice connection details opened from the call "
          "panel's status");

  static String labelAveragePing(String ms) => Intl.message(
      "Average ping: $ms ms",
      name: "labelAveragePing",
      args: [ms],
      desc: "Voice connection details: the average round trip time to the "
          "media server over the last minutes, in milliseconds");

  static String labelLastPing(String ms) => Intl.message("Last ping: $ms ms",
      name: "labelLastPing",
      args: [ms],
      desc: "Voice connection details: the latest round trip time to the "
          "media server, in milliseconds");

  static String labelOutboundPacketLoss(String percent) => Intl.message(
      "Outbound packet loss: $percent%",
      name: "labelOutboundPacketLoss",
      args: [percent],
      desc: "Voice connection details: the share of our voice packets that "
          "did not reach the media server, as a percentage");

  static String get labelConnectionAdvice => Intl.message(
      "Above 250 ms of ping, you and the others hear each other late. Above "
      "10% packet loss, your voice breaks up. If it stays like this, leave "
      "the call and join it again.",
      name: "labelConnectionAdvice",
      desc: "Voice connection details: what the numbers above mean for the "
          "call, and what to do when they are bad");

  static String get labelEndToEndEncrypted => Intl.message(
      "End-to-end encrypted",
      name: "labelEndToEndEncrypted",
      desc: "Voice connection details: the call's audio and video can only "
          "be read by the people in it");

  @override
  State<CallConnectionDetails> createState() => _CallConnectionDetailsState();
}

class _CallConnectionDetailsState extends State<CallConnectionDetails> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
        const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final history = widget.connection.connectionHistory;
    final pings = history.map((s) => s.pingMs).whereType<double>().toList();
    final losses =
        history.map((s) => s.outboundLoss).whereType<double>().toList();
    final format = NumberFormat.decimalPattern(Intl.getCurrentLocale());
    final percent = NumberFormat("0.0", Intl.getCurrentLocale());
    // Not translated: a dash where there is no reading yet.
    const none = "—";

    final average = pings.isEmpty
        ? none
        : format.format((pings.reduce((a, b) => a + b) / pings.length).round());
    final last = pings.isEmpty ? none : format.format(pings.last.round());
    final loss = losses.isEmpty
        ? none
        : percent
            .format(losses.reduce((a, b) => a + b) / losses.length * 100);

    return SizedBox(
      width: CallConnectionDetails.width,
      child: Material(
        color: colors.surfaceContainer,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: colors.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Text(CallConnectionDetails.labelConnectionTitle,
                  style: text.titleSmall?.copyWith(color: colors.primary)),
              SizedBox(
                height: 100,
                width: double.infinity,
                child: CustomPaint(
                  painter: _PingGraph(
                    history,
                    now: DateTime.now(),
                    line: colors.primary,
                    grid: colors.outlineVariant,
                    label: text.labelSmall!
                        .copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
              ),
              if (widget.connection.serverName case final String server)
                Text(server,
                    style: text.bodyMedium?.copyWith(
                        fontFamily: "Code", fontWeight: FontWeight.w600)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(CallConnectionDetails.labelAveragePing(average)),
                  Text(CallConnectionDetails.labelLastPing(last)),
                  Text(CallConnectionDetails.labelOutboundPacketLoss(loss)),
                ],
              ),
              Text(CallConnectionDetails.labelConnectionAdvice,
                  style: text.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant)),
              if (widget.connection.encrypted)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: SpeakingIndicator.color.withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    spacing: 6,
                    children: [
                      Icon(Icons.lock_rounded,
                          size: 14, color: SpeakingIndicator.color),
                      Flexible(
                        child: Text(
                            CallConnectionDetails.labelEndToEndEncrypted,
                            style: text.labelMedium
                                ?.copyWith(color: SpeakingIndicator.color)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The ping of the last [CallConnection.historyLength], newest on the
/// right, scaled to 100 ms or the highest reading. A missing reading breaks
/// the line.
class _PingGraph extends CustomPainter {
  _PingGraph(this.history,
      {required this.now,
      required this.line,
      required this.grid,
      required this.label});

  final List<CallConnectionSample> history;
  final DateTime now;
  final Color line;
  final Color grid;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    const labelWidth = 28.0;
    final plot = Size(size.width - labelWidth, size.height);
    final top = max(
        100.0,
        history
            .map((s) => s.pingMs ?? 0)
            .fold(0.0, (a, b) => max(a, b)));
    final scale = (top / 50).ceil() * 50.0;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      final y = plot.height * f;
      canvas.drawLine(Offset(0, y), Offset(plot.width, y), gridPaint);
      final value = (scale * (1 - f)).round().toString();
      final painter = TextPainter(
          text: TextSpan(text: value, style: label),
          textDirection: TextDirection.ltr)
        ..layout();
      painter.paint(
          canvas,
          Offset(plot.width + 4,
              (y - painter.height / 2).clamp(0, size.height - painter.height)));
    }

    final span = CallConnection.historyLength.inMilliseconds;
    final path = Path();
    var drawing = false;
    for (final sample in history) {
      final ping = sample.pingMs;
      if (ping == null) {
        drawing = false;
        continue;
      }
      final age = now.difference(sample.at).inMilliseconds;
      final x = plot.width * (1 - age / span);
      final y = plot.height * (1 - min(ping, scale) / scale);
      if (drawing) {
        path.lineTo(x, y);
      } else {
        path.moveTo(x, y);
        drawing = true;
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _PingGraph old) => true;
}
