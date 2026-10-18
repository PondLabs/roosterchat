import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:rooster/client/components/voip/call_connection.dart';
import 'package:test/test.dart';

rtc.StatsReport _report(String id, String type, Map<String, dynamic> values) =>
    rtc.StatsReport(id, type, 0, values);

List<rtc.StatsReport> _stats({required int sent, required int lost}) => [
      _report("T1", "transport", {"selectedCandidatePairId": "CP2"}),
      _report("CP1", "candidate-pair",
          {"currentRoundTripTime": 0.5, "nominated": false}),
      _report("CP2", "candidate-pair",
          {"currentRoundTripTime": 0.036, "nominated": true}),
      _report("OA", "outbound-rtp", {"kind": "audio", "packetsSent": sent}),
      _report("OV", "outbound-rtp", {"kind": "video", "packetsSent": 9999}),
      _report("RA", "remote-inbound-rtp",
          {"kind": "audio", "packetsLost": lost, "roundTripTime": 0.9}),
    ];

void main() {
  final t0 = DateTime(2026, 10, 18);

  test("the ping is the selected pair's, in milliseconds", () {
    final sample = CallConnectionSample.fromStats(t0, _stats(sent: 100, lost: 0));
    expect(sample.pingMs, closeTo(36, 0.001));
    expect(sample.outboundLoss, isNull, reason: "nothing to count from yet");
  });

  test("the loss is of the audio sent since the reading before", () {
    final first =
        CallConnectionSample.fromStats(t0, _stats(sent: 1000, lost: 50));
    final second = CallConnectionSample.fromStats(
        t0.add(const Duration(seconds: 1)), _stats(sent: 1050, lost: 55),
        previous: first);
    expect(second.outboundLoss, closeTo(0.1, 1e-9));
  });

  test("without a transport report, the nominated working pair", () {
    final sample = CallConnectionSample.fromStats(t0, [
      _report("CP1", "candidate-pair", {
        "currentRoundTripTime": 0.02,
        "nominated": true,
        "state": "succeeded"
      }),
    ]);
    expect(sample.pingMs, closeTo(20, 0.001));
  });

  test("nothing sent since the reading before is no loss reading", () {
    final first =
        CallConnectionSample.fromStats(t0, _stats(sent: 1000, lost: 50));
    final second = CallConnectionSample.fromStats(
        t0.add(const Duration(seconds: 1)), _stats(sent: 1000, lost: 50),
        previous: first);
    expect(second.outboundLoss, isNull);
  });
}
