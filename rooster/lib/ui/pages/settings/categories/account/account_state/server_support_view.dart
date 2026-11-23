import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/components/social_admin/matrix_server_support.dart';
import 'package:rooster/utils/links/link_utils.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:url_launcher/url_launcher.dart';

/// Who runs the account's server and how to reach them, from its
/// `/.well-known/matrix/support`. Shows nothing when there is none.
class ServerSupportView extends StatefulWidget {
  const ServerSupportView(this.load, {this.openLink, super.key});

  final Future<ServerSupportInfo?> Function() load;

  /// Opens a contact's `mailto:` or the `https:` help page; tests replace it.
  final void Function(BuildContext context, Uri link)? openLink;

  static const pageKey = ValueKey('server-support-page');
  static ValueKey<String> emailKey(String email) =>
      ValueKey('server-support-email-$email');

  static String get labelServerSupportHeader => Intl.message("Server support",
      name: "labelServerSupportHeader",
      desc: "Header of the section of account settings with the contacts "
          "and help page the user's homeserver publishes");

  static String get labelServerSupportAdmin => Intl.message("Administrator",
      name: "labelServerSupportAdmin",
      desc: "Role of a contact of the homeserver: the people who run it "
          "(Matrix role m.role.admin)");

  static String get labelServerSupportSecurity =>
      Intl.message("Security contact",
          name: "labelServerSupportSecurity",
          desc: "Role of a contact of the homeserver: for security reports "
              "(Matrix role m.role.security)");

  static String promptServerSupportPage(String host) =>
      Intl.message("Open the help page on $host",
          name: "promptServerSupportPage",
          args: [host],
          desc: "Button that opens the homeserver's own help page in the "
              "browser; host is the web address it is on");

  @override
  State<ServerSupportView> createState() => _ServerSupportViewState();
}

class _ServerSupportViewState extends State<ServerSupportView> {
  late final Future<ServerSupportInfo?> info = widget.load();

  void open(Uri link) {
    final custom = widget.openLink;
    if (custom != null) return custom(context, link);
    if (link.scheme == 'mailto') {
      launchUrl(link);
    } else {
      LinkUtils.open(link, context: context);
    }
  }

  String roleName(String role) => switch (role) {
        MatrixServerSupport.roleAdmin =>
          ServerSupportView.labelServerSupportAdmin,
        MatrixServerSupport.roleSecurity =>
          ServerSupportView.labelServerSupportSecurity,
        // Not translated: a role the server names itself.
        _ => role,
      };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ServerSupportInfo?>(
      future: info,
      builder: (context, snapshot) {
        final support = snapshot.data;
        if (support == null) return const SizedBox.shrink();
        final page = support.supportPage;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: tiamat.Panel(
            mode: tiamat.TileType.surfaceContainerLow,
            header: ServerSupportView.labelServerSupportHeader,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                for (final contact in support.contacts)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      tiamat.Text.labelEmphasised(roleName(contact.role)),
                      if (contact.matrixId != null)
                        SelectableText(contact.matrixId!),
                      if (contact.emailLink != null)
                        InkWell(
                          key: ServerSupportView.emailKey(contact.email!),
                          onTap: () => open(contact.emailLink!),
                          child: tiamat.Text.label(contact.email!),
                        ),
                    ],
                  ),
                if (page != null)
                  tiamat.Button.secondary(
                    key: ServerSupportView.pageKey,
                    text: ServerSupportView.promptServerSupportPage(page.host),
                    onTap: () => open(page),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
