import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/auth/matrix_account_lifecycle.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/pages/matrix/authentication/matrix_uia_request_view.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:rooster/utils/links/link_utils.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Asks each User-Interactive Authentication step in a dialog. Closing a
/// dialog answers null, which ends the request.
class DialogUiaPrompter implements UiaPrompter {
  DialogUiaPrompter(this.context);
  final BuildContext context;

  static String get labelUiaPassword => Intl.message("Enter your password",
      name: "labelUiaPassword",
      desc: "Title of the dialog where the server asks for the account's "
          "password before an account change (a new password, an email "
          "address, deactivating the account)");

  static String get messageUiaWrongPassword =>
      Intl.message("That password was not accepted. Try again.",
          name: "messageUiaWrongPassword",
          desc: "In the password dialog of an account change, after the "
              "server refused the password typed");

  static String get labelUiaRegistrationToken =>
      Intl.message("Registration token",
          name: "labelUiaRegistrationToken",
          desc: "Title of the dialog asking for the token some servers "
              "require to create an account");

  static String get messageUiaRegistrationToken => Intl.message(
      "This server needs a registration token to create an account. Ask its admin for one.",
      name: "messageUiaRegistrationToken",
      desc: "Explanation in the registration token dialog");

  static String get messageUiaRegistrationTokenRefused =>
      Intl.message("That token was not accepted. Check it and try again.",
          name: "messageUiaRegistrationTokenRefused",
          desc: "In the registration token dialog, after the server refused "
              "the token typed");

  static String get labelUiaTerms => Intl.message("The server's terms",
      name: "labelUiaTerms",
      desc: "Title of the dialog listing the policies (terms of service, "
          "privacy policy) the server asks people to accept to sign up");

  static String get messageUiaTerms =>
      Intl.message("Read each of these and accept them to continue.",
          name: "messageUiaTerms",
          desc: "Explanation above the list of policies in the terms dialog");

  static String promptUiaAcceptPolicy(String policy) =>
      Intl.message("I have read and accept: $policy",
          name: "promptUiaAcceptPolicy",
          args: [policy],
          desc: "Checkbox next to one policy in the terms dialog, with the "
              "policy's name as the server gives it (Privacy Policy)");

  static String get labelUiaEmail => Intl.message("Email address",
      name: "labelUiaEmail",
      desc: "Title of the dialog asking for an email address the server "
          "will confirm with a link, and the placeholder of its field");

  static String messageUiaEmailSent(String address) => Intl.message(
      "We sent a link to $address. Open it, then come back and continue.",
      name: "messageUiaEmailSent",
      args: [address],
      desc: "After the server sent a confirmation link to the email address "
          "typed, with that address");

  static String get labelUiaPhoneCountry =>
      Intl.message("Country, as a two-letter code (BR, US, PT)",
          name: "labelUiaPhoneCountry",
          desc: "Title of the dialog asking which country a phone number is "
              "from, as its ISO code, before the number itself");

  static String get labelUiaPhoneNumber =>
      Intl.message("Phone number, with the area code",
          name: "labelUiaPhoneNumber",
          desc: "Title of the dialog asking for a phone number the server "
              "will send a code to");

  static String messageUiaSmsCode(String phone) =>
      Intl.message("Enter the code sent to $phone",
          name: "messageUiaSmsCode",
          args: [phone],
          desc: "Title of the dialog asking for the code a text message "
              "brought to the phone number shown");

  static String get messageUiaFinishOnWebsite => Intl.message(
      "Finish this step on your server's website: open it, follow the steps there, then come back and continue.",
      name: "messageUiaFinishOnWebsite",
      desc: "When the server asks for a step only its website can do (a "
          "captcha, single sign-on, an approval), with buttons to open the "
          "website and to continue after");

  static String get errorUiaUnsupported => Intl.message(
      "The server asks for a step this app cannot do, so this could not be finished.",
      name: "errorUiaUnsupported",
      desc: "When the server asks for a kind of confirmation the app does not "
          "know");

  Future<String?> _ask(String title,
      {String? description, String? error, bool obscure = false}) {
    return AdaptiveDialog.show<String>(context,
        title: title,
        builder: (_) => UiaTextStep(
            description: description, error: error, obscure: obscure));
  }

  @override
  Future<String?> password({required bool failed}) => _ask(labelUiaPassword,
      obscure: true, error: failed ? messageUiaWrongPassword : null);

  @override
  Future<String?> registrationToken({required bool failed}) =>
      _ask(labelUiaRegistrationToken,
          description: messageUiaRegistrationToken,
          error: failed ? messageUiaRegistrationTokenRefused : null);

  @override
  Future<bool> acceptTerms(List<UiaTermsPolicy> policies) async =>
      await AdaptiveDialog.show<bool>(context,
          title: labelUiaTerms,
          builder: (_) => UiaTermsStep(policies: policies)) ==
      true;

  @override
  Future<String?> email({required bool failed}) => _ask(labelUiaEmail);

  @override
  Future<bool> confirmEmail(String address) =>
      _continue(messageUiaEmailSent(address));

  @override
  Future<(String, String)?> phone({required bool failed}) async {
    final country = await _ask(labelUiaPhoneCountry);
    if (country == null || !context.mounted) return null;
    final number = await _ask(labelUiaPhoneNumber);
    return number == null ? null : (country.toUpperCase(), number);
  }

  @override
  Future<String?> smsCode(String phoneNumber) =>
      _ask(messageUiaSmsCode(phoneNumber));

  @override
  Future<bool> completeOnWebsite(String stage, Uri page) =>
      _continue(messageUiaFinishOnWebsite, page: page);

  Future<bool> _continue(String message, {Uri? page}) async =>
      await AdaptiveDialog.show<bool>(context,
          builder: (context) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  tiamat.Text.label(message),
                  if (page != null)
                    tiamat.Button(
                      text: MatrixUIARequestView.promptRoomUiaOpenWebsite,
                      // Opened in the tap itself, so no popup blocker stops
                      // it on the web; the page is the server's own.
                      onTap: () => LinkUtils.open(page,
                          filterTrackingParameters: false,
                          bypassConfirmation: true),
                    ),
                  tiamat.Button.secondary(
                    text: CommonStrings.promptContinue,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ],
              )) ==
      true;
}

/// One text field and a button, popping what was typed.
class UiaTextStep extends StatefulWidget {
  const UiaTextStep(
      {super.key, this.description, this.error, this.obscure = false});
  final String? description;
  final String? error;
  final bool obscure;

  @override
  State<UiaTextStep> createState() => _UiaTextStepState();
}

class _UiaTextStepState extends State<UiaTextStep> {
  final controller = TextEditingController();

  void submit() {
    final text = controller.text.trim();
    if (text.isNotEmpty) Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        if (widget.description != null)
          tiamat.Text.labelLow(widget.description!),
        if (widget.error != null) tiamat.Text.error(widget.error!),
        TextField(
          key: const ValueKey('uia-text'),
          controller: controller,
          autofocus: true,
          autocorrect: false,
          obscureText: widget.obscure,
          onSubmitted: (_) => submit(),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        tiamat.Button(text: CommonStrings.promptContinue, onTap: submit),
      ],
    );
  }
}

/// The server's policies, each accepted on its own; continuing is only
/// possible once every one is ticked.
class UiaTermsStep extends StatefulWidget {
  const UiaTermsStep({super.key, required this.policies});
  final List<UiaTermsPolicy> policies;

  @override
  State<UiaTermsStep> createState() => _UiaTermsStepState();
}

class _UiaTermsStepState extends State<UiaTermsStep> {
  final Set<String> accepted = {};

  bool get allAccepted =>
      widget.policies.every((policy) => accepted.contains(policy.id));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        tiamat.Text.labelLow(DialogUiaPrompter.messageUiaTerms),
        for (final policy in widget.policies)
          Row(children: [
            Checkbox(
              key: ValueKey('uia-terms-${policy.id}'),
              value: accepted.contains(policy.id),
              onChanged: (value) => setState(() => value == true
                  ? accepted.add(policy.id)
                  : accepted.remove(policy.id)),
            ),
            Flexible(
              child: TextButton(
                onPressed: () => LinkUtils.open(policy.url,
                    filterTrackingParameters: false, context: context),
                child:
                    Text(DialogUiaPrompter.promptUiaAcceptPolicy(policy.name)),
              ),
            ),
          ]),
        tiamat.Button(
          text: CommonStrings.promptContinue,
          onTap: allAccepted ? () => Navigator.of(context).pop(true) : null,
        ),
      ],
    );
  }
}
