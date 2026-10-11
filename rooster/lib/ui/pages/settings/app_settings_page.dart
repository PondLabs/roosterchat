import 'package:rooster/client/client.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/pages/settings/categories/about/settings_category_about.dart';
import 'package:rooster/ui/pages/settings/settings_page.dart';
import 'package:flutter/widgets.dart';

import 'categories/account/settings_category_account.dart';
import 'categories/app/settings_category_app.dart';

class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({super.key, this.editProfileOf});

  /// Opens on Account > Profile, with this account selected.
  final Client? editProfileOf;

  @override
  Widget build(BuildContext context) {
    final hasAccounts = clientManager!.clients.isNotEmpty;
    final account = SettingsCategoryAccount(editProfileOf: editProfileOf);
    return SettingsPage(
      settings: [
        if (hasAccounts) account,
        SettingsCategoryApp(),
        SettingsCategoryAbout(),
      ],
      initialTab: editProfileOf != null && hasAccounts
          ? (
              0,
              account.tabs
                  .indexWhere((t) => t.label == account.labelSettingsTabProfile)
            )
          : null,
    );
  }
}
