// Who holds each plaque of Cock-a-Doodle-Who?, and how it gets there
// without its owner's client ever receiving it. One [PlaqueCustody] runs in
// every client of the session, over the session's addressed lane
// ([CallActivitySession.sendTo]); the match's rules (who writes for whom,
// when a plaque is swapped or revealed) are the caller's.
// docs/adr/0007-plaque-secret.md has the protocol and its reasons.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:rooster/client/components/call_activity/call_activity_session.dart';
import 'package:rooster/client/components/cock_a_doodle_who/deck/deck.dart';
import 'package:rooster/client/components/cock_a_doodle_who/secret/plaque.dart';

export 'plaque.dart';

/// A plaque's content as this client holds it.
class _Held {
  _Held(this.tag, this.owner, this.round, this.version, this.plaque);

  final String tag;
  final String owner;
  final int round;
  final int version;
  final Plaque plaque;

  Map<String, Object?> toJson() => {
        PlaqueCustody._field: 'put',
        'tag': tag,
        'o': owner,
        'r': round,
        'v': version,
        'p': plaque.toJson(),
      };
}

Random _secureRandom() {
  try {
    return Random.secure();
  } on UnsupportedError {
    return Random();
  }
}

/// This client's share of the plaques' custody.
///
/// **Everyone holds every plaque but their own.** A plaque's content goes,
/// addressed, to the session's players and spectators except its owner, and
/// each keeps it; the host publishes only the [ledger], which says nothing
/// the owner may not know. So [plaqueOf] our own identity is null until the
/// reveal, on the host too.
///
/// How the match's engine uses it (the host's calls are no-ops elsewhere):
///
/// - Every client builds one for its session and listens to it; it sends
///   and publishes on its own (the ledger rides the session's state under
///   [partKey], apart from the game's payload).
/// - The host starts each round with [hostBeginRound]. In Homemade, each
///   author then calls [write] for the owner the engine gave them; tell an
///   author who that is with [CallActivitySession.sendTo], so that nobody
///   else's client learns it. In Deck, the cards are drawn at once.
/// - [hostDeal] gives an owner a new card: the swap someone asked for, or
///   the plaque of an owner whose author ran out of time.
/// - [hostReveal] turns a plaque, [hostRetire] takes off the plaque of an
///   owner who left; both make it public in the ledger. Reveal or retire
///   every plaque before the next round.
///
/// A host that takes the seat over carries on from the ledger it last
/// heard and from what it holds, which is everything but its own plaque.
class PlaqueCustody extends ChangeNotifier {
  PlaqueCustody({
    required this.session,
    required this.deck,
    Random? random,
    this.retryEvery = const Duration(seconds: 2),
  }) : _random = random ?? _secureRandom() {
    session.addListener(_run);
    _directSub = session.direct.listen(_onDirect);
    _run();
  }

  /// The key of the ledger in [CallActivitySnapshot.parts].
  static const partKey = 'plaques';

  /// The field that marks our messages on the addressed lane, and says
  /// which: `put` (a plaque's content), `note` (to a host that owns the
  /// plaque: it is dealt, without the content), `ask` and `nak`.
  static const _field = 'plaque';

  final CallActivitySession session;
  final Deck deck;

  /// How long an unanswered request waits before it goes to someone else.
  final Duration retryEvery;

  /// Draws the cards we deal. It never leaves this client: nothing sent
  /// says what it gave or will give.
  final Random _random;

  /// Names plaques and salts rounds. Apart from [_random], so that a tag
  /// tells nothing about a draw.
  final Random _names = _secureRandom();

  PlaqueLedger _ledger = PlaqueLedger();
  Object? _heardPart;
  String _sessionId = '';

  /// What we hold, by tag, oldest first.
  final Map<String, _Held> _held = {};

  /// The cards we have held in this session.
  final Set<String> _seen = {};

  /// What we wrote or dealt that the ledger does not show yet, by owner,
  /// and which host we told.
  final Map<String, _Held> _mine = {};
  final Map<String, String> _told = {};

  /// Who we asked for each tag we lack, who we have asked so far, and the
  /// owners who asked us before they may be answered.
  final Map<String, String> _asks = {};
  final Map<String, Set<String>> _tried = {};
  final Map<String, Set<String>> _waiting = {};

  StreamSubscription<CallActivityDirect>? _directSub;
  Timer? _retry;
  bool _dirty = false;
  bool _changed = false;
  bool _scheduled = false;
  bool _disposed = false;

  String get _self => session.selfIdentity;

  /// The public record of the round's plaques, the same on every client.
  PlaqueLedger get ledger => _ledger;

  /// What is written on [owner]'s plaque, as far as this client may know:
  /// null for our own until it is revealed, and for a plaque that is
  /// pending or has not reached us yet.
  Plaque? plaqueOf(String owner) {
    final entry = _ledger.entries[owner];
    if (entry == null) return null;
    if (entry.plaque != null || owner == _self) return entry.plaque;
    return _held[entry.tag]?.plaque;
  }

  // ----------------------------------------------------------- the author

  /// Homemade: we write [owner]'s plaque. It goes to everyone in the
  /// session but [owner], and [author] is us. False when the ledger is not
  /// waiting for an author's plaque for [owner] (not this round, already
  /// written, or the time ran out and a card took its place).
  bool write(String owner, {required PlaqueKind kind, required String text}) {
    final entry = _ledger.entries[owner];
    if (owner == _self || entry == null || entry.deal != null) return false;
    if (entry.state != PlaqueState.pending || _mine.containsKey(owner)) {
      return false;
    }
    _issue(owner, entry, Plaque(kind: kind, text: text, author: _self));
    _run();
    return true;
  }

  // ------------------------------------------------------------- the host

  /// Starts a round with a plaque asked for each of [owners]: written by
  /// an author ([deck] null, Homemade) or drawn with [deck] (Deck). The
  /// cards of the round before are spent.
  void hostBeginRound(Iterable<String> owners, {DeckFilter? deck}) {
    if (!session.isHost) return;
    _ledger.entries.values.forEach(_spend);
    _ledger = PlaqueLedger(
      round: _ledger.round + 1,
      salt: _name(),
      used: _ledger.used,
      owed: _ledger.owed,
      entries: {
        for (final owner in owners)
          owner: PlaqueEntry(
            version: 1,
            state: PlaqueState.pending,
            deal: deck == null ? null : PlaqueDeal(deck),
          ),
      },
    );
    _stage();
  }

  /// Asks for a card of the deck for [owner], in place of whatever plaque
  /// they had or were waiting for (which is spent, and dropped if it comes
  /// later). The host draws it, or, for its own, the present player with
  /// the lowest identity; the ledger shows it dealt when it is.
  void hostDeal(String owner, DeckFilter filter) {
    if (!session.isHost) return;
    final old = _ledger.entries[owner];
    if (old != null) _spend(old);
    _ledger.entries[owner] = PlaqueEntry(
      version: (old?.version ?? 0) + 1,
      state: PlaqueState.pending,
      deal: PlaqueDeal(filter),
    );
    _stage();
  }

  /// Turns [owner]'s plaque: the ledger carries what is written (and, in
  /// Homemade, its author) to everyone, the owner included. The host's own
  /// comes from someone who holds it, a moment later.
  void hostReveal(String owner) => _open(owner, PlaqueState.revealed);

  /// Takes off the plaque of an [owner] who left: public, like a reveal.
  void hostRetire(String owner) => _open(owner, PlaqueState.retired);

  void _open(String owner, PlaqueState state) {
    final entry = _ledger.entries[owner];
    if (!session.isHost || entry == null || entry.state == state) return;
    _ledger.entries[owner] = PlaqueEntry(
      version: entry.version,
      state: state,
      tag: entry.tag,
      kind: entry.kind,
      pool: entry.pool,
      plaque: entry.plaque,
    );
    _stage();
  }

  /// A plaque leaves play: its card is spent, or owed when we cannot know
  /// it (our own, or one that has not reached us).
  void _spend(PlaqueEntry entry) {
    final tag = entry.tag;
    if (tag == null) return;
    final card = (entry.plaque ?? _held[tag]?.plaque)?.cardId;
    if (card != null) {
      _ledger.used.add(card);
    } else if (entry.pool != null && !_held.containsKey(tag)) {
      _ledger.owed.add(tag);
    }
  }

  /// The ledger changed under the host's hand: the next state sent carries
  /// it, and the dealing runs once the caller is done.
  void _stage() {
    _dirty = true;
    session.hostPart(partKey, _ledger.toJson());
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      _run();
    });
  }

  /// The host's turn: what arrived goes into the ledger, then the cards
  /// asked for are drawn, one dealer at a time.
  void _settle() {
    final entries = _ledger.entries;
    for (final owner in entries.keys.toList()) {
      final entry = entries[owner]!;
      if (entry.state == PlaqueState.pending && owner != _self) {
        // Written by its author, or dealt under the host before us.
        final held = _held.values
            .where((h) =>
                h.owner == owner &&
                h.round == _ledger.round &&
                h.version == entry.version)
            .lastOrNull;
        if (held != null) _accept(owner, entry, held);
      } else if (entry.isOpen && entry.plaque == null) {
        final plaque = _held[entry.tag]?.plaque;
        if (plaque == null) continue;
        entries[owner] = PlaqueEntry(
          version: entry.version,
          state: entry.state,
          tag: entry.tag,
          kind: entry.kind,
          pool: entry.pool,
          plaque: plaque,
        );
        if (plaque.cardId != null) _ledger.used.add(plaque.cardId!);
        _dirty = true;
      }
    }
    for (final tag in _ledger.owed.where(_held.containsKey).toList()) {
      final card = _held[tag]!.plaque.cardId;
      if (card != null) _ledger.used.add(card);
      _ledger.owed.remove(tag);
      _dirty = true;
    }

    // One dealer at a time, each knowing every card in play but its own:
    // while a card is owed to us or ours is being drawn, we draw none.
    final own = entries[_self];
    final order = own?.state == PlaqueState.pending ? own!.deal : null;
    if (order?.dealer != null) {
      // Another dealer only when this one is gone from the game.
      if (!session.presentPlayers.contains(order!.dealer)) _order(own!, order);
      return;
    }
    if (_ledger.owed.isNotEmpty) return;
    for (final owner in entries.keys.toList()) {
      final entry = entries[owner]!;
      if (owner == _self || entry.state != PlaqueState.pending) continue;
      final card = entry.deal == null ? null : _draw(entry.deal!.filter);
      if (card == null) continue;
      _accept(owner, entry, _issue(owner, entry, Plaque.card(card)));
    }
    if (order != null) _order(own!, order);
  }

  /// Our own card is for someone else to draw: the present player with the
  /// lowest identity, named in the ledger.
  void _order(PlaqueEntry own, PlaqueDeal order) {
    final dealer = session.presentPlayers.where((p) => p != _self).firstOrNull;
    if (dealer == order.dealer) return;
    _ledger.entries[_self] = PlaqueEntry(
      version: own.version,
      state: PlaqueState.pending,
      deal: PlaqueDeal(order.filter, dealer: dealer),
    );
    _dirty = true;
  }

  int? _poolOf(Plaque plaque) =>
      plaque.cardId == null ? null : plaquePool(_ledger.salt, plaque.cardId!);

  void _accept(String owner, PlaqueEntry entry, _Held held) =>
      _dealt(owner, entry, held.tag, held.plaque.kind, _poolOf(held.plaque));

  /// The ledger shows [owner]'s plaque on their forehead.
  void _dealt(
      String owner, PlaqueEntry entry, String tag, PlaqueKind kind, int? pool) {
    _ledger.entries[owner] = PlaqueEntry(
      version: entry.version,
      state: PlaqueState.dealt,
      tag: tag,
      kind: kind,
      pool: pool,
    );
    _dirty = true;
  }

  // ------------------------------------------------------------ everyone

  /// One pass over everything there is to do, after anything happened.
  void _run() {
    if (_disposed) return;
    if (session.snapshot.sessionId != _sessionId) {
      _sessionId = session.snapshot.sessionId;
      _ledger = PlaqueLedger();
      for (final map in [_held, _mine, _told, _asks, _tried, _waiting]) {
        map.clear();
      }
      _seen.clear();
      _heardPart = null;
      _changed = true;
    }
    if (session.isHost) {
      _settle();
    } else {
      final part = session.snapshot.parts[partKey];
      if (part != null && !identical(part, _heardPart)) {
        _heardPart = part;
        _ledger = PlaqueLedger.fromJson(part);
        _changed = true;
      }
    }
    _held.removeWhere(
        (tag, h) => h.round < _ledger.round && !_ledger.owed.contains(tag));
    _mine.removeWhere((owner, held) {
      final entry = _ledger.entries[owner];
      return entry?.state != PlaqueState.pending ||
          entry!.version != held.version ||
          held.round != _ledger.round;
    });
    if (!session.isHost) _dealForHost();
    _announce();
    _answerWaiting();
    _sync();
    if (session.isHost && _dirty) {
      session.hostPart(partKey, _ledger.toJson());
      session.sendState();
      _changed = true;
    }
    _dirty = false;
    final busy = _asks.isNotEmpty || _mine.isNotEmpty;
    if (!busy) {
      _retry?.cancel();
      _retry = null;
    } else {
      _retry ??= Timer.periodic(retryEvery, (_) => _retryNow());
    }
    if (_changed) {
      _changed = false;
      notifyListeners();
    }
  }

  /// What went unanswered goes out again: requests to the next holder, and
  /// what we wrote or dealt to the host once more.
  void _retryNow() {
    _asks.clear();
    _told.clear();
    _run();
  }

  void _send(Iterable<String> to, Map<String, Object?> message) =>
      session.sendTo(to, message).catchError((_) {});

  /// Sends a plaque's content to [to], never to its owner before it is
  /// public: the one place a plaque leaves this client. Returns who it
  /// went to.
  Set<String> _put(_Held held, Iterable<String> to) {
    final open = _ledger.isOpen(held.tag);
    final readers = {
      for (final id in to)
        if (id != held.owner || open) id,
    };
    _send(readers, held.toJson());
    return readers;
  }

  Set<String> get _roster =>
      {...session.snapshot.players, ...session.snapshot.spectators};

  /// A random name, 60 bits of it: two clients never make the same one.
  String _name() => [_names.nextInt(1 << 30), _names.nextInt(1 << 30)]
      .map((n) => n.toRadixString(36))
      .join();

  /// We make [owner]'s plaque: we hold it, and everyone who may read it
  /// gets it. The host, when it is someone else, hears of it in [_announce].
  _Held _issue(String owner, PlaqueEntry entry, Plaque plaque) {
    final held = _Held(_name(), owner, _ledger.round, entry.version, plaque);
    _hold(held);
    if (!session.isHost) _mine[owner] = held;
    _put(held, _roster.difference({session.hostIdentity}));
    return held;
  }

  void _hold(_Held held) {
    _held[held.tag] = held;
    if (held.plaque.cardId != null) _seen.add(held.plaque.cardId!);
    _changed = true;
  }

  /// The host's own card is ours to draw when the ledger names us, once we
  /// hold every other plaque in play (so we see every card but ours).
  void _dealForHost() {
    final host = session.hostIdentity;
    final entry = _ledger.entries[host];
    if (host == null || entry == null || _mine.containsKey(host)) return;
    if (entry.state != PlaqueState.pending || entry.deal?.dealer != _self) {
      return;
    }
    if (_ledger.owed.isNotEmpty || _missing().isNotEmpty) return;
    final card = _draw(entry.deal!.filter);
    if (card != null) _issue(host, entry, Plaque.card(card));
  }

  /// A card for someone else, never one in play or spent: none that we
  /// hold or have held, none the ledger lists as used, and, as we cannot
  /// see our own card, none from the half of the deck it is in. When the
  /// theme runs out the draw takes any theme, and only when the deck does,
  /// a spent card.
  DeckCard? _draw(DeckFilter filter) {
    final own = _ledger.entries[_self];
    final avoid = own?.state == PlaqueState.dealt ? own!.pool : null;
    final inPlay = {
      for (final held in _held.values)
        if (held.plaque.cardId != null) held.plaque.cardId!,
      if (avoid != null)
        for (final card in deck.cards)
          if (plaquePool(_ledger.salt, card.id) == avoid) card.id,
    };
    final spent = {...inPlay, ..._seen, ..._ledger.used};
    final any =
        DeckFilter(packs: filter.packs, difficulties: filter.difficulties);
    for (final (from, blocked) in [
      (filter, spent),
      (any, spent),
      (any, inPlay)
    ]) {
      final card =
          deck.draw(from, used: blocked, nextInt: _random.nextInt).firstOrNull;
      if (card != null && !blocked.contains(card.id)) return card;
    }
    return null;
  }

  /// Tells the host what we wrote or dealt, until the ledger shows it:
  /// the content when the host may read it, a note without it when the
  /// plaque is the host's own. Again for each new host.
  void _announce() {
    final host = session.hostIdentity;
    _told.removeWhere((owner, _) => !_mine.containsKey(owner));
    for (final MapEntry(key: owner, value: held) in _mine.entries) {
      if (host == null || host == _self || _told[owner] == host) continue;
      _told[owner] = host;
      if (host != owner) {
        _put(held, [host]);
        continue;
      }
      _send([
        host
      ], {
        _field: 'note',
        'tag': held.tag,
        'r': held.round,
        'v': held.version,
        'kind': held.plaque.kind.key,
        'pool': _poolOf(held.plaque),
      });
    }
  }

  /// The tags of the plaques we may read and do not hold, with each one's
  /// owner (null for a card owed to the host).
  Map<String, String?> _missing() => !_roster.contains(_self)
      ? const {}
      : {
          for (final MapEntry(key: owner, value: entry)
              in _ledger.entries.entries)
            if (entry.tag != null &&
                entry.plaque == null &&
                !_held.containsKey(entry.tag) &&
                (owner != _self || (entry.isOpen && session.isHost)))
              entry.tag!: owner,
          if (session.isHost)
            for (final tag in _ledger.owed)
              if (!_held.containsKey(tag)) tag: null,
        };

  /// Asks a holder for each plaque we lack: someone who joined mid-round,
  /// a message lost in a reconnect, and the host's own once it is public.
  void _sync() {
    final missing = _missing();
    _asks.removeWhere((tag, _) => !missing.containsKey(tag));
    _tried.removeWhere((tag, _) => !missing.containsKey(tag));
    for (final MapEntry(key: tag, value: owner) in missing.entries) {
      final asked = _asks[tag];
      if (asked == null || !session.transport.isPresent(asked)) {
        _askNext(tag, owner);
      }
    }
  }

  void _askNext(String tag, String? owner) {
    final tried = _tried.putIfAbsent(tag, () => {});
    final host = session.hostIdentity;
    final holders = [
      if (host != null) host,
      ..._roster.toList()..sort(),
    ]
        .where((id) =>
            id != _self &&
            id != owner &&
            !tried.contains(id) &&
            session.transport.isPresent(id))
        .toList();
    _asks.remove(tag);
    if (holders.isEmpty) {
      // Everyone here was asked. A card nobody can tell the host stays
      // unknown; anything else is asked for again on the next retry.
      _tried.remove(tag);
      if (session.isHost && _ledger.owed.remove(tag)) _stage();
      return;
    }
    tried.add(holders.first);
    _asks[tag] = holders.first;
    _send([holders.first], {_field: 'ask', 'tag': tag});
  }

  /// Answers who asked us for a plaque. Its owner waits here until the
  /// plaque is public ([_put] sends them nothing before).
  void _answerWaiting() {
    _waiting.removeWhere((tag, askers) {
      final held = _held[tag];
      if (held != null) askers.removeAll(_put(held, askers));
      return held == null || askers.isEmpty;
    });
  }

  void _onDirect(CallActivityDirect direct) {
    if (_disposed) return;
    final message = direct.message;
    final tag = message['tag'];
    if (tag is! String) return;
    switch (message[_field]) {
      case 'put':
        final owner = message['o'], round = message['r'], v = message['v'];
        final plaque = Plaque.fromJson(message['p']);
        if (owner is! String || round is! int || v is! int) return;
        if (plaque == null) return;
        // Our own is not ours to keep before it is public.
        if (owner == _self && !_ledger.isOpen(tag)) return;
        _hold(_Held(tag, owner, round, v, plaque));
      case 'note':
        // Our own plaque is on our forehead: the host's ledger says so.
        final entry = _ledger.entries[_self];
        final dealer = entry?.deal?.dealer;
        if (!session.isHost || entry?.state != PlaqueState.pending) return;
        if (message['r'] != _ledger.round || message['v'] != entry!.version) {
          return;
        }
        if (entry.deal != null && dealer != direct.sender) return;
        final kind = PlaqueKind.values
            .where((k) => k.key == message['kind'])
            .firstOrNull;
        final pool = message['pool'];
        if (kind == null) return;
        _dealt(_self, entry, tag, kind, pool is int ? pool : null);
      case 'ask':
        final held = _held[tag];
        if (held == null || !_roster.contains(direct.sender)) {
          _send([direct.sender], {_field: 'nak', 'tag': tag});
        } else {
          _waiting.putIfAbsent(tag, () => {}).add(direct.sender);
        }
      case 'nak':
        final missing = _missing();
        if (_asks[tag] == direct.sender && missing.containsKey(tag)) {
          _askNext(tag, missing[tag]);
        }
    }
    _run();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    session.removeListener(_run);
    _directSub?.cancel();
    _retry?.cancel();
    super.dispose();
  }
}
