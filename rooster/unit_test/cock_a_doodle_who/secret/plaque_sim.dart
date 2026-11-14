// Simulated matches for the plaque secret's tests: clients on the in-memory
// call, each with its session and its PlaqueCustody, driven the way the
// match's engine will drive them, and an inspection of every message each
// client was delivered.

import 'dart:convert';
import 'dart:math';

import 'package:rooster/client/components/call_activity/call_activity_component.dart';
import 'package:rooster/client/components/call_activity/call_activity_protocol.dart';
import 'package:rooster/client/components/call_activity/call_activity_session.dart';
import 'package:rooster/client/components/call_activity/call_activity_transport.dart';
import 'package:rooster/client/components/cock_a_doodle_who/deck/deck.dart';
import 'package:rooster/client/components/cock_a_doodle_who/secret/plaque_custody.dart';

final whoActivity =
    CallActivity(id: 'chat.commet.who', displayName: () => 'Who');

/// A deck of [perTheme] cards in each theme. A card's id is unlike anything
/// else on the wire, and its name and caption contain it, so finding the id
/// in a message finds the card in any of its forms.
Deck simDeck({int perTheme = 40}) => Deck([
      for (final theme in DeckTheme.values)
        for (var i = 0; i < perTheme; i++)
          DeckCard(
            id: 'card-${theme.index}-${'$i'.padLeft(3, '0')}',
            theme: theme,
            kind: PlaqueKind.values[i % PlaqueKind.values.length],
            reach: CardReach.world,
            difficulty: CardDifficulty.values[i % 3],
            texts: {
              'en': CardText(
                name: 'Name of card-${theme.index}-${'$i'.padLeft(3, '0')}',
                caption: 'About card-${theme.index}-${'$i'.padLeft(3, '0')}',
              ),
            },
          ),
    ]);

/// One client: its session, its custody and the seed its draws come from.
class SimApp {
  SimApp(this.id, this.session, this.custody, this.seed);

  final String id;
  final CallActivitySession session;
  final PlaqueCustody custody;
  final int seed;
}

class Sim {
  Sim(this.count, {this.seed = 1, Deck? deck, this.retryEvery})
      : deck = deck ?? simDeck();

  final int count;
  final int seed;
  final Deck deck;
  final Duration? retryEvery;
  final call = InMemoryActivityCall();
  final List<SimApp> apps = [];

  /// When each secret of each owner became public: how many messages had
  /// been delivered by then.
  final Map<(String, String), int> _openedAt = {};

  /// Launches the session on `p0` and has `p1`... join it as players.
  Future<void> start() async {
    for (var i = 0; i < count; i++) {
      _app('p$i');
    }
    await apps.first.session.launch();
    await settle();
    for (final app in apps.skip(1)) {
      await app.session.join();
    }
    await settle();
  }

  SimApp _app(String id) {
    final session = CallActivitySession(
        activity: whoActivity,
        selfUserId: '@$id:example.org',
        transport: call.join(id));
    final seed = 918273645 + this.seed * 1000003 + apps.length * 7919;
    final app = SimApp(
        id,
        session,
        PlaqueCustody(
          session: session,
          deck: deck,
          random: Random(seed),
          retryEvery: retryEvery ?? const Duration(hours: 1),
        ),
        seed);
    apps.add(app);
    return app;
  }

  /// Someone enters the call and the session mid-round.
  Future<SimApp> add(String id) async {
    final app = _app(id);
    await settle();
    await app.session.join();
    await settle();
    return app;
  }

  /// [id]'s client is gone from the call without a word.
  Future<void> vanish(String id) async {
    final app = this[id];
    apps.remove(app);
    call.leave(id);
    app.custody.dispose();
    app.session.dispose();
    await settle();
  }

  SimApp operator [](String id) => apps.firstWhere((a) => a.id == id);

  SimApp get host => apps.firstWhere((a) => a.session.isHost);

  List<String> get players => host.session.snapshot.players.toList()..sort();

  /// Runs until nobody has anything left to send.
  Future<void> settle() async {
    var quiet = 0, last = -1;
    while (quiet < 4) {
      await Future<void>.delayed(Duration.zero);
      quiet = call.log.length == last ? quiet + 1 : 0;
      last = call.log.length;
    }
  }

  Future<void> close() async {
    for (final app in apps) {
      app.custody.dispose();
      app.session.dispose();
    }
    await call.close();
  }

  // -------------------------------------------------- the engine's moves

  /// A Deck round: a card for every player.
  Future<void> deckRound([DeckFilter filter = const DeckFilter()]) async {
    players.forEach(opened);
    host.custody.hostBeginRound(players, deck: filter);
    await settle();
  }

  /// A Homemade round: each player writes for the next one, except the
  /// [silent] ones, whose owners are left waiting.
  Future<void> homemadeRound({Set<String> silent = const {}}) async {
    players.forEach(opened);
    host.custody.hostBeginRound(players);
    await settle();
    final ring = players;
    for (var i = 0; i < ring.length; i++) {
      final author = ring[i], owner = ring[(i + 1) % ring.length];
      if (silent.contains(author)) continue;
      this[author].custody.write(owner,
          kind: PlaqueKind.person,
          text:
              'homemade for $owner by $author in ${host.custody.ledger.round}');
    }
    await settle();
  }

  /// A new card for [owner]: a swap, or the writing time that ran out.
  Future<void> deal(String owner,
      [DeckFilter filter = const DeckFilter()]) async {
    opened(owner);
    host.custody.hostDeal(owner, filter);
    await settle();
  }

  Future<void> reveal(String owner) async {
    opened(owner);
    host.custody.hostReveal(owner);
    await settle();
  }

  Future<void> retire(String owner) async {
    opened(owner);
    host.custody.hostRetire(owner);
    await settle();
  }

  /// What is on [owner]'s forehead, as the others hold it.
  Plaque? truth(String owner) => apps
      .where((a) => a.id != owner)
      .map((a) => a.custody.plaqueOf(owner))
      .nonNulls
      .firstOrNull;

  /// Everything wrong with where the round's plaques are: one not dealt, a
  /// client of the session that does not hold another's, or holds its own.
  List<String> misplaced() {
    final problems = <String>[];
    final ledger = host.custody.ledger;
    final roster = {
      ...host.session.snapshot.players,
      ...host.session.snapshot.spectators,
    };
    for (final MapEntry(key: owner, value: entry) in ledger.entries.entries) {
      if (entry.isOpen) continue;
      if (entry.state != PlaqueState.dealt) problems.add('$owner: not dealt');
      for (final app in apps.where((a) => roster.contains(a.id))) {
        final plaque = app.custody.plaqueOf(owner);
        if (app.id == owner && plaque != null) {
          problems.add('$owner holds their own plaque');
        } else if (app.id != owner && plaque?.text != truth(owner)?.text) {
          problems.add('${app.id} does not hold $owner\'s plaque');
        }
      }
    }
    return problems;
  }

  // ------------------------------------------------------ the inspection

  /// Plaques seen in a client's hands that were never sent: with two
  /// clients, the host's plaque stays with the one who made it.
  final Map<String, Set<String>> _unsent = {};

  /// The secrets of each owner: the text and the card of every plaque ever
  /// made for them, read from what was sent and from who holds them.
  Map<String, Set<String>> _secrets() {
    for (final owner in host.custody.ledger.entries.keys) {
      final plaque = truth(owner);
      if (plaque == null) continue;
      _unsent
          .putIfAbsent(owner, () => {})
          .addAll([plaque.text, if (plaque.cardId != null) plaque.cardId!]);
    }
    final secrets = {
      for (final MapEntry(:key, :value) in _unsent.entries) key: {...value},
    };
    for (final (_, message, _) in call.log) {
      final put = message['m'];
      if (message['t'] != 'direct' || put is! Map) continue;
      if (put['plaque'] != 'put') continue;
      final plaque = put['p'] as Map;
      secrets.putIfAbsent(put['o'] as String, () => {}).addAll([
        plaque['text'] as String,
        if (plaque['card'] != null) plaque['card'] as String,
      ]);
    }
    return secrets;
  }

  /// From now on [owner]'s plaques so far are public: revealed, retired,
  /// swapped out or of a round that is over.
  void opened(String owner) {
    for (final secret in _secrets()[owner] ?? const <String>{}) {
      _openedAt.putIfAbsent((owner, secret), () => call.delivered.length);
    }
  }

  /// How many whole messages the inspection read.
  int inspected = 0;

  /// Every message delivered to a client that tells it what it must not
  /// know: its own plaque's text or card before that became public, a
  /// generator's seed, or a ledger entry of its own with more in it than
  /// the owner may see. Empty when the secret held.
  List<String> leaks() {
    final secrets = _secrets();
    final seeds = {for (final app in apps) '${app.seed}'};
    final assemblers = <String, CallPartAssembler>{};
    final problems = <String>[];
    inspected = 0;
    final delivered = call.delivered;
    for (var i = 0; i < delivered.length; i++) {
      final d = delivered[i];
      final whole = assemblers
          .putIfAbsent(d.to, CallPartAssembler.new)
          .add(d.from, d.message);
      if (whole == null) continue;
      inspected++;
      final text = jsonEncode(whole);
      for (final secret in secrets[d.to] ?? const <String>{}) {
        final opened = _openedAt[(d.to, secret)];
        if ((opened == null || i < opened) && text.contains(secret)) {
          problems.add('${d.to} was sent "$secret" by ${d.from}: $text');
        }
      }
      for (final seed in seeds.where(text.contains)) {
        problems.add('${d.to} was sent the seed $seed by ${d.from}');
      }
      final parts = whole['parts'];
      final ledger = parts is Map ? parts[PlaqueCustody.partKey] : null;
      final own = ledger is Map ? (ledger['of'] as Map)[d.to] : null;
      if (own is Map && (own['s'] == 'pending' || own['s'] == 'dealt')) {
        final extra = own.keys
            .toSet()
            .difference({'v', 's', 'tag', 'kind', 'pool', 'deal'});
        if (extra.isNotEmpty) {
          problems.add('${d.to}\'s own ledger entry carries $extra');
        }
      }
    }
    return problems;
  }
}
