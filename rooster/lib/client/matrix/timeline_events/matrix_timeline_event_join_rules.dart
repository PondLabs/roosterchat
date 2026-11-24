import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_state.dart';
import 'package:rooster/client/timeline.dart';

/// `m.room.join_rules`: who can join the room changed.
class MatrixTimelineEventJoinRules extends MatrixTimelineEventState {
  MatrixTimelineEventJoinRules(super.event, {required super.client});

  static String messageJoinRulePublic(String user) =>
      Intl.message("$user made the room public: anyone can join",
          name: "messageJoinRulePublic",
          args: [user],
          desc: "Timeline line for when someone sets the room's join rule "
              "to public");

  static String messageJoinRuleInvite(String user) =>
      Intl.message("$user made the room invite only",
          name: "messageJoinRuleInvite",
          args: [user],
          desc: "Timeline line for when someone sets the room so that only "
              "people invited can join");

  static String messageJoinRuleKnock(String user) =>
      Intl.message("$user let people ask to join the room",
          name: "messageJoinRuleKnock",
          args: [user],
          desc: "Timeline line for when someone sets the room so that "
              "anyone can ask to join (Matrix calls it knocking) and must be "
              "let in");

  static String messageJoinRuleRestricted(String user) =>
      Intl.message("$user let members of certain spaces join the room",
          name: "messageJoinRuleRestricted",
          args: [user],
          desc: "Timeline line for when someone sets the room so that "
              "members of the spaces or rooms it lists can join (the "
              "restricted join rule)");

  static String messageJoinRuleKnockRestricted(String user) => Intl.message(
      "$user let members of certain spaces join the room, and others ask "
      "to join",
      name: "messageJoinRuleKnockRestricted",
      args: [user],
      desc: "Timeline line for the knock_restricted join rule: members of "
          "the spaces or rooms it lists can join, anyone else can ask to "
          "join");

  static String messageJoinRuleChanged(String user) =>
      Intl.message("$user changed who can join the room",
          name: "messageJoinRuleChanged",
          args: [user],
          desc: "Timeline line for a change to the room's join rule that "
              "the app cannot describe (unknown or missing)");

  String? get joinRule => contentString('join_rule');

  @override
  IconData get icon => Icons.door_front_door_outlined;

  @override
  String getBody({Timeline? timeline}) {
    final user = senderName(timeline: timeline);
    return switch (joinRule) {
      'public' => messageJoinRulePublic(user),
      // `private` is reserved by the spec and behaves as invite only.
      'invite' || 'private' => messageJoinRuleInvite(user),
      'knock' => messageJoinRuleKnock(user),
      'restricted' => messageJoinRuleRestricted(user),
      'knock_restricted' => messageJoinRuleKnockRestricted(user),
      _ => messageJoinRuleChanged(user),
    };
  }
}
