import 'package:flutter_test/flutter_test.dart';

import 'oidc_fakes.dart';

void main() {
  // CI runs without VODOZEMAC_LIB_DIR: a `setUpAll(initVodozemac)` must not
  // fail the file whose tests are skipped then.
  test('without VODOZEMAC_LIB_DIR, initVodozemac does nothing', () async {
    await expectLater(initVodozemac(environment: const {}), completes);
  });
}
