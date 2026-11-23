import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/reporting/matrix_ignored_users.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/organisms/moderation/ignore_user_actions.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Settings > Account > Preferences: the people the user ignores, a button
/// to stop ignoring each, and a field to ignore someone by Matrix ID.
class IgnoredUsersPreferences extends StatefulWidget {
  const IgnoredUsersPreferences({required this.client, super.key});

  final matrix.Client client;

  static const idFieldKey = ValueKey('ignore_user_id');
  static const ignoreKey = ValueKey('ignore_user_add');

  static String get labelIgnoredUsersTitle => Intl.message("Ignored Users",
      name: "labelIgnoredUsersTitle",
      desc: "Header of the settings section listing the users the user "
          "ignores");

  static String get labelIgnoredUsersDescription => Intl.message(
      "You do not see messages or invites from the people you ignore.",
      name: "labelIgnoredUsersDescription",
      desc: "Under the header of the ignored users section in settings");

  static String get labelIgnoredUsersEmpty => Intl.message(
      "You are not ignoring anyone.",
      name: "labelIgnoredUsersEmpty",
      desc: "In the ignored users section of settings when the list is empty");

  static String get hintIgnoreUserId =>
      Intl.message("Matrix ID of someone to ignore",
          name: "hintIgnoreUserId",
          desc: "Placeholder of the field in settings where the user types the "
              "Matrix ID of someone to ignore");

  @override
  State<IgnoredUsersPreferences> createState() =>
      _IgnoredUsersPreferencesState();
}

class _IgnoredUsersPreferencesState extends State<IgnoredUsersPreferences> {
  late final MatrixIgnoredUsers ignored = MatrixIgnoredUsers.of(widget.client);
  late final StreamSubscription<Set<String>> changed;
  final id = TextEditingController();
  String? error;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    changed = ignored.onChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    changed.cancel();
    id.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await action();
    } catch (e, s) {
      Log.onError(e, s, content: "Could not change the ignore list");
      error = IgnoreUserActions.errorOf(e);
    }
    if (mounted) setState(() => saving = false);
  }

  Future<void> ignore() => run(() async {
        await ignored.ignore(id.text.trim());
        id.clear();
      });

  @override
  Widget build(BuildContext context) {
    final users = ignored.users;
    return tiamat.Panel(
      header: IgnoredUsersPreferences.labelIgnoredUsersTitle,
      mode: tiamat.TileType.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          tiamat.Text.labelLow(
              IgnoredUsersPreferences.labelIgnoredUsersDescription),
          if (users.isEmpty)
            tiamat.Text.body(IgnoredUsersPreferences.labelIgnoredUsersEmpty),
          for (final user in users)
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: tiamat.Text.body(user,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                tiamat.Button.secondary(
                  key: ValueKey('unignore_$user'),
                  text: IgnoreUserActions.promptUnignoreUser,
                  onTap:
                      saving ? null : () => run(() => ignored.unignore(user)),
                ),
              ],
            ),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: TextField(
                  key: IgnoredUsersPreferences.idFieldKey,
                  controller: id,
                  decoration: InputDecoration(
                      hintText: IgnoredUsersPreferences.hintIgnoreUserId),
                  onSubmitted: (_) => ignore(),
                ),
              ),
              tiamat.Button.danger(
                key: IgnoredUsersPreferences.ignoreKey,
                text: IgnoreUserActions.promptIgnoreUser,
                isLoading: saving,
                onTap: saving ? null : ignore,
              ),
            ],
          ),
          if (error != null)
            Text(error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ),
    );
  }
}
