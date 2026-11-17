import 'dart:io';

import 'package:rooster/diagnostic/speed_log/request_record.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';

/// A route as the speed log writes it: its method and the end of its route
/// template (the log keeps only templates and host classes, never a URL;
/// see docs/speed-log.md), such as `PUT` and `/send/{eventType}/{txnId}`.
typedef SpeedRoute = (String method, String templateEnd);

const sendEvent = ('PUT', '/send/{eventType}/{txnId}');
const keysQuery = ('POST', '/keys/query');
const keysClaim = ('POST', '/keys/claim');
const sendToDevice = ('PUT', '/sendToDevice/{eventType}/{txnId}');
const reserveMxc = ('POST', '/media/v1/create');
const uploadToMxc = ('PUT', '/media/v3/upload/{serverName}/{mediaId}');
const uploadMedia = ('POST', '/media/v3/upload');
const openIdToken = ('POST', '/openid/request_token');
const sfuGet = ('POST', '/sfu/get');
const healthz = ('GET', '/healthz');

String label(SpeedRoute route) => '${route.$1} ${route.$2}';

bool goesTo(RequestRecord request, SpeedRoute route) =>
    request.method == route.$1 && request.route.endsWith(route.$2);

/// How many of [requests] went to each of [routes], by [label]: a map that
/// a failed `expect` prints whole, so a regression names its route.
Map<String, int> countRoutes(
        Iterable<RequestRecord> requests, List<SpeedRoute> routes) =>
    {
      for (final route in routes)
        label(route): requests.where((r) => goesTo(r, route)).length,
    };

/// The attempt numbers (`RequestRecord.attempt`) of [requests] to each of
/// [routes], by [label], in the order of [requests].
Map<String, List<int>> attemptsByRoute(
        Iterable<RequestRecord> requests, List<SpeedRoute> routes) =>
    {
      for (final route in routes)
        label(route): [
          for (final request in requests)
            if (goesTo(request, route)) request.attempt
        ],
    };

/// Every route of [requests], counted: what a scenario prints beside what
/// it asserts.
Map<String, int> allRoutes(Iterable<RequestRecord> requests) {
  final counts = <String, int>{};
  for (final request in requests) {
    final key = '${request.method} ${request.route} ${request.hostClass.label}';
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

/// The app's requests made in [span].
List<RequestRecord> requestsOf(SpeedSpan span) => [
      for (final request in SpeedLog.instance.requests.toList())
        if (request.operationId == span.id) request
    ];

/// The app's requests started at [mark] (a `SpeedLog.instance.now()`) or
/// later, in a span or not.
List<RequestRecord> requestsSince(Duration mark) => [
      for (final request in SpeedLog.instance.requests.toList())
        if (request.startedAt >= mark) request
    ];

/// Why a test that needs the integration stack cannot run here, or null:
/// the homeserver [homeserver] (an `http://host[:port]` address) and, with
/// [livekit], the call token service the CI's well-known announces
/// (`LIVEKIT_URL`, scripts/integration-server-livekit.sh) must take a
/// connection.
Future<String?> integrationStackSkipReason(String homeserver,
    {bool livekit = false}) async {
  final server = Uri.parse(homeserver);
  if (!await _reachable(server.host, server.port)) {
    return 'SKIPPED: the homeserver is not reachable on '
        '${server.host}:${server.port} (HOMESERVER). These request counts '
        'need the integration Synapse (scripts/integration-server-synapse.sh); '
        'without it the test exercises nothing.';
  }
  if (livekit) {
    final focus = Uri.parse(
        Platform.environment['LIVEKIT_URL'] ?? 'http://localhost:8180');
    if (!await _reachable(focus.host, focus.port)) {
      return 'SKIPPED: LiveKit is not reachable on ${focus.host}:${focus.port} '
          '(LIVEKIT_URL). The call join counts need Synapse and LiveKit up '
          '(scripts/integration-server-livekit.sh).';
    }
  }
  return null;
}

Future<bool> _reachable(String host, int port) async {
  try {
    final socket =
        await Socket.connect(host, port, timeout: const Duration(seconds: 5));
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}
