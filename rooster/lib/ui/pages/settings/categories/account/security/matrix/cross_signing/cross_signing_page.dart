import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/ui/pages/settings/categories/account/security/matrix/cross_signing/cross_signing_view.dart';
import 'package:flutter/widgets.dart';

import 'package:matrix/encryption.dart';

enum MatrixCrossSigningMode {
  standard,
  enableBackup,
  restoreBackup,
  resetCrossSigning,
  crossSigningOnly,

  /// Verifies this device with the recovery key or security phrase: keeps
  /// the account's keys and backup as they are, and only signs this device.
  verifyDevice
}

class MatrixCrossSigningPage extends StatefulWidget {
  const MatrixCrossSigningPage(
      {required this.client,
      this.mode = MatrixCrossSigningMode.standard,
      super.key,
      this.onComplete});
  final MatrixClient client;
  final MatrixCrossSigningMode mode;
  final Function()? onComplete;

  @override
  State<MatrixCrossSigningPage> createState() => MatrixCrossSigningPageState();
}

class MatrixCrossSigningPageState extends State<MatrixCrossSigningPage> {
  BootstrapState state = BootstrapState.loading;
  Bootstrap? bootstrapper;
  @override
  void initState() {
    var mx = widget.client.getMatrixClient();
    bootstrapper = mx.encryption?.bootstrap(onUpdate: onBootstrapperUdate);
    onBootstrapperUdate(bootstrapper!);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MatrixCrossSigningView(
      shownState,
      recoveryKey: bootstrapper?.newSsssKey?.recoveryKey,
      onSetNewSsss: (passphrase) {
        bootstrapper?.newSsss(passphrase);
      },
      onAskSetupCrossSigning: () async {
        await bootstrapper?.askSetupCrossSigning(
          setupMasterKey: true,
          setupSelfSigningKey: true,
          setupUserSigningKey: true,
        );
      },
      onAskSetupOnlineBackup: (enable) {
        bootstrapper?.askSetupOnlineKeyBackup(enable);
      },
      useExistingKeys: (use) {
        bootstrapper?.useExistingSsss(use);
      },
      wipeSsss: (wipe) {
        bootstrapper?.wipeSsss(wipe);
        if (!wipe) {
          bootstrapper?.useExistingSsss(true);
          bootstrapper?.openExistingSsss();
        }
      },
      wipeExistingBackup: (wipe) {
        bootstrapper?.wipeOnlineKeyBackup(wipe);
      },
      openExistingSsss: (key) async {
        await bootstrapper?.newSsssKey!.unlock(keyOrPassphrase: key);
        await bootstrapper?.openExistingSsss();

        if (bootstrapper!.encryption.crossSigning.enabled) {
          await bootstrapper?.client.encryption!.crossSigning
              .selfSign(keyOrPassphrase: key);
        }
      },
      wipeCrossSigning: (wipe) {
        bootstrapper?.wipeCrossSigning(wipe);
      },
    );
  }

  /// Verifying a device never makes new keys: a step that would (no secret
  /// storage to unlock, or no cross-signing in it) shows as an error.
  BootstrapState get shownState {
    if (widget.mode != MatrixCrossSigningMode.verifyDevice) return state;
    return switch (state) {
      BootstrapState.askNewSsss ||
      BootstrapState.askSetupCrossSigning ||
      BootstrapState.askUnlockSsss ||
      BootstrapState.askBadSsss =>
        BootstrapState.error,
      _ => state,
    };
  }

  void onBootstrapperUdate(Bootstrap bootstrapper) async {
    if (bootstrapper.state == BootstrapState.done) {
      widget.onComplete?.call();
    }

    if (widget.mode == MatrixCrossSigningMode.enableBackup ||
        widget.mode == MatrixCrossSigningMode.restoreBackup) {
      switch (bootstrapper.state) {
        case BootstrapState.askUseExistingSsss:
          bootstrapper.useExistingSsss(true);
          break;
        case BootstrapState.askWipeSsss:
          bootstrapper.wipeSsss(false);
          break;
        case BootstrapState.askWipeCrossSigning:
          bootstrapper.wipeCrossSigning(false);
          break;
        case BootstrapState.askWipeOnlineKeyBackup:
          bootstrapper.wipeOnlineKeyBackup(false);
          break;
        default:
          break;
      }
    }

    if (widget.mode == MatrixCrossSigningMode.verifyDevice) {
      switch (bootstrapper.state) {
        case BootstrapState.askWipeSsss:
          bootstrapper.wipeSsss(false);
          break;
        case BootstrapState.askUseExistingSsss:
          bootstrapper.useExistingSsss(true);
          break;
        case BootstrapState.askWipeCrossSigning:
          bootstrapper.wipeCrossSigning(false);
          break;
        case BootstrapState.askWipeOnlineKeyBackup:
          bootstrapper.wipeOnlineKeyBackup(false);
          break;
        case BootstrapState.askSetupOnlineKeyBackup:
          bootstrapper.askSetupOnlineKeyBackup(false);
          break;
        default:
          break;
      }
    }

    // A closed confirmation dialog now ends its request, so the setup can
    // finish after this page is gone.
    if (!mounted) return;
    setState(() {
      state = bootstrapper.state;
    });
  }
}
