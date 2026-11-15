// Simulated matches: the plaque secret's simulated clients (secret/
// plaque_sim.dart) with a WhoMatch each, on fake time, so a test plays the
// rules the way the screens will, seconds and all.

import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:rooster/client/components/cock_a_doodle_who/match/match_engine.dart';

import '../secret/plaque_sim.dart';

export '../secret/plaque_sim.dart';

class MatchSim {
  MatchSim(this.async, int count, {this.seed = 1})
      : sim = Sim(count, seed: seed);

  final FakeAsync async;
  final Sim sim;
  final int seed;
  late final _clock = async.getClock(DateTime.utc(2026, 11, 15, 20));
  final Map<String, WhoMatch> matches = {};

  int get now => _clock.now().millisecondsSinceEpoch;

  /// Everyone in the call, the session launched by p0 and joined, each
  /// with its match; then [settings] in the lobby.
  void start([MatchSettings? settings]) {
    sim.start();
    run();
    sim.apps.forEach(_attach);
    run();
    if (settings != null) host.hostSetup(settings);
    run();
  }

  void _attach(SimApp app) {
    final match = matches[app.id] = WhoMatch(
      session: app.session,
      custody: app.custody,
      random: Random(app.seed),
      now: _clock.now,
    );
    match.addListener(() => _track(app));
  }

  /// The round and version of each owner's plaque the host's ledger last
  /// showed.
  final Map<String, (int, int)> _versions = {};

  /// Tells the inspection ([Sim.leaks]) when a plaque became public: the
  /// host's engine turned it, took it off, swapped it out or started a new
  /// round. The host's match notifies right after it told the custody,
  /// before anything that says so is delivered.
  void _track(SimApp app) {
    if (!app.session.isHost) return;
    final ledger = app.custody.ledger;
    for (final MapEntry(key: owner, value: entry) in ledger.entries.entries) {
      final version = (ledger.round, entry.version);
      final was = _versions[owner];
      if (entry.isOpen || (was != null && was != version)) sim.opened(owner);
      _versions[owner] = version;
    }
  }

  /// Runs every message and timer due now.
  void run() {
    for (var i = 0; i < 4; i++) {
      async.elapse(Duration.zero);
    }
  }

  /// Lets [time] go by.
  void wait(Duration time) {
    async.elapse(time);
    run();
  }

  void seconds(num count) =>
      wait(Duration(milliseconds: (count * 1000).round()));

  WhoMatch operator [](String id) => matches[id]!;

  WhoMatch get host => matches[sim.host.id]!;
  MatchState get state => host.state;
  String? get asker => state.asker;

  /// Someone enters the call and joins the session as a player.
  WhoMatch add(String id) {
    sim.add(id);
    run();
    _attach(sim[id]);
    run();
    return this[id];
  }

  /// Someone enters the call and watches the session.
  WhoMatch addSpectator(String id) {
    final app = sim.enter(id);
    run();
    app.session.join(asPlayer: false);
    run();
    _attach(app);
    run();
    return this[id];
  }

  /// [id]'s machine clock is [ahead] of the others' from now on.
  void skew(String id, Duration ahead) {
    matches.remove(id)!.dispose();
    final app = sim[id];
    final match = matches[id] = WhoMatch(
      session: app.session,
      custody: app.custody,
      random: Random(app.seed),
      now: () => _clock.now().add(ahead),
    );
    match.addListener(() => _track(app));
    run();
  }

  /// [id]'s client is gone without a word.
  void vanish(String id) {
    matches.remove(id)!.dispose();
    sim.vanish(id);
    run();
  }

  /// Homemade: everyone not [silent] writes the plaque they were given.
  void writeAll({Set<String> silent = const {}}) {
    for (final MapEntry(key: id, value: match) in matches.entries) {
      if (silent.contains(id) || match.writingFor == null) continue;
      match.write('for ${match.writingFor} by $id', PlaqueKind.person);
    }
    run();
  }

  /// Every responder of the current question gives [answer], or the
  /// answer [by] gives each.
  void answerAll(MatchAnswer answer, {MatchAnswer? Function(String)? by}) {
    for (final id in state.responders) {
      final given = by == null ? answer : by(id);
      if (given != null) this[id].answer(given);
    }
    run();
  }

  /// The plaques are on, the look is over: the first question.
  void toQuestions({Set<String> silent = const {}}) {
    if (state.phase == MatchPhase.writing) writeAll(silent: silent);
    if (silent.isNotEmpty) seconds(60);
    expectPhase(MatchPhase.look);
    seconds(10);
    expectPhase(MatchPhase.asking);
  }

  void expectPhase(MatchPhase phase) {
    if (state.phase != phase) {
      throw StateError('expected $phase, the match is in ${state.phase}');
    }
  }

  /// Whose plaque is still a secret to everyone's own client.
  List<String> ownLeaks() => [
        for (final MapEntry(key: id, value: match) in matches.entries)
          if (!(sim.host.custody.ledger.entries[id]?.isOpen ?? true) &&
              match.plaqueOf(id) != null)
            id,
      ];

  void close() {
    for (final match in matches.values) {
      match.dispose();
    }
    sim.close();
    run();
  }
}
