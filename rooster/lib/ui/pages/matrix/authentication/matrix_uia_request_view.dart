import 'package:rooster/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
// have to do it this way to avoid some widgetbook codegen issue
// ignore: implementation_imports
import 'package:matrix/src/utils/uia_request.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:flutter/material.dart' as material;

class MatrixUIARequestView extends StatefulWidget {
  const MatrixUIARequestView(this.state,
      {this.onSubmitAuthentication,
      required this.nextSteps,
      super.key,
      this.onFail,
      this.onSubmitSso,
      this.accountPage,
      this.notApprovedYet = false,
      this.onOpenAccountPage,
      this.onRetry,
      this.onSuccess});
  final UiaRequestState state;
  final Set<String> nextSteps;
  final Function(String password)? onSubmitAuthentication;
  final Function()? onSubmitSso;

  /// The server's own web page where the person approves the request, when
  /// it asks for that (Matrix 1.15's `m.oauth`), as the Matrix
  /// Authentication Service of matrix.org does before new verification
  /// keys.
  final Uri? accountPage;

  /// The request was sent again and the server still waits for the
  /// approval.
  final bool notApprovedYet;
  final Function()? onOpenAccountPage;

  /// Sends the request again, once the person approved it on [accountPage].
  final Function()? onRetry;
  final Function()? onSuccess;
  final Function()? onFail;

  @override
  State<MatrixUIARequestView> createState() => _MatrixUIARequestViewState();
}

enum UIAStep {
  password,
  sso,
}

class _MatrixUIARequestViewState extends State<MatrixUIARequestView> {
  TextEditingController passwordFieldController = TextEditingController();
  bool get canUsePassword => widget.nextSteps.contains("m.login.password");
  bool get canUseSso => widget.nextSteps.contains("m.login.sso");

  bool get canUseAccountPage => widget.accountPage != null;

  bool get canUseAnyNextStep =>
      canUsePassword || canUseSso || canUseAccountPage;

  UIAStep? pickedStep;

  String get promptRoomUiaContinueWithPassword => Intl.message(
      "Continue with password",
      name: "promptRoomUiaContinueWithPassword",
      desc:
          "Button in the dialog where the server asks us to sign in again before a sensitive action: confirm with the account's password");

  String get promptRoomUiaContinueWithSso => Intl.message("Continue with SSO",
      name: "promptRoomUiaContinueWithSso",
      desc:
          "Button in the dialog where the server asks us to sign in again before a sensitive action: confirm through single sign-on (SSO) in the browser");

  String get messageRoomUiaNoSupportedMethod => Intl.message(
      "Sorry, none of the authentication methods provided by the server are supported.",
      name: "messageRoomUiaNoSupportedMethod",
      desc:
          "In the dialog where the server asks us to sign in again: the app supports none of the ways the server offers");

  static String get messageRoomUiaApproveOnWebsite => Intl.message(
      "Your server approves this change on its own website: open it, approve the change, and come back.",
      name: "messageRoomUiaApproveOnWebsite",
      desc: "In the dialog where the server asks us to confirm a sensitive "
          "change (such as new keys that verify your sessions): the server "
          "only takes it once the person approves it on the server's own "
          "website, which the button below opens in the browser");

  static String get messageRoomUiaNotApprovedYet => Intl.message(
      "The server has not seen the approval yet. Approve the change on the website, then try again.",
      name: "messageRoomUiaNotApprovedYet",
      desc: "In the dialog where the server asks us to approve a sensitive "
          "change on its website: we asked again and the server still "
          "waits for that approval");

  static String get promptRoomUiaOpenWebsite => Intl.message("Open the website",
      name: "promptRoomUiaOpenWebsite",
      desc: "Button in the dialog where the server asks us to approve a "
          "sensitive change on its own website: opens that website in the "
          "browser");

  String get labelRoomUiaAccountPassword => Intl.message("Account Password",
      name: "labelRoomUiaAccountPassword",
      desc:
          "Placeholder of the password field in the dialog where the server asks us to sign in again before a sensitive action");

  String get messageRoomUiaSuccess => Intl.message("Success!",
      name: "messageRoomUiaSuccess",
      desc:
          "Shown when signing in again for a sensitive action worked, in the dialog where the server asked for it");

  String get messageRoomUiaLoginFailed => Intl.message("Login failed...",
      name: "messageRoomUiaLoginFailed",
      desc:
          "Shown when signing in again for a sensitive action failed, in the dialog where the server asked for it");

  @override
  void initState() {
    if (canUsePassword && !canUseSso) {
      pickedStep = UIAStep.password;
    }

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 500,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: buildView(),
      ),
    );
  }

  Widget buildView() {
    switch (widget.state) {
      case UiaRequestState.done:
        return done(context);
      case UiaRequestState.fail:
        return fail(context);
      case UiaRequestState.loading:
        return loading();
      case UiaRequestState.waitForUser:
        if (canUseAccountPage) return accountPageStep();
        return pickedStep == null ? showAvailableSteps() : showPickedStep();
    }
  }

  Widget showAvailableSteps() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          if (canUsePassword)
            tiamat.Button(
              text: promptRoomUiaContinueWithPassword,
              onTap: () => setState(() {
                pickedStep = UIAStep.password;
              }),
            ),
          if (canUseSso)
            tiamat.Button(
                text: promptRoomUiaContinueWithSso,
                onTap: () {
                  widget.onSubmitSso?.call();
                  setState(() {
                    pickedStep = UIAStep.sso;
                  });
                }),
          if (canUseAnyNextStep == false) ...[
            tiamat.Text.labelLow(messageRoomUiaNoSupportedMethod),
            tiamat.Text.labelLow(widget.nextSteps.toString()),
          ]
        ],
      ),
    );
  }

  /// The server takes the request once the person approves it on its
  /// website: the button opens it in the same tap (no popup blocker stops
  /// it on the web), and coming back or "Continue" sends the request again.
  Widget accountPageStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        tiamat.Text.label(widget.notApprovedYet
            ? messageRoomUiaNotApprovedYet
            : messageRoomUiaApproveOnWebsite),
        tiamat.Button(
          text: promptRoomUiaOpenWebsite,
          onTap: () => widget.onOpenAccountPage?.call(),
        ),
        tiamat.Button.secondary(
          text: widget.notApprovedYet
              ? CommonStrings.promptRetry
              : CommonStrings.promptContinue,
          onTap: () => widget.onRetry?.call(),
        ),
      ],
    );
  }

  Widget showPickedStep() {
    if (pickedStep == UIAStep.password) {
      return userPasswordInput();
    }

    switch (pickedStep!) {
      case UIAStep.password:
        return userPasswordInput();
      case UIAStep.sso:
        return showSsoStep();
    }
  }

  Widget showSsoStep() {
    return SizedBox(
        height: 300,
        width: 300,
        child: Center(
          child: CircularProgressIndicator(),
        ));
  }

  Widget userPasswordInput() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        TextInput(
          placeholder: labelRoomUiaAccountPassword,
          obscureText: true,
          controller: passwordFieldController,
        ),
        SizedBox(
            height: 40,
            child: Button(
              text: CommonStrings.promptSubmit,
              onTap: () => widget.onSubmitAuthentication
                  ?.call(passwordFieldController.text),
            ))
      ],
    );
  }

  Widget loading() {
    return const Center(
      child: material.CircularProgressIndicator(),
    );
  }

  Widget done(BuildContext context) {
    Navigator.pop(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Icon(
                material.Icons.verified_user_rounded,
                color: material.Colors.green.shade400,
                size: 40,
              ),
            ),
            Flexible(child: tiamat.Text.largeTitle(messageRoomUiaSuccess))
          ],
        ),
        SizedBox(
          height: 40,
          width: 200,
          child: tiamat.Button.success(
            text: CommonStrings.promptContinue,
            onTap: () => widget.onSuccess?.call(),
          ),
        )
      ],
    );
  }

  Widget fail(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Icon(
                material.Icons.error_outline,
                color: material.Theme.of(context).colorScheme.error,
                size: 40,
              ),
            ),
            Flexible(child: tiamat.Text.largeTitle(messageRoomUiaLoginFailed))
          ],
        ),
        SizedBox(
          height: 40,
          width: 200,
          child: tiamat.Button.danger(
            text: CommonStrings.promptContinue,
            onTap: () => widget.onFail?.call(),
          ),
        )
      ],
    );
  }
}
