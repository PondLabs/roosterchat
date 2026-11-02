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
      this.onSuccess});
  final UiaRequestState state;
  final Set<String> nextSteps;
  final Function(String password)? onSubmitAuthentication;
  final Function()? onSubmitSso;
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

  bool get canUseAnyNextStep => canUsePassword || canUseSso;

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
