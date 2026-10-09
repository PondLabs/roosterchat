import 'package:rooster/client/role.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MatrixRole implements Role {
  int powerLevel;
  late int rank;

  /// A name of its own, instead of the one its rank has.
  final String? _nameOverride;

  MatrixRole(this.powerLevel, {String? nameOverride, IconData? iconOverride})
      : _nameOverride = nameOverride {
    if (powerLevel >= 150) {
      rank = 150;
      icon = Icons.local_police;
    } else if (powerLevel >= 100) {
      rank = 100;
      icon = Icons.security;
    } else if (powerLevel >= 50) {
      rank = 50;
      icon = Icons.shield_rounded;
    } else {
      icon = Icons.groups;
      rank = 0;
    }

    if (iconOverride != null) {
      icon = iconOverride;
    }
  }

  static String get labelRoomRoleOwner => Intl.message("Owner",
      name: "labelRoomRoleOwner",
      desc:
          "Role of someone in a room or space (shown next to their name): one of its creators, above the admins");

  static String get labelRoomRoleAdmin => Intl.message("Admin",
      name: "labelRoomRoleAdmin",
      desc:
          "Role of someone in a room or space (shown next to their name): an administrator");

  static String get labelRoomRoleModerator => Intl.message("Moderator",
      name: "labelRoomRoleModerator",
      desc:
          "Role of someone in a room or space (shown next to their name): a moderator");

  static String get labelRoomRoleMember => Intl.message("Member",
      name: "labelRoomRoleMember",
      desc:
          "Role of someone in a room or space (shown next to their name): an ordinary member");

  static String get labelCalendarRoleModerator => Intl.message(
        "Calendar Moderator",
        name: "labelCalendarRoleModerator",
        desc:
            "A role in a calendar room: people who may edit the calendar's events, between moderator and member",
      );

  /// The role's name, in the app's language as it is now.
  @override
  String get name =>
      _nameOverride ??
      switch (rank) {
        150 => labelRoomRoleOwner,
        100 => labelRoomRoleAdmin,
        50 => labelRoomRoleModerator,
        _ => labelRoomRoleMember,
      };

  @override
  bool operator ==(Object other) {
    if (other is! MatrixRole) return false;
    if (identical(this, other)) return true;
    return rank == other.rank;
  }

  @override
  int get hashCode => powerLevel.hashCode;

  @override
  late IconData icon;
}
