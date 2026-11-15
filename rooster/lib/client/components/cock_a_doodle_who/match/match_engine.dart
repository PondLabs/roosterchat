// The match of Cock-a-Doodle-Who? over a call-activity session: one
// [WhoMatch] runs in every client. The host's plays the rules
// (match_rules.dart) on the state everyone sees (match_state.dart), keeps
// the time and tells the plaques' custody (secret/plaque_custody.dart) when
// a round starts and a plaque is dealt, swapped, revealed or retired;
// everyone else's reads the state and sends the host what its player does.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:rooster/client/components/call_activity/call_activity_session.dart';
import 'package:rooster/client/components/cock_a_doodle_who/deck/deck.dart';
import 'package:rooster/client/components/cock_a_doodle_who/match/match_rules.dart';
import 'package:rooster/client/components/cock_a_doodle_who/match/match_settings.dart';
import 'package:rooster/client/components/cock_a_doodle_who/match/match_state.dart';
import 'package:rooster/client/components/cock_a_doodle_who/secret/plaque_custody.dart';

export 'package:rooster/client/components/cock_a_doodle_who/deck/deck.dart';
export 'package:rooster/client/components/cock_a_doodle_who/secret/plaque_custody.dart';

export 'match_rules.dart';
export 'match_settings.dart';
export 'match_state.dart';

/// What came of [WhoMatch.write].
enum WriteResult {
  /// The plaque went to everyone but its owner.
  sent,

  /// The text is empty or longer than [maxPlaqueText] characters.
  badText,

  /// We have no plaque to write now: not writing, already written, or the
  /// time ran out and a card took its place.
  closed,
}

Random _secureRandom() {
  try {
    return Random.secure();
  } on UnsupportedError {
    return Random();
  }
}

/// This client's match.
///
/// The screens read [state] and the plaques ([plaqueOf]), listen to this,
/// and act with [write], [answer], [askSwap] and [chooseTheme]; the host's
/// screens also with the `host` methods. Every action of a player who is
/// not the host goes to the host on the session's addressed lane, which
/// stamps its sender, so nobody can act for someone else.
///
/// The times in [state] are milliseconds since the epoch on the host's
/// clock, and every state says what that clock read when it was sent
/// ([MatchState.sentAt]). Each client keeps how far the host's clock is
/// from its own [now] ([hostNow]); the machines' clocks need not agree. A
/// host that takes the seat over carries on from the last state it heard,
/// its deadlines moved onto its own clock: the same phase, order, points
/// and time left.
class WhoMatch extends ChangeNotifier {
  WhoMatch({
    required this.session,
    required this.custody,
    Random? random,
    DateTime Function()? now,
  })  : _random = random ?? _secureRandom(),
        now = now ?? DateTime.now {
    session.addListener(_onSession);
    custody.addListener(_onCustody);
    _directSub = session.direct.listen(_onDirect);
    _onSession();
  }

  /// The field that marks the match's messages on the addressed lane, and
  /// says which: `write` (host to author: whose plaque), `answer`, `swap`
  /// and `theme` (a player to the host).
  static const _field = 'who';

  final CallActivitySession session;

  /// The plaques of the session. Not ours to dispose.
  final PlaqueCustody custody;

  /// This machine's clock. The deadlines are on the host's: see [hostNow].
  final DateTime Function() now;

  /// Draws the turns' order, who writes for whom and a theme nobody
  /// picked. Only the host's is used.
  final Random _random;

  MatchState _state = MatchState();
  Object? _heard;
  String _sessionId = '';
  bool _hosting = false;
  bool _disposed = false;
  Timer? _timer;
  StreamSubscription<CallActivityDirect>? _directSub;

  /// Homemade: the round and the owner whose plaque we write, as the host
  /// told us; and the round we wrote it in.
  (int, String)? _writeFor;
  int _wroteIn = 0;

  /// The host's clock less ours, in milliseconds, from the last state
  /// heard; 0 while we host.
  int _offset = 0;

  /// The [MatchState.sentAt] [_offset] was taken from. The custody sends
  /// the state again with its own changes, the match's untouched: only a
  /// state the match itself sent says what the host's clock reads now.
  int? _offsetFrom;

  /// The match as the host last published it.
  MatchState get state => _state;

  String get _self => session.selfIdentity;
  int get _now => now().millisecondsSinceEpoch;

  /// The host's clock now, in milliseconds since the epoch, as far as this
  /// client can tell (off by the time the last state took to arrive): what
  /// the deadlines in [state] count down against.
  int get hostNow => _now + _offset;

  /// A new match in the lobby: nothing to write from the one before.
  void _forgetWriting() {
    _writeFor = null;
    _wroteIn = 0;
  }

  /// Whether we play this round: we were there when it started and have
  /// not left. Who joins mid-round watches until the next one.
  bool get playsThisRound =>
      _state.order.contains(_self) && !_state.left.contains(_self);

  /// Homemade, while the plaques are written: the owner whose plaque we
  /// write. Null when we write none or already wrote it.
  String? get writingFor {
    final assignment = _writeFor;
    if (_state.phase != MatchPhase.writing || assignment == null) return null;
    final (round, owner) = assignment;
    return round == _state.round && _wroteIn != round ? owner : null;
  }

  /// What is written on [owner]'s plaque, as far as we may know: null for
  /// our own until it is revealed, and while it is on its way.
  Plaque? plaqueOf(String owner) => custody.plaqueOf(owner);

  // ------------------------------------------------------- every player

  /// Homemade: writes the plaque of [writingFor]: [text] from 1 to
  /// [maxPlaqueText] characters, trimmed, and its [kind].
  WriteResult write(String text, PlaqueKind kind) {
    final owner = writingFor;
    if (owner == null) return WriteResult.closed;
    final clean = plaqueText(text);
    if (clean == null) return WriteResult.badText;
    // Marked first: the custody tells its listeners while it sends.
    final wrote = _wroteIn;
    _wroteIn = _state.round;
    if (!custody.write(owner, kind: kind, text: clean)) {
      _wroteIn = wrote;
      return WriteResult.closed;
    }
    notifyListeners();
    return WriteResult.sent;
  }

  /// Answers the current question; a later answer replaces it until the
  /// count closes. Only the round's players who are not asking count.
  void answer(MatchAnswer answer) =>
      _act({_field: 'answer', 'a': answer.key, 'q': _state.questionId});

  /// Deck, before the questions start: asks for another card for
  /// [owner]'s plaque. Each plaque is swapped once at most.
  void askSwap(String owner) => _act({_field: 'swap', 'o': owner});

  /// Deck, on the scoreboard, for the last-placed player: the next round's
  /// [theme], null for Anything goes.
  void chooseTheme(DeckTheme? theme) =>
      _act({_field: 'theme', 'th': theme?.key ?? 'any'});

  void _act(Map<String, Object?> action) {
    if (session.isHost) {
      _onAction(_self, action);
      return;
    }
    final host = session.hostIdentity;
    if (host != null) session.sendTo([host], action).catchError((_) {});
  }

  // ----------------------------------------------------------- the host

  /// The settings of the match, in the lobby.
  void hostSetup(MatchSettings settings) {
    if (!session.isHost || _state.phase != MatchPhase.lobby) return;
    _state.settings = settings;
    _apply(publish: true);
  }

  /// Starts the first round. False when not in the lobby or with fewer
  /// than two players.
  bool hostStart() {
    if (!session.isHost || _state.phase != MatchPhase.lobby) return false;
    if (session.presentPlayers.length < 2) return false;
    _beginRound();
    _apply(publish: true);
    return true;
  }

  /// Without a clock, passes the turn of whoever is asking.
  void hostSkipTurn() {
    if (!session.isHost || _state.phase != MatchPhase.asking) return;
    if (_state.settings.secondsPerQuestion != null) return;
    _passTurn();
    _apply(publish: true);
  }

  /// On the scoreboard, starts the next round now (Deck: with a random
  /// theme when none was picked).
  void hostContinue() {
    if (!session.isHost || _state.phase != MatchPhase.scores) return;
    _beginRound();
    _apply(publish: true);
  }

  /// After the final result: back to the lobby, the points cleared.
  void hostPlayAgain() {
    if (!session.isHost || _state.phase != MatchPhase.finished) return;
    _state = MatchState(settings: _state.settings);
    _forgetWriting();
    _apply(publish: true);
  }

  // ------------------------------------------------------------ the loop

  void _onSession() {
    if (_disposed) return;
    if (session.snapshot.sessionId != _sessionId) {
      _sessionId = session.snapshot.sessionId;
      _state = MatchState();
      _heard = null;
      _offset = 0;
      _offsetFrom = null;
      _forgetWriting();
    }
    final game = session.snapshot.game;
    if (!session.isHost) {
      _hosting = false;
      _timer?.cancel();
      _timer = null;
      if (!identical(game, _heard)) {
        _heard = game;
        if (game.isNotEmpty) {
          final was = _state.phase;
          _state = MatchState.fromJson(game);
          final sent = _state.sentAt;
          if (sent != null && sent != _offsetFrom) {
            _offsetFrom = sent;
            _offset = sent - _now;
          }
          if (_state.phase == MatchPhase.lobby && was != MatchPhase.lobby) {
            _forgetWriting();
          }
        }
        notifyListeners();
      }
      return;
    }
    if (!_hosting) {
      // The seat is ours: from the state we last heard, if there was one,
      // its deadlines moved from the old host's clock onto ours.
      _hosting = true;
      if (game.isNotEmpty && !identical(game, _heard)) {
        _state = MatchState.fromJson(game);
      }
      int? ours(int? deadline) => deadline == null ? null : deadline - _offset;
      _state
        ..deadline = ours(_state.deadline)
        ..tallyDeadline = ours(_state.tallyDeadline);
      _offset = 0;
      _apply(publish: true);
      return;
    }
    _apply();
  }

  void _onCustody() {
    if (_disposed) return;
    if (session.isHost) _apply();
    notifyListeners();
  }

  void _onDirect(CallActivityDirect direct) {
    if (_disposed) return;
    final message = direct.message;
    if (message[_field] == 'write') {
      final round = message['r'], owner = message['o'];
      if (direct.sender != session.hostIdentity) return;
      if (round is! int || owner is! String) return;
      _writeFor = (round, owner);
      notifyListeners();
    } else if (message[_field] is String && session.isHost) {
      _onAction(direct.sender, message);
    }
  }

  /// What a player did, on the host.
  void _onAction(String sender, Map<String, Object?> action) {
    final s = _state;
    switch (action[_field]) {
      case 'answer':
        final answer = MatchAnswer.parse(action['a']);
        if (s.phase != MatchPhase.asking || answer == null) return;
        if (action['q'] != s.questionId) return;
        if (!s.responders.contains(sender)) return;
        s.answers[sender] = answer;
        s.tallyDeadline ??= _now + MatchTimes.answers.inMilliseconds;
      case 'swap':
        final owner = action['o'];
        if (s.settings.mode != MatchMode.deck || owner is! String) return;
        if (s.phase != MatchPhase.dealing && s.phase != MatchPhase.look) {
          return;
        }
        if (owner == sender || !session.snapshot.players.contains(sender)) {
          return;
        }
        if (!s.active.contains(owner) || s.swapped.contains(owner)) return;
        if (custody.ledger.entries[owner]?.state != PlaqueState.dealt) return;
        s.swapped.add(owner);
        custody.hostDeal(owner, s.settings.filter(s.theme));
      case 'theme':
        if (s.phase != MatchPhase.scores || s.themePicked) return;
        if (s.settings.mode != MatchMode.deck || sender != s.chooser) return;
        final key = action['th'];
        final theme = DeckTheme.values.where((t) => t.key == key).firstOrNull;
        if (theme == null && key != 'any') return;
        s.themePicked = true;
        s.nextTheme = theme;
      default:
        return;
    }
    // The state changed before [_apply] could see it: send it anyway.
    _apply(publish: true);
  }

  /// The host's pass over the rules, after anything happened: who left,
  /// then each phase whose time or condition came, until nothing moves.
  /// The state goes out when it changed.
  void _apply({bool publish = false}) {
    if (_disposed || !session.isHost) return;
    final before = jsonEncode(_state.toJson());
    final phase = _state.phase;
    if (phase != MatchPhase.lobby && phase != MatchPhase.finished) {
      _noteLeavers();
      if (session.presentPlayers.length < 2) {
        _finish();
      } else {
        for (var steps = 0; steps < 32 && _step(); steps++) {}
      }
    }
    if (publish || jsonEncode(_state.toJson()) != before) {
      _state.sentAt = _now;
      session.hostGamePayload(_state.toJson());
      _heard = session.snapshot.game;
      session.sendState();
      notifyListeners();
    }
    _arm();
  }

  /// Wakes the host at the next deadline still to come.
  void _arm() {
    _timer?.cancel();
    _timer = null;
    final t = _now;
    final next = [_state.deadline, _state.tallyDeadline]
        .nonNulls
        .where((d) => d > t)
        .fold<int?>(null, (a, d) => a == null ? d : min(a, d));
    if (next == null) return;
    _timer = Timer(Duration(milliseconds: next - t), _apply);
  }

  /// The round's players who are gone: their plaque comes off, they
  /// answer no more and their turn is skipped.
  void _noteLeavers() {
    final here = session.presentPlayers.toSet();
    for (final player in _state.order) {
      if (here.contains(player) || _state.left.contains(player)) continue;
      _state.left.add(player);
      _state.answers.remove(player);
      if (_state.answers.isEmpty) _state.tallyDeadline = null;
      custody.hostRetire(player);
    }
  }

  /// Whether every plaque of the round is on its owner's forehead.
  bool get _allDealt => _state.order.every((owner) {
        if (_state.left.contains(owner)) return true;
        final entry = custody.ledger.entries[owner];
        return entry != null && entry.state != PlaqueState.pending;
      });

  bool _passed(int? deadline) => deadline != null && _now >= deadline;

  /// One move of the current phase, when its time or condition came.
  bool _step() {
    final s = _state;
    switch (s.phase) {
      case MatchPhase.writing:
        if (_passed(s.deadline)) {
          // Nobody wrote it in time: a card of Anything goes, from the
          // packs that are on.
          for (final owner in s.active) {
            final entry = custody.ledger.entries[owner];
            if (entry?.state == PlaqueState.pending && entry?.deal == null) {
              custody.hostDeal(owner, DeckFilter(packs: s.settings.packs));
            }
          }
        }
        if (!_allDealt) return false;
        _look();
      case MatchPhase.dealing:
        if (!_allDealt) return false;
        _look();
      case MatchPhase.look:
        if (!_passed(s.deadline)) return false;
        s.phase = MatchPhase.asking;
        s.lap = 1;
        s.turn = -1;
        _passTurn();
      case MatchPhase.asking:
        final asker = s.asker;
        if (asker == null || s.left.contains(asker)) {
          _passTurn();
          return true;
        }
        if (s.active.length < 2) {
          // One player has not guessed: their rescue, whoever asks now.
          _rescue();
          return true;
        }
        final responders = s.responders;
        final all =
            responders.isNotEmpty && responders.every(s.answers.containsKey);
        if (s.answers.isNotEmpty && (all || _passed(s.tallyDeadline))) {
          _closeCount(asker);
        } else if (s.answers.isEmpty && _passed(s.deadline)) {
          s.last = MatchTally(asker, null, const {});
          _passTurn();
        } else {
          return false;
        }
      case MatchPhase.rescue:
        if (!_passed(s.deadline)) return false;
        _endRound();
      case MatchPhase.scores:
        final picked = s.settings.mode == MatchMode.deck && s.themePicked;
        if (!picked && !_passed(s.deadline)) return false;
        _beginRound();
      case MatchPhase.lobby:
      case MatchPhase.finished:
        return false;
    }
    return true;
  }

  void _look() {
    _state
      ..phase = MatchPhase.look
      ..deadline = _now + MatchTimes.look.inMilliseconds;
  }

  /// A new round: everyone in the game now plays it, in a new order.
  void _beginRound() {
    final s = _state;
    final order = [...session.presentPlayers]..shuffle(_random);
    s
      ..round += 1
      ..order = order
      ..guessed = {}
      ..left = {}
      ..swapped = {}
      ..roundPoints = {}
      ..answers = {}
      ..tallyDeadline = null
      ..last = null
      ..turn = 0
      ..lap = 1
      ..question = 1
      ..chooser = null;
    for (final player in order) {
      s.points.putIfAbsent(player, () => 0);
      s.stats.putIfAbsent(player, PlayerStats.new);
    }
    if (s.settings.mode == MatchMode.homemade) {
      s
        ..theme = null
        ..phase = MatchPhase.writing
        ..deadline = _now + MatchTimes.writing.inMilliseconds;
      custody.hostBeginRound(order);
      // Each author learns their owner alone.
      final writers = drawWriters(order, _random);
      for (final MapEntry(key: author, value: owner) in writers.entries) {
        if (author == _self) {
          _writeFor = (s.round, owner);
        } else {
          session.sendTo([author],
              {_field: 'write', 'r': s.round, 'o': owner}).catchError((_) {});
        }
      }
    } else {
      s.theme = switch (s.round) {
        1 => s.settings.theme,
        _ when s.themePicked => s.nextTheme,
        _ => DeckTheme.values[_random.nextInt(DeckTheme.values.length)],
      };
      s
        ..phase = MatchPhase.dealing
        ..deadline = null;
      custody.hostBeginRound(order, deck: s.settings.filter(s.theme));
    }
    s
      ..themePicked = false
      ..nextTheme = null;
  }

  /// The turn goes to the next player still asking, a lap more when the
  /// order starts over. With one player left, or past the lap limit, the
  /// rescue.
  void _passTurn() {
    final s = _state;
    final active = s.active;
    if (active.length < 2) {
      _rescue();
      return;
    }
    var next = s.turn, lap = s.lap;
    for (var step = 0; step < s.order.length; step++) {
      next++;
      if (next >= s.order.length) {
        next = 0;
        lap++;
      }
      if (active.contains(s.order[next])) break;
    }
    if (lap > s.settings.lapLimit) {
      _rescue();
      return;
    }
    s
      ..turn = next
      ..lap = lap;
    _newQuestion(1);
  }

  void _newQuestion(int question) {
    final seconds = _state.settings.secondsPerQuestion;
    _state
      ..question = question
      ..questionId += 1
      ..answers = {}
      ..tallyDeadline = null
      ..deadline = seconds == null ? null : _now + seconds * 1000;
  }

  /// The count of the current question closes, and decides.
  void _closeCount(String asker) {
    final s = _state;
    final outcome =
        tallyOutcome(s.answers.values, responders: s.responders.length)!;
    s.last = MatchTally(asker, outcome, {
      for (final MapEntry(:key, :value) in s.counts.entries)
        if (value > 0) key: value,
    });
    s.stats[asker] = (s.stats[asker] ?? const PlayerStats()).add(
      asked: 1,
      guessed: outcome == TallyOutcome.gotIt ? 1 : 0,
      noes: outcome == TallyOutcome.no ? 1 : 0,
    );
    switch (outcome) {
      case TallyOutcome.gotIt:
        final points = lapPoints(lapLimit: s.settings.lapLimit, lap: s.lap);
        s.guessed[asker] = s.lap;
        s.roundPoints[asker] = points;
        s.points[asker] = (s.points[asker] ?? 0) + points;
        custody.hostReveal(asker);
        _passTurn();
      case TallyOutcome.yes when s.question < maxQuestionsPerTurn:
        _newQuestion(s.question + 1);
      case TallyOutcome.yes:
      case TallyOutcome.no:
        _passTurn();
    }
  }

  void _rescue() {
    final s = _state;
    if (s.active.isEmpty) {
      _endRound();
      return;
    }
    s
      ..phase = MatchPhase.rescue
      ..answers = {}
      ..tallyDeadline = null
      ..deadline = _now + MatchTimes.rescue.inMilliseconds;
  }

  /// The plaques still on foreheads turn, for no points; then the
  /// scoreboard, or the final result after the last round.
  void _endRound() {
    final s = _state;
    s.active.forEach(custody.hostReveal);
    if (s.round >= s.settings.rounds) {
      _finish();
      return;
    }
    s
      ..phase = MatchPhase.scores
      ..answers = {}
      ..tallyDeadline = null;
    if (s.settings.mode == MatchMode.homemade) {
      s.deadline = _now + MatchTimes.scores.inMilliseconds;
      return;
    }
    // The last-placed player of the round still here picks the next
    // theme; who only watched it is not in the standings.
    final here = session.presentPlayers.where(s.order.contains);
    final last = here.fold<String?>(
        null,
        (low, p) =>
            low == null || (s.points[p] ?? 0) < (s.points[low] ?? 0) ? p : low);
    s
      ..chooser = last
      ..themePicked = false
      ..deadline = _now + MatchTimes.themeChoice.inMilliseconds;
  }

  void _finish() {
    final s = _state;
    // A match cut short mid-round turns the plaques still on foreheads.
    if (s.phase != MatchPhase.scores && s.phase != MatchPhase.finished) {
      s.active.forEach(custody.hostReveal);
    }
    s
      ..phase = MatchPhase.finished
      ..answers = {}
      ..deadline = null
      ..tallyDeadline = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _directSub?.cancel();
    session.removeListener(_onSession);
    custody.removeListener(_onCustody);
    super.dispose();
  }
}
