// MSC4191: the links to the account page of a server on OAuth 2.0, one per
// action it announces in `account_management_actions_supported`, with the
// session's `device_id` where the action is about one; nothing for the
// actions it does not announce.

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/matrix/auth/matrix_account_lifecycle.dart';

void main() {
  final page = Uri.parse('https://account.example.org/manage?lang=pt');
  const all = [
    AccountManagementActions.profile,
    AccountManagementActions.sessionsList,
    AccountManagementActions.sessionView,
    AccountManagementActions.sessionEnd,
    AccountManagementActions.accountDeactivate,
    AccountManagementActions.crossSigningReset,
  ];

  String? link(List<String>? supported, String? action, {String? deviceId}) =>
      accountManagementLink(page, supported, action: action, deviceId: deviceId)
          ?.toString();

  test('every announced action, with its exact query', () {
    expect(link(all, 'org.matrix.profile'),
        'https://account.example.org/manage?lang=pt&action=org.matrix.profile');
    expect(link(all, 'org.matrix.sessions_list'),
        'https://account.example.org/manage?lang=pt&action=org.matrix.sessions_list');
    expect(link(all, 'org.matrix.account_deactivate'),
        'https://account.example.org/manage?lang=pt&action=org.matrix.account_deactivate');
    expect(link(all, 'org.matrix.cross_signing_reset'),
        'https://account.example.org/manage?lang=pt&action=org.matrix.cross_signing_reset');
  });

  test('session_view and session_end carry the device_id', () {
    expect(link(all, 'org.matrix.session_view', deviceId: 'ABC DEF'),
        'https://account.example.org/manage?lang=pt&action=org.matrix.session_view&device_id=ABC+DEF');
    expect(link(all, 'org.matrix.session_end', deviceId: 'QWERTY'),
        'https://account.example.org/manage?lang=pt&action=org.matrix.session_end&device_id=QWERTY');
    // Without a session there is no link to one.
    expect(link(all, 'org.matrix.session_end'), isNull);
    expect(link(all, 'org.matrix.session_view', deviceId: ''), isNull);
  });

  test('an action not announced gives no link', () {
    for (final action in all) {
      final others = all.where((a) => a != action).toList();
      expect(link(others, action, deviceId: 'QWERTY'), isNull, reason: action);
    }
    expect(link(null, 'org.matrix.profile'), isNull);
    expect(link(const [], 'org.matrix.profile'), isNull);
  });

  test('the page itself needs no action announced', () {
    expect(link(null, null), page.toString());
  });

  test(
      'older names of the session actions are used when only they are '
      'announced', () {
    expect(
        link(const ['org.matrix.device_delete'], 'org.matrix.session_end',
            deviceId: 'QWERTY'),
        'https://account.example.org/manage?lang=pt&action=org.matrix.device_delete&device_id=QWERTY');
    expect(link(const ['org.matrix.devices_list'], 'org.matrix.sessions_list'),
        'https://account.example.org/manage?lang=pt&action=org.matrix.devices_list');
  });

  test('no page, or a page that is not on the web: no link', () {
    expect(
        accountManagementLink(null, all, action: 'org.matrix.profile'), isNull);
    expect(
        accountManagementLink(Uri.parse('javascript:alert(1)'), all,
            action: 'org.matrix.profile'),
        isNull);
  });
}
