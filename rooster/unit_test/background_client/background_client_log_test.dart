@TestOn('vm')
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';
import 'package:rooster/client/matrix_background/matrix_background_client.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Android background client reads the stored account (its tokens and
/// encryption account among it) and logs none of its values.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Each value of the stored account, marked so it can be found anywhere.
  const homeserver = 'https://homeserver-mark-h7.example';
  const token = 'access-token-mark-t7';
  const refreshToken = 'refresh-token-mark-r7';
  const userId = '@user-mark-u7:example.org';
  const deviceId = 'DEVICE-MARK-D7';
  const deviceName = 'device-name-mark-n7';
  const prevBatch = 'prev-batch-mark-p7';
  const olmAccount = 'olm-account-mark-o7';
  const oidcClientId = 'oidc-client-mark-c7';
  const marks = {
    'homeserver_url': homeserver,
    'token': token,
    'refresh_token': refreshToken,
    'user_id': userId,
    'device_id': deviceId,
    'device_name': deviceName,
    'prev_batch': prevBatch,
    'olm_account': olmAccount,
    'oidc_client_id': oidcClientId,
  };

  test('opening the client logs none of the stored account\'s values',
      () async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();

    final database = await MatrixSdkDriftDatabase.init(
        NativeDatabase.memory(), 'background_log');
    addTearDown(database.db.close);
    await database.insertClient(
        'background_log',
        homeserver,
        token,
        null,
        refreshToken,
        userId,
        deviceId,
        deviceName,
        prevBatch,
        olmAccount,
        oidcClientId);

    Log.log.clear();
    final printed = <String>[];
    final client = MatrixBackgroundClient(
        databaseId: 'background_log', openDatabase: () async => database);
    await runZoned(
      () => client.init(true, isBackgroundService: true),
      zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line)),
    );

    // The account was read: the client uses its token.
    expect(client.api.accessToken, token);
    expect(client.deviceId, deviceId);

    final logged = [...Log.log.map((e) => e.rawContent), ...printed];
    expect(logged, isNotEmpty, reason: 'the client logs as it opens');
    for (final MapEntry(key: field, value: mark) in marks.entries) {
      expect(logged.where((line) => line.contains(mark)), isEmpty,
          reason: 'the account\'s $field reached the log');
    }
  });
}
