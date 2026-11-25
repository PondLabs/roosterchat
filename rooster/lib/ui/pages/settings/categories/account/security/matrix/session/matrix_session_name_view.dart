import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// What the person chose for a session's name: [name], or no name at all
/// when it is null.
class SessionNameChoice {
  const SessionNameChoice(this.name);

  final String? name;
}

/// Asks for a session's new name, or for none, which clears it.
class MatrixSessionNameView extends StatefulWidget {
  const MatrixSessionNameView({this.currentName, super.key});

  final String? currentName;

  static String get labelSessionRenameTitle => Intl.message("Rename session",
      name: "labelSessionRenameTitle",
      desc: "Settings > Security > Sessions: title of the dialog that "
          "changes the name of one of your sessions (signed-in devices)");

  static String get labelSessionName => Intl.message("Session name",
      name: "labelSessionName",
      desc: "Settings > Security > Sessions: label of the field with the "
          "session's new name");

  static String get messageSessionNameVisible =>
      Intl.message("People you talk with can see the names of your sessions.",
          name: "messageSessionNameVisible",
          desc: "Settings > Security > Sessions: in the rename dialog, warns "
              "that session names are public to other users");

  static String get promptSessionNameRemove => Intl.message("Remove name",
      name: "promptSessionNameRemove",
      desc: "Settings > Security > Sessions: button that clears the session's "
          "name, so it has none");

  static String get messageSessionRenameFailed =>
      Intl.message("The session's name was not changed. Try again.",
          name: "messageSessionRenameFailed",
          desc: "Settings > Security > Sessions: renaming a session, or "
              "removing its name, failed; the name stays as it was");

  @override
  State<MatrixSessionNameView> createState() => _MatrixSessionNameViewState();
}

class _MatrixSessionNameViewState extends State<MatrixSessionNameView> {
  late final controller = TextEditingController(text: widget.currentName);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  String get name => controller.text.trim();

  void save() {
    if (name.isEmpty) return;
    Navigator.pop(context, SessionNameChoice(name));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          tiamat.Text.label(MatrixSessionNameView.labelSessionName),
          tiamat.TextInput(
            key: const ValueKey('session-name'),
            controller: controller,
            maxLines: 1,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => save(),
          ),
          tiamat.Text.labelLow(MatrixSessionNameView.messageSessionNameVisible),
          tiamat.Button(
              text: CommonStrings.promptSave,
              onTap: name.isEmpty ? null : save),
          if (widget.currentName != null)
            tiamat.Button.secondary(
                text: MatrixSessionNameView.promptSessionNameRemove,
                onTap: () =>
                    Navigator.pop(context, const SessionNameChoice(null))),
          tiamat.Button.secondary(
              text: CommonStrings.promptCancel,
              onTap: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}
