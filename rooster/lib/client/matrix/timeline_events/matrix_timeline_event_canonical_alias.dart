import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_state.dart';
import 'package:rooster/client/timeline.dart';

/// `m.room.canonical_alias`: the room's main address, or its other
/// addresses, changed.
class MatrixTimelineEventCanonicalAlias extends MatrixTimelineEventState {
  MatrixTimelineEventCanonicalAlias(super.event, {required super.client});

  static String messageCanonicalAliasSet(String user, String address) =>
      Intl.message("$user set the main address of the room to $address",
          name: "messageCanonicalAliasSet",
          args: [user, address],
          desc: "Timeline line for when someone sets the room's main "
              "address (Matrix calls it the canonical alias, like "
              "#room:example.org), with the address");

  static String messageCanonicalAliasRemoved(String user) =>
      Intl.message("$user removed the main address of the room",
          name: "messageCanonicalAliasRemoved",
          args: [user],
          desc: "Timeline line for when someone clears the room's main "
              "address (canonical alias)");

  static String messageAltAliasesChanged(String user) =>
      Intl.message("$user changed the other addresses of the room",
          name: "messageAltAliasesChanged",
          args: [user],
          desc: "Timeline line for when someone changes the room's "
              "alternative addresses (alt_aliases) and not its main one");

  /// An address is `#localpart:server`.
  static String? _alias(Object? value) {
    final alias = MatrixTimelineEventState.nonEmptyString(value);
    return alias != null && alias.startsWith('#') ? alias : null;
  }

  String? get alias => _alias(event.content['alias']);

  String? get previousAlias => _alias(event.prevContent?['alias']);

  @override
  IconData get icon => Icons.alternate_email;

  @override
  String getBody({Timeline? timeline}) {
    final user = senderName(timeline: timeline);
    final alias = this.alias;
    final previous = previousAlias;
    if (alias != null && alias != previous) {
      return messageCanonicalAliasSet(user, alias);
    }
    if (alias == null && previous != null) {
      return messageCanonicalAliasRemoved(user);
    }
    if (alias != null || event.content['alt_aliases'] is List) {
      return messageAltAliasesChanged(user);
    }
    return messageCanonicalAliasRemoved(user);
  }
}
