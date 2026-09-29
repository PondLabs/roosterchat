import 'package:cockhouse/main.dart';
import 'package:cockhouse/ui/pages/settings/categories/about/settings_category_about.dart';
import 'package:cockhouse/ui/pages/settings/settings_page.dart';
import 'package:flutter/widgets.dart';

import 'categories/account/settings_category_account.dart';
import 'categories/app/settings_category_app.dart';

class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsPage(settings: [
      if (clientManager!.clients.isNotEmpty) SettingsCategoryAccount(),
      SettingsCategoryApp(),
      SettingsCategoryAbout(),
    ]);
  }
}
