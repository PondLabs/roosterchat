import 'package:rooster/ui/pages/matrix/authentication/matrix_uia_request_view.dart';
import 'package:rooster/utils/error_utils.dart';
import 'package:rooster/utils/links/link_utils.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart';

import '../../../../client/matrix/matrix_client.dart';

class MatrixUIARequest extends StatefulWidget {
  const MatrixUIARequest(this.request, this.client, {super.key});
  final UiaRequest request;
  final MatrixClient client;
  @override
  State<MatrixUIARequest> createState() => _MatrixUIARequestState();
}

/// The steps that send the person to the server's own website to approve
/// the request: Matrix 1.15's `m.oauth`, and the name the Matrix
/// Authentication Service gave it before (MSC4312).
const accountPageStages = ['m.oauth', 'org.matrix.cross_signing_reset'];

class _MatrixUIARequestState extends State<MatrixUIARequest> {
  void Function(UiaRequestState)? originalOnUpdate;
  late UiaRequestState state;
  late Set<String> steps;

  /// The website was opened from here: coming back to the app sends the
  /// request again.
  bool sentToAccountPage = false;

  /// The request was sent again after the website step.
  bool retried = false;

  /// The server still waited for the approval when the request was sent
  /// again.
  bool notApprovedYet = false;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    state = widget.request.state;

    originalOnUpdate = widget.request.onUpdate;
    widget.request.onUpdate = onUpdate;
    steps = widget.request.nextStages;
    // Back from the website (another app, or another browser tab on the
    // web): the server may have the approval now.
    _lifecycle = AppLifecycleListener(onResume: () {
      if (sentToAccountPage) retry();
    });

    super.initState();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void onUpdate(UiaRequestState state) {
    setState(() {
      this.state = state;
      this.steps = widget.request.nextStages;
      if (state == UiaRequestState.waitForUser && retried) {
        notApprovedYet = true;
      }
    });

    originalOnUpdate?.call(state);
  }

  /// The server's page for the step it waits on, when it is a web page
  /// (`http` or `https`): nothing else is opened.
  Uri? get accountPage {
    for (final stage in accountPageStages) {
      if (!steps.contains(stage)) continue;
      final params = widget.request.params[stage];
      final url = params is Map ? params['url'] : null;
      final uri = url is String ? Uri.tryParse(url) : null;
      if (uri != null && (uri.scheme == "http" || uri.scheme == "https")) {
        return uri;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return MatrixUIARequestView(
      state,
      nextSteps: steps,
      onSubmitAuthentication: submitAuthentication,
      onSubmitSso: submitSso,
      accountPage: accountPage,
      notApprovedYet: notApprovedYet,
      onOpenAccountPage: openAccountPage,
      onRetry: retry,
      onSuccess: () => Navigator.of(context).pop(),
      onFail: () => Navigator.of(context).pop(),
    );
  }

  void submitAuthentication(String password) {
    ErrorUtils.tryRun(context, () async {
      await widget.request.completeStage(AuthenticationPassword(
          password: password,
          identifier: AuthenticationUserIdentifier(
              user: widget.client.matrixClient.userID!)));
    });
  }

  void openAccountPage() {
    sentToAccountPage = true;
    // As Settings > Security does for sessions: without a context nothing
    // is asked, as the dialog says where the button leads and the link is
    // the server's own, so on the web the page opens in the same task as
    // the tap (no popup blocker stops it).
    LinkUtils.open(accountPage!,
        filterTrackingParameters: false, bypassConfirmation: true);
  }

  /// Sends the request again with the same session, as the server asks
  /// once the person approved it on its website.
  void retry() {
    if (state != UiaRequestState.waitForUser) return;
    retried = true;
    widget.request
        .completeStage(AuthenticationData(session: widget.request.session));
  }

  submitSso() {
    // https://spec.matrix.org/v1.15/client-server-api/#client-behaviour-21
    var hs = widget.client.matrixClient.homeserver!;
    var url = hs.replace(
        path: "/_matrix/client/v3/auth/m.login.sso/fallback/web",
        queryParameters: {"session": widget.request.session});

    LinkUtils.open(url,
        bypassConfirmation: true,
        filterTrackingParameters: false,
        context: context);
    Navigator.of(context).pop();
  }
}
