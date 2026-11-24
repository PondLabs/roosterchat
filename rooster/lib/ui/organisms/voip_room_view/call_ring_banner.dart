import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/components/voip_room/call_ring.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Someone is ringing us to this channel's call (MSC4075): who, with Join
/// and Decline (MSC4310). Nothing while nobody rings. The same on the web.
class CallRingBanner extends StatelessWidget {
  const CallRingBanner(
      {required this.rings,
      required this.nameOf,
      required this.onJoin,
      super.key});

  final CallRings rings;

  /// The display name of a user id.
  final String Function(String userId) nameOf;

  final VoidCallback onJoin;

  static String labelCallRinging(String name) =>
      Intl.message("$name is calling",
          name: "labelCallRinging",
          args: [name],
          desc: "Shown on a voice channel's page while someone rings us to "
              "its call, beside the Join and Decline buttons. The name is "
              "the person ringing");

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CallRing?>(
      valueListenable: rings.ringing,
      builder: (context, ring, _) {
        if (ring == null) return const SizedBox.shrink();
        return Padding(
          key: const ValueKey("callRingBanner"),
          padding: const EdgeInsets.all(8),
          child: tiamat.Tile.surfaceContainer(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  const Icon(Icons.ring_volume),
                  tiamat.Text.label(labelCallRinging(nameOf(ring.senderId))),
                  tiamat.Button.success(
                      text: CommonStrings.promptJoin, onTap: onJoin),
                  tiamat.Button.danger(
                      text: CommonStrings.promptDecline, onTap: rings.decline),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
