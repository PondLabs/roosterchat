import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

/// How the media server judges our connection, LiveKit's verdict.
enum CallConnectionQuality { unknown, lost, poor, good, excellent }

/// One reading of our connection to a call, taken once a second.
class CallConnectionSample {
  const CallConnectionSample(this.at,
      {this.pingMs, this.packetsSent, this.packetsLost, this.outboundLoss});

  final DateTime at;

  /// The round trip to the media server, in milliseconds.
  final double? pingMs;

  /// Running counts of our audio packets: sent, and reported lost by the
  /// server.
  final int? packetsSent;
  final int? packetsLost;

  /// The share of our packets lost since the reading before, 0 to 1.
  final double? outboundLoss;

  /// Reads [reports], a peer connection's statistics. [previous] is the
  /// reading before, which the loss is counted from.
  static CallConnectionSample fromStats(
      DateTime at, Iterable<rtc.StatsReport> reports,
      {CallConnectionSample? previous}) {
    final byId = {for (final r in reports) r.id: r};

    // The pair the transport uses; with no transport report, the one
    // nominated and working.
    final selectedId = reports
        .where((r) => r.type == 'transport')
        .map((r) => r.values['selectedCandidatePairId'])
        .whereType<String>()
        .firstOrNull;
    final pair = byId[selectedId] ??
        reports
            .where((r) =>
                r.type == 'candidate-pair' &&
                r.values['nominated'] == true &&
                r.values['state'] == 'succeeded')
            .firstOrNull;

    num? rtt = pair?.values['currentRoundTripTime'] as num?;
    int? sent;
    int? lost;
    for (final r in reports) {
      final v = r.values;
      if (v['kind'] != null && v['kind'] != 'audio') continue;
      switch (r.type) {
        case 'outbound-rtp':
          if (v['packetsSent'] case final num n) sent = (sent ?? 0) + n.toInt();
        case 'remote-inbound-rtp':
          if (v['packetsLost'] case final num n) lost = (lost ?? 0) + n.toInt();
          rtt ??= v['roundTripTime'] as num?;
      }
    }

    double? loss;
    final before = previous;
    if (before != null &&
        sent != null &&
        lost != null &&
        before.packetsSent != null &&
        before.packetsLost != null) {
      final newlySent = sent - before.packetsSent!;
      final newlyLost = lost - before.packetsLost!;
      if (newlySent > 0) loss = (newlyLost / newlySent).clamp(0.0, 1.0);
    }

    return CallConnectionSample(at,
        pingMs: rtt == null ? null : rtt * 1000,
        packetsSent: sent,
        packetsLost: lost,
        outboundLoss: loss);
  }
}

/// A call that can say how our connection to it is doing: the status row
/// of the call panel and its details.
abstract class CallConnection {
  /// The connection dropped and the call is trying to get it back.
  bool get reconnecting;

  CallConnectionQuality get connectionQuality;

  /// The media server we are connected to.
  String? get serverName;

  /// Whether the call's media is end-to-end encrypted.
  bool get encrypted;

  /// The readings of the last few minutes, oldest first.
  List<CallConnectionSample> get connectionHistory;

  /// How long [connectionHistory] goes back.
  static const historyLength = Duration(minutes: 5);
}
