import 'package:rooster/diagnostic/speed_log/request_record.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';

/// The speed log as plain text, to copy into an issue. Times count from the
/// log's start on a monotonic clock. Holds route templates, host classes,
/// numbers and the fixed names of spans and steps: no ids, names, hosts,
/// URLs or tokens (see `RequestRecord` and `SpeedSpan`).
///
/// One request per line:
/// `+12.345s POST /_matrix/media/v3/upload homeserver status=200 attempt=1 up=1048576 down=62 headers=523ms total=524ms handed_over=12ms(transport) to_answer=511ms up_rate=2052kB/s`
///
/// One span per line, its steps indented under it.
String buildSpeedReport(SpeedLog log) {
  final out = StringBuffer()
    ..writeln('Rooster speed report')
    ..writeln('clock: monotonic, +seconds since the log started')
    ..writeln()
    ..writeln('requests (${log.requests.length}, newest '
        '${log.requests.capacity} kept):');
  for (final request in log.requests.toList()) {
    out.writeln(describeRequest(request));
  }
  final open = log.openSpans;
  out
    ..writeln()
    ..writeln('spans (${log.spans.length} finished, ${open.length} open):');
  for (final span in [...log.spans.toList(), ...open]) {
    out.writeln(_span(span));
    for (final step in span.steps) {
      out.writeln('  ${_step(step)}');
    }
  }
  return out.toString();
}

/// One line for [r], as in the report.
String describeRequest(RequestRecord r) {
  final parts = <String>[
    _at(r.startedAt),
    r.method,
    r.route,
    r.hostClass.label,
    r.status != null ? 'status=${r.status}' : 'error=${r.error}',
    if (r.status != null && r.error != null) 'error=${r.error}',
    'attempt=${r.attempt}',
    if (r.operationId != null) 'op=${r.operationId}',
    'up=${r.bytesUp}',
    'down=${r.bytesDown}',
    'headers=${_ms(r.timeToHeaders)}',
    'total=${_ms(r.total)}',
    if (r.retryAfterMs != null) 'retry_after_ms=${r.retryAfterMs}',
    if (r.bodyHandedOver != null)
      'handed_over=${_ms(r.bodyHandedOver)}(${r.handOverBoundary})',
    if (r.handedOverToAnswer != null) 'to_answer=${_ms(r.handedOverToAnswer)}',
    if (r.uploadBytesPerSecond != null)
      'up_rate=${(r.uploadBytesPerSecond! / 1000).round()}kB/s',
  ];
  return parts.join(' ');
}

String _span(SpeedSpan s) => [
      _at(s.startedAt),
      s.name,
      'op=${s.id}',
      s.isFinished ? 'total=${_ms(s.duration)}' : 'open',
      if (s.outcome != null) 'outcome=${s.outcome}',
      'longest_frame=${_ms(s.longestFrame)}',
    ].join(' ');

String _step(SpanStep step) => [
      step.name,
      if (step.available) '+${_ms(step.start)}',
      _ms(step.duration),
      for (final value in step.values.entries) '${value.key}=${value.value}',
    ].join(' ');

String _at(Duration d) => '+${(d.inMilliseconds / 1000).toStringAsFixed(3)}s';

String _ms(Duration? d) => d == null
    ? 'unavailable'
    : '${(d.inMicroseconds / 1000).toStringAsFixed(d.inMilliseconds < 10 ? 1 : 0)}ms';
