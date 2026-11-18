/// The Home screen itself shows the notice that this device is not
/// verified as soon as it is added, and drops it as soon as it goes,
/// without waiting for a sync to redraw it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/alert.dart';
import 'package:rooster/client/client_manager.dart';
import 'package:rooster/client/matrix/components/key_verification_component/matrix_key_verification_component.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/organisms/home_screen/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

void main() {
  testWidgets(
      'the Home screen shows the notice when it is added and drops it when '
      'it goes, with no sync', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await preferences.init();
      // No release check leaves the test.
      await preferences.checkForUpdates.set(false);
    });
    final manager = clientManager = ClientManager();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      theme: ThemeDark.theme,
      home: Scaffold(body: HomeScreen(clientManager: manager)),
    ));
    await tester.pump();
    final notice =
        find.text(MatrixKeyVerificationComponent.labelDeviceNotVerified);
    expect(notice, findsNothing);

    // As the verification component adds it.
    final alert = Alert(AlertType.warning,
        titleGetter: () =>
            MatrixKeyVerificationComponent.labelDeviceNotVerified,
        messageGetter: () =>
            MatrixKeyVerificationComponent.messageDeviceNotVerified);
    manager.alertManager.addAlert(alert);
    await tester.pump();
    expect(notice, findsOneWidget);

    manager.alertManager.clearAlert(alert);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(notice, findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
