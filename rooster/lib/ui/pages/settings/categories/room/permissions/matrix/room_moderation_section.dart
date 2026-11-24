import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/moderation/matrix_policy_server.dart';
import 'package:rooster/client/matrix/components/moderation/matrix_room_moderation.dart';
import 'package:rooster/client/matrix/components/moderation/matrix_server_acl.dart';
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/organisms/moderation/banned_members_view.dart';
import 'package:rooster/ui/organisms/moderation/policy_server_view.dart';
import 'package:rooster/ui/organisms/moderation/server_acl_editor.dart';

/// The moderation screens a room's permissions page opens: only those our
/// power level lets us use are shown.
class RoomModerationSection extends StatelessWidget {
  const RoomModerationSection(this.room, {super.key});

  final matrix.Room room;

  static const bannedKey = ValueKey('moderation_banned');
  static const serverAclKey = ValueKey('moderation_server_acl');
  static const policyServerKey = ValueKey('moderation_policy_server');

  static String get labelRoomModeration => Intl.message("Moderation",
      name: "labelRoomModeration",
      desc: "Heading of the moderation tools in a room's permission settings");

  Future<void> open(BuildContext context, String title, Widget child) =>
      AdaptiveDialog.show(context,
          title: title,
          builder: (context) => SizedBox(
              width: MediaQuery.sizeOf(context).desktop ? 560 : null,
              child: child));

  @override
  Widget build(BuildContext context) {
    final moderation = MatrixRoomModeration(room);
    if (!moderation.canModerate) return const SizedBox.shrink();

    Widget entry(
            Key key, IconData icon, String title, Widget Function() view) =>
        ListTile(
          key: key,
          leading: Icon(icon),
          title: Text(title),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => open(context, title, view()),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(labelRoomModeration,
              style: Theme.of(context).textTheme.titleSmall),
        ),
        if (moderation.canBan)
          entry(bannedKey, Icons.block, BannedMembersView.labelBannedMembers,
              () => BannedMembersView(moderation)),
        if (moderation.canEditServerAcl)
          entry(serverAclKey, Icons.dns, ServerAclEditor.labelServerAcl,
              () => ServerAclEditor(MatrixServerAcl(room))),
        if (moderation.canEditPolicyServer)
          entry(
              policyServerKey,
              Icons.policy,
              PolicyServerView.labelPolicyServer,
              () => PolicyServerView(MatrixPolicyServer(room))),
        const Divider(),
      ],
    );
  }
}
