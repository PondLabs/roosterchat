// The plaques of a round of Cock-a-Doodle-Who?, in their two halves: what
// is written on one ([Plaque]), which its owner's client must not receive
// before the reveal, and what everyone may know about it ([PlaqueLedger]),
// the owner included. docs/adr/0007-plaque-secret.md has the why.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:rooster/client/components/cock_a_doodle_who/deck/deck.dart';

T? _byKey<T>(List<T> values, String Function(T) key, Object? wanted) {
  for (final value in values) {
    if (key(value) == wanted) return value;
  }
  return null;
}

PlaqueKind? _kind(Object? key) => _byKey(PlaqueKind.values, (k) => k.key, key);

/// What is written on a plaque: the secret. It travels only in messages
/// addressed to the people who may read it (everyone in the session but the
/// owner) and, once revealed, in the ledger.
class Plaque {
  const Plaque({
    required this.kind,
    required this.text,
    this.caption,
    this.cardId,
    this.author,
  });

  /// The plaque a card of the deck becomes. [text] and [caption] are the
  /// English ones, for a client whose deck does not have the card yet;
  /// everyone else reads the card in their own language ([textIn]).
  Plaque.card(DeckCard card)
      : kind = card.kind,
        text = card.name(deckSourceLanguage),
        caption = card.caption(deckSourceLanguage),
        cardId = card.id,
        author = null;

  static Plaque? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = _kind(json['kind']);
    final text = json['text'];
    if (kind == null || text is! String) return null;
    final caption = json['caption'], card = json['card'], by = json['author'];
    return Plaque(
      kind: kind,
      text: text,
      caption: caption is String ? caption : null,
      cardId: card is String ? card : null,
      author: by is String ? by : null,
    );
  }

  final PlaqueKind kind;

  /// Homemade: what the author wrote. Deck: the card's name in English.
  final String text;

  /// Deck: the line that tells the people answering what the card is.
  final String? caption;

  /// Deck: the card's id in the deck.
  final String? cardId;

  /// Homemade: the call identity of who wrote it.
  final String? author;

  /// What to show in [language]: the card's name when [deck] has the card,
  /// else [text].
  String textIn(Deck deck, String language) =>
      deck.byId(cardId ?? '')?.name(language) ?? text;

  /// The caption to show in [language], when there is one.
  String? captionIn(Deck deck, String language) =>
      deck.byId(cardId ?? '')?.caption(language) ?? caption;

  Map<String, Object?> toJson() => {
        'kind': kind.key,
        'text': text,
        if (caption != null) 'caption': caption,
        if (cardId != null) 'card': cardId,
        if (author != null) 'author': author,
      };
}

/// Where a plaque is in its life.
enum PlaqueState {
  /// Asked for, not there yet: an author is writing it, or a card is being
  /// drawn.
  pending,

  /// On the owner's forehead: everyone but the owner holds it.
  dealt,

  /// Turned: the owner may read it, and the ledger carries it once the host
  /// has it.
  revealed,

  /// Taken off because its owner left; public like a revealed one.
  retired,
}

/// The order for a card of the deck, in a pending entry.
class PlaqueDeal {
  const PlaqueDeal(this.filter, {this.dealer});

  static PlaqueDeal? fromJson(Object? json) {
    if (json is! Map) return null;
    Set<T> read<T>(Object? keys, List<T> values, String Function(T) key) => {
          for (final k in keys is List ? keys : const [])
            if (_byKey(values, key, k) case final value?) value,
        };
    final by = json['by'];
    return PlaqueDeal(
      DeckFilter(
        theme: _byKey(DeckTheme.values, (t) => t.key, json['theme']),
        packs: read(json['packs'], CardReach.values, (r) => r.key),
        difficulties: read(json['levels'], CardDifficulty.values, (d) => d.key),
      ),
      dealer: by is String ? by : null,
    );
  }

  /// Which cards the draw may give.
  final DeckFilter filter;

  /// Who draws it when the host cannot: the host's own card is drawn by
  /// another player. Null while the host draws it itself.
  final String? dealer;

  Map<String, Object?> toJson() => {
        if (dealer != null) 'by': dealer,
        if (filter.theme != null) 'theme': filter.theme!.key,
        'packs': [for (final pack in filter.packs) pack.key],
        'levels': [for (final level in filter.difficulties) level.key],
      };
}

/// What everyone may know about one player's plaque. Nothing here tells the
/// owner what is written: [tag] is a random name, [kind] is what the owner
/// sees on their own video, and [pool] says only which half of the deck the
/// card is in.
class PlaqueEntry {
  const PlaqueEntry({
    required this.version,
    required this.state,
    this.tag,
    this.kind,
    this.pool,
    this.deal,
    this.plaque,
  });

  static PlaqueEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final version = json['v'];
    final state = _byKey(PlaqueState.values, (s) => s.name, json['s']);
    if (version is! int || state == null) return null;
    final tag = json['tag'], pool = json['pool'];
    return PlaqueEntry(
      version: version,
      state: state,
      tag: tag is String ? tag : null,
      kind: _kind(json['kind']),
      pool: pool is int ? pool : null,
      deal: PlaqueDeal.fromJson(json['deal']),
      plaque: Plaque.fromJson(json['plaque']),
    );
  }

  /// Counts the plaques asked for this owner in the round: a swap or a
  /// card dealt after the writing time ran out is the next version, and
  /// what was written for an earlier one is dropped.
  final int version;
  final PlaqueState state;

  /// The random name of the plaque on the forehead: what the holders keep
  /// its content under. Null while pending.
  final String? tag;

  /// The plaque's kind, which its owner sees too.
  final PlaqueKind? kind;

  /// Which half of the deck a card is in, 0 or 1 ([plaquePool]). Null for
  /// a Homemade plaque.
  final int? pool;

  /// The order for a card, while pending. Null when an author writes it.
  final PlaqueDeal? deal;

  /// What is written, once public ([isOpen]) and known to the host.
  final Plaque? plaque;

  /// Whether the plaque is no longer a secret.
  bool get isOpen =>
      state == PlaqueState.revealed || state == PlaqueState.retired;

  Map<String, Object?> toJson() => {
        'v': version,
        's': state.name,
        if (tag != null) 'tag': tag,
        if (kind != null) 'kind': kind!.key,
        if (pool != null) 'pool': pool,
        if (deal != null) 'deal': deal!.toJson(),
        if (plaque != null) 'plaque': plaque!.toJson(),
      };
}

/// The public record of a round's plaques, kept by the host and sent to
/// everyone in the session's state. The collections are the custody's to
/// change; read them, do not write them.
class PlaqueLedger {
  PlaqueLedger({
    this.round = 0,
    this.salt = '',
    Set<String>? used,
    Set<String>? owed,
    Map<String, PlaqueEntry>? entries,
  })  : used = used ?? {},
        owed = owed ?? {},
        entries = entries ?? {};

  factory PlaqueLedger.fromJson(Map<String, Object?> json) {
    Set<String> strings(Object? list) => {
          for (final e in list is List ? list : const [])
            if (e is String) e
        };
    final round = json['round'], salt = json['salt'], of = json['of'];
    return PlaqueLedger(
      round: round is int ? round : 0,
      salt: salt is String ? salt : '',
      used: strings(json['used']),
      owed: strings(json['owed']),
      entries: {
        for (final MapEntry(:key, :value)
            in (of is Map ? of : const {}).entries)
          if (PlaqueEntry.fromJson(value) case final entry? when key is String)
            key: entry,
      },
    );
  }

  /// Counts the rounds of the session, from 1.
  final int round;

  /// Splits the deck in two for this round ([plaquePool]).
  final String salt;

  /// The ids of the cards the session has spent: revealed, retired or
  /// swapped out. No draw gives them again.
  final Set<String> used;

  /// The tags of cards that left play before the host learned them (its
  /// own, swapped out or carried over a round): whoever holds one sends it
  /// to the host, which adds it to [used].
  final Set<String> owed;

  /// Each owner's plaque, by call identity.
  final Map<String, PlaqueEntry> entries;

  /// Whether the plaque named [tag] is public: its owner may be sent it.
  bool isOpen(String tag) =>
      owed.contains(tag) ||
      entries.values.any((entry) => entry.tag == tag && entry.isOpen);

  Map<String, Object?> toJson() => {
        'round': round,
        'salt': salt,
        'used': used.toList(),
        if (owed.isNotEmpty) 'owed': owed.toList(),
        'of': {
          for (final MapEntry(:key, :value) in entries.entries)
            key: value.toJson(),
        },
      };
}

/// Which half of the deck [cardId] is in for the round with [salt]: 0 or 1,
/// the same on every client. Whoever draws a card takes it from the half
/// their own card is not in, so they cannot draw the one card they do not
/// see. A hash and not the card's position, so that the halves change every
/// round and say nothing else about a card.
int plaquePool(String salt, String cardId) =>
    sha256.convert(utf8.encode('$salt\n$cardId')).bytes.first & 1;
