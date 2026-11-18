@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';

import 'fake_account.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the app\'s own client records its requests in the speed log', () async {
    SpeedLog.instance.requests.clear();
    final transport = FakeTransport();
    // Built as the app builds an account: MatrixClient makes the SDK client.
    final client = await fakeAccount('app_client_speed_log_test', transport);
    addTearDown(client.close);

    expect(transport.seen, contains('POST /_matrix/client/v3/login'));
    final login = SpeedLog.instance.requests.toList().where(
        (r) => r.method == 'POST' && r.route == '/_matrix/client/v3/login');
    expect(login, hasLength(1),
        reason: 'the login reached the server without passing through '
            'SpeedHttpClient');
    expect(login.single.status, 200);
    expect(login.single.hostClass, HostClass.homeserver);
  });
}
