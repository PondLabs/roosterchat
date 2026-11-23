import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/components/social_admin/matrix_account_restriction.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Says that the account is locked or suspended, while it is, with a button
/// to try its sync again now.
class AccountRestrictionBanner extends StatelessWidget {
  const AccountRestrictionBanner(this.watcher,
      {required this.account, super.key});

  final AccountRestrictionWatcher watcher;

  /// The account's Matrix ID, named in the explanation.
  final String account;

  static const checkAgainKey = ValueKey('account-restriction-check-again');

  static String get promptAccountRestrictionCheckAgain =>
      Intl.message("Check again",
          name: "promptAccountRestrictionCheckAgain",
          desc: "Button on the banner of a locked or suspended account: asks "
              "the server again now whether the account works");

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AccountRestriction?>(
      valueListenable: watcher.restriction,
      builder: (context, restriction, _) {
        if (restriction == null) return const SizedBox.shrink();
        final colors = Theme.of(context).colorScheme;
        return Card(
          color: colors.errorContainer,
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Row(spacing: 8, children: [
                  Icon(Icons.lock_person, color: colors.onErrorContainer),
                  Expanded(
                      child: tiamat.Text.labelEmphasised(
                          MatrixAccountRestrictionComponent.titleOf(
                              restriction))),
                ]),
                tiamat.Text.label(MatrixAccountRestrictionComponent.messageOf(
                    restriction, account)),
                tiamat.Button.secondary(
                  key: checkAgainKey,
                  text: promptAccountRestrictionCheckAgain,
                  onTap: watcher.checkAgain,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
