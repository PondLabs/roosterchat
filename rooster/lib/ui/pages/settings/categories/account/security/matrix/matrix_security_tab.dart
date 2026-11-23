import 'package:rooster/client/alert.dart';
import 'package:rooster/client/matrix/auth/matrix_account_lifecycle.dart';
import 'package:rooster/client/matrix/components/dehydrated_devices/matrix_dehydrated_devices_component.dart';
import 'package:rooster/client/matrix/components/key_portability/megolm_key_portability.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/molecules/alert_view.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/pages/settings/categories/account/security/matrix/session/matrix_session.dart';
import 'package:rooster/ui/pages/settings/categories/account/security/matrix/session/matrix_session_name_view.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:rooster/utils/links/link_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import 'cross_signing/cross_signing_page.dart';
import 'dehydrated_device/matrix_dehydrated_device_panel.dart';
import 'key_backup/matrix_key_backup_panel.dart';
import 'key_portability/matrix_key_portability_panel.dart';

class MatrixSecurityTab extends StatefulWidget {
  const MatrixSecurityTab(this.client, {super.key});
  final MatrixClient client;

  static String get messageSettingsSessionsOnAccountPage => Intl.message(
      "Your server signs sessions out on its own website, which opens in your browser.",
      name: "messageSettingsSessionsOnAccountPage",
      desc: "Settings > Security > Sessions: on a server that only lets its "
          "own account website sign sessions (devices) out, says that "
          "removing one opens that website");

  static String get messageSettingsSessionsCannotSignOut => Intl.message(
      "Your server does not let apps sign out your other sessions, so sign out on each device.",
      name: "messageSettingsSessionsCannotSignOut",
      desc: "Settings > Security > Sessions: the server neither has an "
          "account website nor lets apps sign sessions (devices) out, so "
          "there is no remove button");

  static String messageSettingsSessionsSignedOut(int howMany) =>
      Intl.plural(howMany,
          one: "1 session was signed out.",
          other: "$howMany sessions were signed out.",
          name: "messageSettingsSessionsSignedOut",
          args: [howMany],
          desc: "Settings > Security > Sessions: after the list is fetched "
              "again, how many sessions (devices) left it, for example "
              "after signing them out on the server's website");
  @override
  State<MatrixSecurityTab> createState() => _MatrixSecurityTabState();
}

class _MatrixSecurityTabState extends State<MatrixSecurityTab> {
  bool crossSigningEnabled = false;
  bool? messageBackupEnabled;
  bool isVerified = false;
  bool encryptionDisabled = false;
  List<Device>? devices;
  late DateTime time;

  Map<String, Object?>? authMetadata;

  /// The server answered `/auth_metadata`, with the metadata or with an
  /// error (a server without an account service): false while unknown.
  bool authMetadataAnswered = false;

  bool? supportsLegacyUIA;

  /// The account page was opened from here: coming back to the app fetches
  /// the list again, with what was signed out there.
  bool sentToAccountPage = false;

  /// How many sessions the last fetch found gone from the list before it.
  int sessionsSignedOut = 0;

  /// Why the last rename of a session failed, while its name stays.
  String? sessionNameError;

  Future<void>? _loading;

  late final AppLifecycleListener _lifecycle;

  Uri? get accountManagementUri {
    var str = authMetadata?.tryGet<String>("account_management_uri");
    if (str == null) return null;
    return Uri.tryParse(str);
  }

  List<String>? get supportedActions =>
      authMetadata?.tryGetList<String>("account_management_actions_supported");

  /// Sessions are signed out on the server's account page (MSC4191), as
  /// on a server with the Matrix Authentication Service.
  bool get usesAccountPage =>
      supportsLegacyUIA != true && accountManagementUri != null;

  /// Sessions are renamed here, through the client API, unless the
  /// server's account page manages them. A server that gave no metadata
  /// does not delegate.
  bool get canEditSessionNames => !usesAccountPage;

  /// The server answered that it has no account page and does not sign
  /// sessions out through the client API either.
  bool get cannotSignOutSessions =>
      supportsLegacyUIA == false &&
      authMetadataAnswered &&
      accountManagementUri == null;

  String get labelMatrixCrossSigning => Intl.message("Cross signing",
      desc: "Title label for matrix cross signing",
      name: "labelMatrixCrossSigning");

  String get labelMatrixCrossSigningAndBackup => Intl.message(
      "Cross Signing & Backup",
      desc: "Header label for matrix cross signing and message backup section",
      name: "labelMatrixCrossSigningAndBackup");

  String get labelMatrixAccountSessions => Intl.message("Sessions",
      desc: "Title label for account sessions",
      name: "labelMatrixAccountSessions");

  String get labelMatrixCrossSigningExplanation =>
      Intl.message("Set up to verify and keep track of all your sessions",
          desc: "Explains what matrix cross signing does",
          name: "labelMatrixCrossSigningExplanation");

  String get labelMatrixResetCrossSigningTitle =>
      Intl.message("Reset cross signing",
          desc: "Title for the popup dialog when resetting cross signing",
          name: "labelMatrixResetCrossSigningTitle");

  String get labelMatrixMessageBackup => Intl.message("Message backup",
      desc: "TItle label for matrix message backup settings",
      name: "labelMatrixMessageBackup");

  String get labelMatrixMessageBackupExplanation => Intl.message(
      "Maintains a backup of your message history, in case you lose all your sessions. Your messages will be encrypted before uploading",
      desc: "Explains what matrix message backup does",
      name: "labelMatrixMessageBackupExplanation");

  String get promptSetupMatrixMessageBackup => Intl.message("Set up backup",
      desc: "Text on the button to begin the setup process for message backup",
      name: "promptSetupMatrixMessageBackup");

  String get labelRestoreMatrixBackupTitle => Intl.message("Restore backup",
      desc: "Title of the popup dialog for restoring message backup",
      name: "labelRestoreMatrixBackupTitle");

  String messageSettingsInactiveSessions(int howMany) => Intl.plural(howMany,
      one: "You have 1 session which has not been used recently",
      other: "You have $howMany sessions which have not been used recently",
      name: "messageSettingsInactiveSessions",
      args: [howMany],
      desc: "Settings > Security > Sessions: warning that some of your "
          "sessions (signed-in devices) have not been used for over two "
          "months");

  String get labelSettingsInactiveDevices => Intl.message("Inactive Devices",
      name: "labelSettingsInactiveDevices",
      desc: "Settings > Security > Sessions: title of the warning about "
          "sessions not used for over two months");

  String messageSettingsConfirmLogOutSessions(int howMany) =>
      Intl.plural(howMany,
          one: "Are you sure you want to log out of 1 session?",
          other: "Are you sure you want to log out of $howMany sessions?",
          name: "messageSettingsConfirmLogOutSessions",
          args: [howMany],
          desc: "Settings > Security > Sessions: asks before signing out every "
              "session not used for over two months");

  String get messageSettingsEncryptionDisabledByServer =>
      Intl.message("Your homeserver has force-disabled encryption",
          name: "messageSettingsEncryptionDisabledByServer",
          desc: "Settings > Security: your Matrix server turned end-to-end "
              "encryption off for everyone");

  String get labelSettingsEncryptionDisabled =>
      Intl.message("Encryption Disabled",
          name: "labelSettingsEncryptionDisabled",
          desc: "Settings > Security: title of the notice that your Matrix "
              "server turned encryption off");

  String get messageSettingsSessionNotVerified => Intl.message(
      "Your current session is not verified. You will not be able to participate in encrypted chats.",
      name: "messageSettingsSessionNotVerified",
      desc: "Settings > Security: warning that this device has not been "
          "verified with your other sessions");

  String get labelSettingsSessionUnverified => Intl.message("Unverified",
      name: "labelSettingsSessionUnverified",
      desc: "Settings > Security: title of the warning that this session has "
          "not been verified");

  @override
  void initState() {
    time = DateTime.now();
    // Back from the account page (another app, or another browser tab on
    // the web): the list shows what was signed out there.
    _lifecycle = AppLifecycleListener(onResume: () {
      if (sentToAccountPage) getDevices();
    });
    checkState();
    getDevices();

    widget.client.hasServerDisabledEncryption().then((v) => setState(() {
          encryptionDisabled = v;
        }));

    super.initState();
  }

  void checkState() {
    setState(() {
      var encryption = widget.client.getMatrixClient().encryption;
      crossSigningEnabled = encryption?.crossSigning.enabled ?? false;
      messageBackupEnabled = encryption?.keyManager.keyBackupEnabled ?? false;
      isVerified = widget.client.matrixClient.isUnknownSession == false;
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Fetches the list, unless a fetch is already on its way.
  void getDevices() {
    _loading ??= _fetchDevices().whenComplete(() => _loading = null);
  }

  Future<void> _fetchDevices() async {
    var gotDevices = await widget.client.getMatrixClient().getDevices();

    if (!authMetadataAnswered) {
      try {
        authMetadata = await widget.client.matrixClient
            .request(RequestType.GET, "/client/v1/auth_metadata");
        authMetadataAnswered = true;
      } on MatrixException {
        // No account service here (404 M_UNRECOGNIZED).
        authMetadataAnswered = true;
      } catch (e, s) {
        Log.onError(e, s);
      }
    }

    // A server with an account page signs sessions out only there: the
    // client API is never asked.
    if (accountManagementUri == null && supportsLegacyUIA == null) {
      try {
        await widget.client.matrixClient
            .request(RequestType.DELETE, "/client/v3/devices/_", data: {
          "auth": {
            "type": "m.login.dummy",
          }
        });
      } catch (e) {
        if (e case MatrixException mx) {
          if (mx.error == MatrixError.M_FORBIDDEN) {
            supportsLegacyUIA = true;
          } else {
            supportsLegacyUIA = false;
          }
        }
      }
    }

    gotDevices
        ?.sort((a, b) => (b.lastSeenTs ?? 0).compareTo(a.lastSeenTs ?? 0));

    if (!mounted) return;
    final before = devices?.map((device) => device.deviceId).toSet();
    setState(() {
      if (before != null && gotDevices != null) {
        sessionsSignedOut = before
            .difference(gotDevices.map((device) => device.deviceId).toSet())
            .length;
      }
      devices = gotDevices;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
      spacing: 4,
      children: [crossSigningPanel(), sessionsPanel()],
    );
  }

  Iterable<Device> get inactiveDevices =>
      devices?.where((i) => isDeviceInactive(i)) ?? [];

  Panel sessionsPanel() {
    return Panel(
      header: labelMatrixAccountSessions,
      mode: TileType.surfaceContainerLow,
      child: devices == null
          ? SizedBox(
              height: 300,
              child: Center(child: const CircularProgressIndicator()))
          : Column(
              children: [
                for (final message in [
                  if (usesAccountPage)
                    MatrixSecurityTab.messageSettingsSessionsOnAccountPage,
                  if (cannotSignOutSessions)
                    MatrixSecurityTab.messageSettingsSessionsCannotSignOut,
                  if (sessionsSignedOut > 0)
                    MatrixSecurityTab.messageSettingsSessionsSignedOut(
                        sessionsSignedOut),
                ])
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: tiamat.Text.labelLow(message)),
                  ),
                if (sessionNameError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: tiamat.Text.error(sessionNameError!)),
                  ),
                if ((supportsLegacyUIA == true || usesAccountPage) &&
                    inactiveDevices.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                    child: Container(
                      decoration: BoxDecoration(
                          color: ColorScheme.of(context).surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Flexible(
                              child: AlertView(
                                Alert(
                                  AlertType.warning,
                                  messageGetter: () =>
                                      messageSettingsInactiveSessions(
                                          inactiveDevices.length),
                                  titleGetter: () =>
                                      labelSettingsInactiveDevices,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              height: 40,
                              child: tiamat.IconButton(
                                size: 15,
                                icon: Icons.logout,
                                onPressed: () {
                                  if (supportsLegacyUIA == true) {
                                    removeInactiveDevices();
                                  } else {
                                    openSessionsList();
                                  }
                                },
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemBuilder: (context, index) {
                    var device = devices![index];
                    return Padding(
                      padding: const EdgeInsets.all(2.0),
                      child: MatrixSession(
                        device,
                        widget.client.getMatrixClient(),
                        inactive: isDeviceInactive(device),
                        editName: canEditSessionNames
                            ? () => editSessionName(device)
                            : null,
                        removeSession: supportsLegacyUIA == true
                            ? () => removeDeviceUIA(device.deviceId)
                            : usesAccountPage
                                ? () => removeDeviceOAuth(device.deviceId)
                                : null,
                      ),
                    );
                  },
                  itemCount: devices!.length,
                ),
              ],
            ),
    );
  }

  /// Renames [device] (`PUT /devices/{id}`), or clears its name, then
  /// fetches the list again. When the server refuses or cannot be
  /// reached, the list keeps the name it had.
  Future<void> editSessionName(Device device) async {
    final choice = await AdaptiveDialog.show<SessionNameChoice>(context,
        title: MatrixSessionNameView.labelSessionRenameTitle,
        builder: (_) => MatrixSessionNameView(currentName: device.displayName));
    if (choice == null || !mounted) return;
    final client = widget.client.getMatrixClient();
    try {
      final name = choice.name;
      if (name == null) {
        await client.deleteDeviceDisplayName(device.deviceId);
      } else {
        await client.updateDevice(device.deviceId, displayName: name);
      }
    } catch (e, s) {
      Log.onError(e, s);
      if (mounted) {
        setState(() => sessionNameError =
            MatrixSessionNameView.messageSessionRenameFailed);
      }
      return;
    }
    if (!mounted) return;
    setState(() => sessionNameError = null);
    getDevices();
  }

  void removeDeviceUIA(String deviceID) async {
    await widget.client.matrixClient.uiaRequestBackground((auth) async {
      await widget.client.matrixClient.deleteDevice(deviceID, auth: auth);

      getDevices();
    });
  }

  void removeInactiveDevices() async {
    var confirm = await AdaptiveDialog.confirmation(context,
        dangerous: true,
        prompt: messageSettingsConfirmLogOutSessions(inactiveDevices.length));

    if (confirm != true) return;

    await widget.client.matrixClient.uiaRequestBackground((auth) async {
      await widget.client.matrixClient.deleteDevices(
          inactiveDevices.map((i) => i.deviceId).toList(),
          auth: auth);
    });

    getDevices();
  }

  /// Opens the account page on signing [deviceID] out (MSC4191's
  /// `org.matrix.session_end`), else on the session, else on the list.
  void removeDeviceOAuth(String deviceID) {
    final page = [
      AccountManagementActions.sessionEnd,
      AccountManagementActions.sessionView,
    ]
        .map((action) => accountManagementLink(
            accountManagementUri, supportedActions,
            action: action, deviceId: deviceID))
        .nonNulls
        .firstOrNull;
    if (page == null) return openSessionsList();
    openAccountPage(page);
  }

  /// Opens the account page on the list of sessions, where the inactive
  /// ones are signed out.
  void openSessionsList() {
    final page = accountManagementLink(accountManagementUri, supportedActions,
            action: AccountManagementActions.sessionsList) ??
        accountManagementLink(accountManagementUri, supportedActions);
    if (page != null) openAccountPage(page);
  }

  void openAccountPage(Uri page) {
    sentToAccountPage = true;
    // Without a context: nothing to ask, as this screen says where the
    // button leads and the link is the server's own, so on the web the
    // page opens in the same task as the tap (no popup blocker stops it).
    LinkUtils.open(page,
        filterTrackingParameters: false, bypassConfirmation: true);
  }

  void onUpdated() {
    setState(() {
      getDevices();
    });
  }

  Panel crossSigningPanel() {
    return Panel(
        header: labelMatrixCrossSigningAndBackup,
        mode: TileType.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            spacing: 4,
            children: [
              if (encryptionDisabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                  child: Container(
                    decoration: BoxDecoration(
                        color: ColorScheme.of(context).surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(8)),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: AlertView(Alert(AlertType.info,
                          messageGetter: () =>
                              messageSettingsEncryptionDisabledByServer,
                          titleGetter: () => labelSettingsEncryptionDisabled)),
                    ),
                  ),
                ),
              if (!isVerified)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                  child: Container(
                    decoration: BoxDecoration(
                        color: ColorScheme.of(context).surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(8)),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: AlertView(Alert(AlertType.warning,
                          messageGetter: () =>
                              messageSettingsSessionNotVerified,
                          titleGetter: () => labelSettingsSessionUnverified)),
                    ),
                  ),
                ),
              crossSigning(),
              const tiamat.Seperator(),
              messageBackup()
            ],
          ),
        ));
  }

  Widget crossSigning() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Text.label(labelMatrixCrossSigning),
              tiamat.Text.labelLow(labelMatrixCrossSigningExplanation)
            ],
          ),
        ),
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
            child: crossSigningEnabled
                ? tiamat.Button.danger(
                    text: CommonStrings.promptReset,
                    onTap: () => AdaptiveDialog.show(context,
                        builder: (_) => MatrixCrossSigningPage(
                              client: widget.client,
                              mode: MatrixCrossSigningMode.resetCrossSigning,
                              onComplete: checkState,
                            ),
                        dismissible: true,
                        title: labelMatrixResetCrossSigningTitle),
                  )
                : tiamat.Button.secondary(
                    text: CommonStrings.promptEnable,
                    onTap: () => AdaptiveDialog.show(context,
                        builder: (_) => MatrixCrossSigningPage(
                              client: widget.client,
                              onComplete: checkState,
                            ),
                        dismissible: true,
                        title: labelMatrixCrossSigning),
                  )),
      ],
    );
  }

  late final keyBackupController =
      MatrixKeyBackupController(widget.client.getMatrixClient());

  Widget messageBackup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        messageBackupRow(),
        // The details, rotation and deletion of the backup on the server
        // (and m.key_backup, MSC4287), loaded again once it is set up.
        if (widget.client.getMatrixClient().encryption != null)
          MatrixKeyBackupPanel(
            key: ValueKey(messageBackupEnabled),
            controller: keyBackupController,
            onChanged: checkState,
          ),
        // Room keys to and from a file (the spec's key export format).
        if (widget.client.getMatrixClient().encryption != null) ...[
          const tiamat.Seperator(),
          MatrixKeyPortabilityPanel(controller: keyPortability),
        ],
        // MSC3814: keys for messages sent while no session is signed in.
        if (widget.client.getMatrixClient().encryption != null &&
            dehydratedDevices != null) ...[
          const tiamat.Seperator(),
          MatrixDehydratedDevicePanel(controller: dehydratedDevices!),
        ],
      ],
    );
  }

  late final dehydratedDevices =
      widget.client.getComponent<MatrixDehydratedDevicesComponent>();

  late final keyPortability =
      MegolmKeyPortability(widget.client.getMatrixClient());

  Widget messageBackupRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Text.label(labelMatrixMessageBackup),
              tiamat.Text.labelLow(labelMatrixMessageBackupExplanation)
            ],
          ),
        ),
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
            child: messageBackupEnabled == true
                ? tiamat.Button.secondary(
                    text: CommonStrings.promptRestore,
                    onTap: () => AdaptiveDialog.show(context,
                        builder: (_) => MatrixCrossSigningPage(
                              client: widget.client,
                              onComplete: checkState,
                              mode: MatrixCrossSigningMode.restoreBackup,
                            ),
                        dismissible: true,
                        title: labelRestoreMatrixBackupTitle),
                  )
                : messageBackupEnabled == false
                    ? tiamat.Button.secondary(
                        text: CommonStrings.promptEnable,
                        onTap: () => AdaptiveDialog.show(context,
                            builder: (_) => MatrixCrossSigningPage(
                                  client: widget.client,
                                  onComplete: checkState,
                                  mode: MatrixCrossSigningMode.enableBackup,
                                ),
                            dismissible: true,
                            title: promptSetupMatrixMessageBackup),
                      )
                    : const CircularProgressIndicator())
      ],
    );
  }

  bool isDeviceInactive(Device device) {
    if (device.lastSeenTs == null) return false;

    var date = DateTime.fromMillisecondsSinceEpoch(device.lastSeenTs!);
    var diff = time.difference(date);

    return diff.inDays > 60;
  }
}
