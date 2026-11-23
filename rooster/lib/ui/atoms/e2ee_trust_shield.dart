import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// How far the user can trust someone's end-to-end encryption keys, or a
/// whole encrypted room's.
enum E2eeTrust {
  /// Their identity (cross-signing master key) is verified, and so is
  /// every one of their devices.
  verified,

  /// Not verified yet, or one of their devices is not.
  unverified,

  /// The identity the user once verified was replaced by another: the
  /// critical alert. Someone may be posing as them.
  identityChanged,
}

/// A shield telling the [E2eeTrust] apart three ways: its icon (a check, a
/// plain outline, a cross), its color, and a label read out by screen
/// readers (and shown next to it with [showLabel]).
class E2eeTrustShield extends StatelessWidget {
  const E2eeTrustShield(this.trust,
      {this.size = 16, this.showLabel = false, this.label, super.key});

  final E2eeTrust trust;
  final double size;
  final bool showLabel;

  /// Words in place of [labelOf], for a thing the shield is about (such as
  /// a session) whose words differ in some languages.
  final String? label;

  static String get labelE2eeTrustVerified => Intl.message("Verified",
      name: "labelE2eeTrustVerified",
      desc: "Next to a shield icon: this user's (or every member's) "
          "encryption identity and devices are verified");

  static String get labelE2eeTrustUnverified => Intl.message("Not verified",
      name: "labelE2eeTrustUnverified",
      desc: "Next to a shield icon: this user's (or a member's) encryption "
          "identity or one of their devices is not verified");

  static String get labelE2eeTrustIdentityChanged =>
      Intl.message("Identity changed",
          name: "labelE2eeTrustIdentityChanged",
          desc: "Next to a red shield icon: the encryption identity of a "
              "user the user had verified was replaced by a new one");

  static String get tooltipE2eeTrustVerified =>
      Intl.message("Encrypted, and verified: you know these keys are theirs",
          name: "tooltipE2eeTrustVerified",
          desc: "Tooltip of the green shield of a verified user or room");

  static String get tooltipE2eeTrustUnverified => Intl.message(
      "Encrypted, but not verified: verify to make sure no one else "
      "reads along",
      name: "tooltipE2eeTrustUnverified",
      desc: "Tooltip of the grey shield of a user or room not verified yet");

  static String get tooltipE2eeTrustIdentityChanged => Intl.message(
      "Their identity changed since you verified them. Verify them again "
      "before you trust their messages",
      name: "tooltipE2eeTrustIdentityChanged",
      desc: "Tooltip of the red shield shown when a verified user's "
          "encryption identity was replaced");

  /// The words for [trust], as shown and as read out.
  static String labelOf(E2eeTrust trust) => switch (trust) {
        E2eeTrust.verified => labelE2eeTrustVerified,
        E2eeTrust.unverified => labelE2eeTrustUnverified,
        E2eeTrust.identityChanged => labelE2eeTrustIdentityChanged,
      };

  static String tooltipOf(E2eeTrust trust) => switch (trust) {
        E2eeTrust.verified => tooltipE2eeTrustVerified,
        E2eeTrust.unverified => tooltipE2eeTrustUnverified,
        E2eeTrust.identityChanged => tooltipE2eeTrustIdentityChanged,
      };

  static IconData iconOf(E2eeTrust trust) => switch (trust) {
        E2eeTrust.verified => Icons.verified_user,
        E2eeTrust.unverified => Icons.shield_outlined,
        E2eeTrust.identityChanged => Icons.gpp_bad,
      };

  static Color colorOf(BuildContext context, E2eeTrust trust) {
    final scheme = Theme.of(context).colorScheme;
    return switch (trust) {
      E2eeTrust.verified => Colors.green.shade600,
      E2eeTrust.unverified => scheme.onSurfaceVariant,
      E2eeTrust.identityChanged => scheme.error,
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = colorOf(context, trust);
    final label = this.label ?? labelOf(trust);
    Widget result = Icon(iconOf(trust), size: size, color: color);

    if (showLabel) {
      result = Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          result,
          Flexible(
            child: tiamat.Text.labelLow(label,
                color: color, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      );
    }

    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: tiamat.Tooltip(text: tooltipOf(trust), child: result),
    );
  }
}
