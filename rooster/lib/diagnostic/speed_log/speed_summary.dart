import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';

/// The median and 95th percentile of [count] durations, by nearest rank:
/// p95 of 20 samples is the 19th smallest.
class Percentiles {
  const Percentiles(this.count, this.p50, this.p95);

  final int count;
  final Duration p50;
  final Duration p95;

  /// Null when [samples] is empty.
  static Percentiles? of(Iterable<Duration> samples) {
    final sorted = samples.toList()..sort();
    if (sorted.isEmpty) return null;
    Duration rank(double q) {
      final index = (q * sorted.length).ceil() - 1;
      return sorted[index.clamp(0, sorted.length - 1)];
    }

    return Percentiles(sorted.length, rank(0.5), rank(0.95));
  }
}

/// One step name of an operation, over its spans that ended `ok`.
class StepSummary {
  const StepSummary(this.name, this.timing, this.unavailable);

  final String name;

  /// Over the steps that were timed; null when none was.
  final Percentiles? timing;

  /// How many times the step could not be timed.
  final int unavailable;
}

/// One operation (a span name) in the log.
class OperationSummary {
  const OperationSummary(this.name, this.finished, this.total, this.steps);

  final String name;

  /// Finished spans, whatever their outcome.
  final int finished;

  /// Of the spans that ended `ok`; null when none did. Its count is how
  /// many ended `ok`.
  final Percentiles? total;

  /// In the order they first appear.
  final List<StepSummary> steps;

  int get ok => total?.count ?? 0;
}

/// p50 and p95 of every operation in [log] and of each of its steps, over
/// the finished spans that ended `ok` (a failed send or a dropped sync
/// would skew them; they are counted in [OperationSummary.finished]).
/// Operations are whatever span names the log holds, sorted by name.
List<OperationSummary> summarizeSpeedLog(SpeedLog log) {
  final byName = <String, List<SpeedSpan>>{};
  for (final span in log.spans.toList()) {
    byName.putIfAbsent(span.name, () => []).add(span);
  }
  final names = byName.keys.toList()..sort();
  return [
    for (final name in names) _operation(name, byName[name]!),
  ];
}

OperationSummary _operation(String name, List<SpeedSpan> spans) {
  final ok = spans.where((s) => s.outcome == SpeedOutcome.ok).toList();
  final timed = <String, List<Duration>>{};
  final unavailable = <String, int>{};
  for (final span in ok) {
    for (final step in span.steps) {
      final samples = timed.putIfAbsent(step.name, () => []);
      unavailable.putIfAbsent(step.name, () => 0);
      final duration = step.duration;
      if (duration == null) {
        unavailable[step.name] = unavailable[step.name]! + 1;
      } else {
        samples.add(duration);
      }
    }
  }
  return OperationSummary(
    name,
    spans.length,
    Percentiles.of([for (final span in ok) span.duration!]),
    [
      for (final step in timed.keys)
        StepSummary(step, Percentiles.of(timed[step]!), unavailable[step]!),
    ],
  );
}
