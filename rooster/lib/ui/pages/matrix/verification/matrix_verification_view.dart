import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:rooster/client/matrix/components/key_verification_component/matrix_qr_verification_payload.dart';
import 'package:rooster/ui/atoms/emoji_widget.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:rooster/utils/emoji/unicode_emoji.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class MatrixVerificationPageView extends StatefulWidget {
  const MatrixVerificationPageView({
    required this.state,
    required this.sasTypes,
    required this.sasNumbers,
    required this.sasEmoji,
    required this.userID,
    this.isSelfVerification = true,
    this.possibleMethods = const [],
    this.qrDataRawBytes,
    this.canceledCode,
    this.qrPayloadError,
    this.ssssError,
    this.isBusy = false,
    this.onVerificationRequestAccepted,
    this.onVerificationRequestRejected,
    this.onSasAccepted,
    this.onSasRejected,
    this.onStartSas,
    this.onSubmitQrPayloadText,
    this.onLoadQrPayloadFile,
    this.onQrPayloadInputChanged,
    this.onConfirmQrScan,
    this.onRejectQrScan,
    this.onUnlockSsss,
    this.onSkipSsss,
    this.onCancel,
    super.key,
  });

  final Function? onVerificationRequestAccepted;
  final Function? onVerificationRequestRejected;
  final Function? onSasAccepted;
  final Function? onSasRejected;
  final Function? onStartSas;
  final void Function(String payload)? onSubmitQrPayloadText;
  final Function? onLoadQrPayloadFile;
  final VoidCallback? onQrPayloadInputChanged;
  final Function? onConfirmQrScan;
  final Function? onRejectQrScan;
  final void Function(String keyOrPassphrase)? onUnlockSsss;
  final Function? onSkipSsss;
  final Function? onCancel;

  final List<String> sasTypes;
  final List<KeyVerificationEmoji> sasEmoji;
  final List<int> sasNumbers;
  final String userID;
  final bool isSelfVerification;
  final List<String> possibleMethods;
  final Uint8List? qrDataRawBytes;
  final String? canceledCode;
  final String? qrPayloadError;
  final String? ssssError;
  final bool isBusy;

  final KeyVerificationState state;

  @override
  State<MatrixVerificationPageView> createState() =>
      _MatrixVerificationPageViewState();
}

class _MatrixVerificationPageViewState
    extends State<MatrixVerificationPageView> {
  final TextEditingController _qrInputController = TextEditingController();
  final TextEditingController _ssssController = TextEditingController();
  bool _qrCopied = false;

  @override
  void dispose() {
    _qrInputController.dispose();
    _ssssController.dispose();
    super.dispose();
  }

  String get messageWaitingOtherDeviceToAccept => Intl.message(
        "Waiting for the other device to accept the request",
        name: "messageWaitingOtherDeviceToAccept",
        desc:
            "Message to show while waiting for another device to accept a matrix session verification request",
      );

  String messageWaitingOtherUserToAccept(String username) => Intl.message(
        "Waiting for $username to accept the verification request",
        name: "messageWaitingOtherUserToAccept",
        args: [username],
        desc:
            "Shown while waiting for another Matrix user to accept an in-room key verification request",
      );

  String get messageWaitingOtherPartyToConfirm => Intl.message(
        "Waiting for the other party to confirm…",
        name: "messageWaitingOtherPartyToConfirm",
        desc:
            "Shown after confirming SAS emoji or numbers while waiting for the other side's MAC confirmation",
      );

  String messageMatrixSessionVerificationRequest(String username) =>
      Intl.message(
        "**$username** has requested to verify your session",
        desc:
            "Message to show when another user has requested to verify your matrix session. Supports markdown to emphasise the user name",
        args: [username],
        name: "messageMatrixSessionVerificationRequest",
      );

  String messageMatrixUserVerificationRequest(String username) => Intl.message(
        "**$username** wants to verify your identity",
        name: "messageMatrixUserVerificationRequest",
        args: [username],
        desc:
            "Shown when another Matrix user sends an in-room request to verify identities. Supports markdown to emphasise the user ID",
      );

  String get messageSasEmojiVerificationPrompt => Intl.message(
        "Check that the emoji are the same, and in the same order as on the other device",
        name: "messageSasEmojiVerificationPrompt",
        desc:
            "Explains what to look for when verifying using emoji. Needs to portray that the emoji MUST be the same AND in the same order",
      );

  String get messageSasDecimalVerificationPrompt => Intl.message(
        "Check that these numbers match the ones shown on the other device",
        name: "messageSasDecimalVerificationPrompt",
        desc:
            "Shown when verifying a session or user by comparing three decimal numbers",
      );

  String get promptConfirmEmojiMatches => Intl.message(
        "They match!",
        name: "promptConfirmEmojiMatches",
        desc: "Button text to confirm that the emoji matches",
      );

  String get promptEmojiDoNotMatch => Intl.message(
        "They don't match",
        name: "promptEmojiDoNotMatch",
        desc: "Button text to confirm that the emoji do NOT match",
      );

  String get messageVerificationComplete => Intl.message(
        "Verification Complete!",
        name: "messageVerificationComplete",
        desc:
            "Message to show when verification was completed successfully, and the session has been verified",
      );

  String get labelVerificationQrTitle => Intl.message(
        "Verify with QR code",
        name: "labelVerificationQrTitle",
        desc:
            "Heading shown on the QR verification step when a QR code can be displayed or entered",
      );

  String get messageVerificationQrScanPrompt => Intl.message(
        "Scan this QR code with the other device, or copy the code below if it has no camera.",
        name: "messageVerificationQrScanPrompt",
        desc:
            "Instructions above the QR code during E2EE verification, including the no-camera copy option",
      );

  String get promptCopyQrPayload => Intl.message(
        "Copy QR payload",
        name: "promptCopyQrPayload",
        desc:
            "Button below a verification QR code to copy its encoded payload for devices without a camera",
      );

  String get labelVerificationQrNoCameraTitle => Intl.message(
        "No camera? Enter or load a QR payload",
        name: "labelVerificationQrNoCameraTitle",
        desc:
            "Heading for the desktop and web fallback input where the user pastes or loads a QR verification payload",
      );

  String get placeholderVerificationQrPayload => Intl.message(
        "Paste QR verification payload",
        name: "placeholderVerificationQrPayload",
        desc:
            "Placeholder inside the text field for pasting a Matrix QR verification payload without a camera",
      );

  String get promptVerifyQrPayload => Intl.message(
        "Verify QR payload",
        name: "promptVerifyQrPayload",
        desc:
            "Button that submits a pasted QR verification payload to complete reciprocation",
      );

  String get promptLoadQrPayloadFile => Intl.message(
        "Load from file",
        name: "promptLoadQrPayloadFile",
        desc:
            "Button in the no-camera QR verification fallback to load a QR payload from a local file",
      );

  String get promptVerifyWithEmoji => Intl.message(
        "Compare emoji instead",
        name: "promptVerifyWithEmoji",
        desc:
            "Button on the QR verification choice screen to switch to SAS emoji comparison",
      );

  String get messageVerificationQrScannedWaiting => Intl.message(
        "QR code verified! Confirm on the other device to finish.",
        name: "messageVerificationQrScannedWaiting",
        desc:
            "Shown to the scanning device after submitting a valid QR payload while waiting for the other side to confirm",
      );

  String get messageVerificationConfirmQrScan => Intl.message(
        "The other device scanned your QR code. Did it show a verified confirmation?",
        name: "messageVerificationConfirmQrScan",
        desc:
            "Shown to the device displaying the QR code after receiving a valid reciprocate start event",
      );

  String messageVerificationConfirmQrScanUser(String username) => Intl.message(
        "$username scanned your QR code. Did their device show a verified confirmation?",
        name: "messageVerificationConfirmQrScanUser",
        args: [username],
        desc:
            "Shown when another user scanned your QR code and you must confirm they saw the verified screen",
      );

  String get promptConfirmQrScanMatches => Intl.message(
        "Yes, it matches",
        name: "promptConfirmQrScanMatches",
        desc:
            "Button to confirm the other side showed a verified screen after scanning your QR code",
      );

  String get promptRejectQrScan => Intl.message(
        "No, cancel verification",
        name: "promptRejectQrScan",
        desc:
            "Button to reject QR scan confirmation and cancel the verification",
      );

  String get labelVerificationUnlockSsss => Intl.message(
        "Unlock your cross-signing keys",
        name: "labelVerificationUnlockSsss",
        desc:
            "Heading shown during verification when secret storage must be unlocked to sign the verified user or device",
      );

  String get messageVerificationUnlockSsss => Intl.message(
        "Enter your recovery key or security phrase to sign this verification across your devices.",
        name: "messageVerificationUnlockSsss",
        desc:
            "Explains why a recovery key or security phrase is requested during verification",
      );

  String get placeholderVerificationSsssInput => Intl.message(
        "Recovery key or security phrase",
        name: "placeholderVerificationSsssInput",
        desc:
            "Placeholder in the input field used to unlock secret storage during key verification",
      );

  String get promptSkipVerificationSigning => Intl.message(
        "Skip signing",
        name: "promptSkipVerificationSigning",
        desc:
            "Button to continue verification without unlocking cross-signing secret storage",
      );

  String get messageVerificationCancelled => Intl.message(
        "Verification was cancelled.",
        name: "messageVerificationCancelled",
        desc: "Shown when either party cancels a key verification session",
      );

  String get messageVerificationTimedOut => Intl.message(
        "Verification timed out. Start a new request to try again.",
        name: "messageVerificationTimedOut",
        desc: "Shown when a key verification request expires before completion",
      );

  String get messageVerificationKeyMismatch => Intl.message(
        "Verification failed because the security keys did not match.",
        name: "messageVerificationKeyMismatch",
        desc:
            "Shown when a key verification is cancelled due to mismatched keys or QR secret",
      );

  String get messageVerificationSasMismatch => Intl.message(
        "Verification failed because the emoji or numbers did not match.",
        name: "messageVerificationSasMismatch",
        desc:
            "Shown when a SAS verification is cancelled because the emoji or numbers did not match",
      );

  String get messageVerificationAcceptedElsewhere => Intl.message(
        "This verification request was accepted on another device.",
        name: "messageVerificationAcceptedElsewhere",
        desc:
            "Shown when another device of the same account accepted the verification request first",
      );

  String get messageVerificationUnsupportedMethod => Intl.message(
        "No compatible verification method was found.",
        name: "messageVerificationUnsupportedMethod",
        desc:
            "Shown when two clients do not share any supported E2EE verification method",
      );

  String get messageVerificationInvalidSecret => Intl.message(
        "Verification failed because the QR secret or message was invalid.",
        name: "messageVerificationInvalidSecret",
        desc:
            "Shown when verification is cancelled due to an invalid message or mismatched QR reciprocate secret",
      );

  String get messageVerificationFailed => Intl.message(
        "Verification failed. Please try again.",
        name: "messageVerificationFailed",
        desc:
            "Fallback error message when a key verification fails for an unspecified reason",
      );

  /// The SAS emoji's names by their number (the Matrix spec's list), as
  /// the keys of [labelRoomVerificationEmojiName].
  static const _sasEmojiKeys = [
    "dog",
    "cat",
    "lion",
    "horse",
    "unicorn",
    "pig",
    "elephant",
    "rabbit",
    "panda",
    "rooster",
    "penguin",
    "turtle",
    "fish",
    "octopus",
    "butterfly",
    "flower",
    "tree",
    "cactus",
    "mushroom",
    "globe",
    "moon",
    "cloud",
    "fire",
    "banana",
    "apple",
    "strawberry",
    "corn",
    "pizza",
    "cake",
    "heart",
    "smiley",
    "robot",
    "hat",
    "glasses",
    "spanner",
    "santa",
    "thumbsUp",
    "umbrella",
    "hourglass",
    "clock",
    "gift",
    "lightBulb",
    "book",
    "pencil",
    "paperclip",
    "scissors",
    "lock",
    "key",
    "hammer",
    "telephone",
    "flag",
    "train",
    "bicycle",
    "aeroplane",
    "rocket",
    "trophy",
    "ball",
    "guitar",
    "trumpet",
    "bell",
    "anchor",
    "headphones",
    "folder",
    "pin",
  ];

  String labelRoomVerificationEmojiName(String emoji) => Intl.select(
        emoji,
        {
          "dog": "Dog",
          "cat": "Cat",
          "lion": "Lion",
          "horse": "Horse",
          "unicorn": "Unicorn",
          "pig": "Pig",
          "elephant": "Elephant",
          "rabbit": "Rabbit",
          "panda": "Panda",
          "rooster": "Rooster",
          "penguin": "Penguin",
          "turtle": "Turtle",
          "fish": "Fish",
          "octopus": "Octopus",
          "butterfly": "Butterfly",
          "flower": "Flower",
          "tree": "Tree",
          "cactus": "Cactus",
          "mushroom": "Mushroom",
          "globe": "Globe",
          "moon": "Moon",
          "cloud": "Cloud",
          "fire": "Fire",
          "banana": "Banana",
          "apple": "Apple",
          "strawberry": "Strawberry",
          "corn": "Corn",
          "pizza": "Pizza",
          "cake": "Cake",
          "heart": "Heart",
          "smiley": "Smiley",
          "robot": "Robot",
          "hat": "Hat",
          "glasses": "Glasses",
          "spanner": "Spanner",
          "santa": "Santa",
          "thumbsUp": "Thumbs Up",
          "umbrella": "Umbrella",
          "hourglass": "Hourglass",
          "clock": "Clock",
          "gift": "Gift",
          "lightBulb": "Light Bulb",
          "book": "Book",
          "pencil": "Pencil",
          "paperclip": "Paperclip",
          "scissors": "Scissors",
          "lock": "Lock",
          "key": "Key",
          "hammer": "Hammer",
          "telephone": "Telephone",
          "flag": "Flag",
          "train": "Train",
          "bicycle": "Bicycle",
          "aeroplane": "Aeroplane",
          "rocket": "Rocket",
          "trophy": "Trophy",
          "ball": "Ball",
          "guitar": "Guitar",
          "trumpet": "Trumpet",
          "bell": "Bell",
          "anchor": "Anchor",
          "headphones": "Headphones",
          "folder": "Folder",
          "pin": "Pin",
          "other": "$emoji",
        },
        name: "labelRoomVerificationEmojiName",
        args: [emoji],
        desc:
            "The name under each emoji while verifying a session by comparing emoji (the Matrix spec's list of 64), picked by its English key. Translate each name; other is never shown",
      );

  /// The name shown under a SAS emoji, in the app's language.
  String sasEmojiName(KeyVerificationEmoji emoji) {
    if (emoji.number < 0 || emoji.number >= _sasEmojiKeys.length) {
      return emoji.name;
    }
    return labelRoomVerificationEmojiName(_sasEmojiKeys[emoji.number]);
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: determineStage(context),
      ),
    );
  }

  Widget determineStage(BuildContext context) {
    switch (widget.state) {
      case KeyVerificationState.askAccept:
        return promptAcceptRequest(context);
      case KeyVerificationState.askSSSS:
        return promptUnlockSsss(context);
      case KeyVerificationState.askChoice:
        return promptChoice(context);
      case KeyVerificationState.askSas:
        return promptAskSas(context);
      case KeyVerificationState.showQRSuccess:
        return showQrSuccess(context);
      case KeyVerificationState.confirmQRScan:
        return confirmQrScan(context);
      case KeyVerificationState.done:
        return done(context);
      case KeyVerificationState.waitingAccept:
        return waitingView(
          context,
          widget.isSelfVerification
              ? messageWaitingOtherDeviceToAccept
              : messageWaitingOtherUserToAccept(widget.userID),
        );
      case KeyVerificationState.waitingSas:
        return waitingView(context, messageWaitingOtherPartyToConfirm);
      case KeyVerificationState.error:
        return errorView(context);
    }
  }

  Widget promptAcceptRequest(BuildContext context) {
    final promptText = widget.isSelfVerification
        ? messageMatrixSessionVerificationRequest(widget.userID)
        : messageMatrixUserVerificationRequest(widget.userID);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        MarkdownBody(data: promptText),
        tiamat.Button.success(
          key: const ValueKey('verification-accept'),
          text: CommonStrings.promptAccept,
          isLoading: widget.isBusy,
          onTap: widget.onVerificationRequestAccepted?.call,
        ),
        tiamat.Button.danger(
          key: const ValueKey('verification-reject'),
          text: CommonStrings.promptReject,
          onTap: widget.isBusy
              ? null
              : () => widget.onVerificationRequestRejected?.call(),
        ),
      ],
    );
  }

  Widget promptUnlockSsss(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        tiamat.Text.labelEmphasised(labelVerificationUnlockSsss),
        tiamat.Text.label(messageVerificationUnlockSsss),
        tiamat.TextInput(
          key: const ValueKey('verification-ssss-field'),
          controller: _ssssController,
          placeholder: placeholderVerificationSsssInput,
          obscureText: true,
          onSubmitted: (value) => widget.onUnlockSsss?.call(value),
        ),
        if (widget.ssssError != null)
          tiamat.Text.error(
            widget.ssssError!,
            key: const ValueKey('verification-ssss-error'),
          ),
        tiamat.Button(
          key: const ValueKey('verification-ssss-submit'),
          text: CommonStrings.promptConfirm,
          isLoading: widget.isBusy,
          onTap: () => widget.onUnlockSsss?.call(_ssssController.text),
        ),
        tiamat.Button.secondary(
          key: const ValueKey('verification-ssss-skip'),
          text: promptSkipVerificationSigning,
          onTap: widget.isBusy ? null : () => widget.onSkipSsss?.call(),
        ),
        if (widget.onCancel != null) _cancelButton(),
      ],
    );
  }

  Widget promptChoice(BuildContext context) {
    final qrBytes = widget.qrDataRawBytes;
    final canShowQr =
        widget.possibleMethods.contains(matrix.EventTypes.QRShow) &&
            qrBytes != null &&
            qrBytes.isNotEmpty;
    final canScanQr = widget.possibleMethods.contains(matrix.EventTypes.QRScan);
    final canUseSas = widget.possibleMethods.contains(matrix.EventTypes.Sas);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        if (canShowQr || canScanQr)
          tiamat.Text.labelEmphasised(labelVerificationQrTitle),
        if (canShowQr) ...[
          tiamat.Text.label(messageVerificationQrScanPrompt),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 200,
                  child: PrettyQrView(
                    key: const ValueKey('verification-qr-view'),
                    qrImage: QrImage(
                      QrCode.fromUint8List(
                        data: qrBytes,
                        errorCorrectLevel: QrErrorCorrectLevel.L,
                      ),
                    ),
                    decoration: const PrettyQrDecoration(
                      quietZone: PrettyQrQuietZone.standard,
                      shape: PrettyQrSquaresSymbol(color: Colors.black),
                      background: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
          tiamat.Button.secondary(
            key: const ValueKey('verification-qr-copy'),
            text: _qrCopied
                ? CommonStrings.promptCopyComplete
                : promptCopyQrPayload,
            onTap: () {
              Clipboard.setData(
                ClipboardData(
                  text: MatrixQrVerificationPayload.encodeText(qrBytes),
                ),
              );
              setState(() => _qrCopied = true);
            },
          ),
        ],
        if (canScanQr) ...[
          if (canShowQr) const Divider(),
          tiamat.Text.label(labelVerificationQrNoCameraTitle),
          tiamat.TextInput(
            key: const ValueKey('verification-qr-payload-field'),
            controller: _qrInputController,
            placeholder: placeholderVerificationQrPayload,
            maxLines: 2,
            minLines: 1,
            onChanged: (_) => widget.onQrPayloadInputChanged?.call(),
            onSubmitted: (value) => widget.onSubmitQrPayloadText?.call(value),
          ),
          if (widget.qrPayloadError != null)
            tiamat.Text.error(
              widget.qrPayloadError!,
              key: const ValueKey('verification-qr-error'),
            ),
          tiamat.Button(
            key: const ValueKey('verification-qr-submit'),
            text: promptVerifyQrPayload,
            isLoading: widget.isBusy,
            onTap: () =>
                widget.onSubmitQrPayloadText?.call(_qrInputController.text),
          ),
          if (widget.onLoadQrPayloadFile != null)
            tiamat.Button.secondary(
              key: const ValueKey('verification-qr-load-file'),
              text: promptLoadQrPayloadFile,
              onTap: widget.isBusy
                  ? null
                  : () => widget.onLoadQrPayloadFile?.call(),
            ),
        ],
        if (canUseSas) ...[
          if (canShowQr || canScanQr) const Divider(),
          tiamat.Button.secondary(
            key: const ValueKey('verification-start-sas'),
            text: promptVerifyWithEmoji,
            isLoading: widget.isBusy && !canScanQr,
            onTap: widget.isBusy ? null : () => widget.onStartSas?.call(),
          ),
        ],
        if (widget.onCancel != null) _cancelButton(),
      ],
    );
  }

  Widget showQrSuccess(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        const Center(
          child: Icon(
            Icons.verified_user_rounded,
            color: Colors.green,
            size: 72,
          ),
        ),
        tiamat.Text.label(
          messageVerificationQrScannedWaiting,
          key: const ValueKey('verification-qr-success-message'),
        ),
        loading(context),
        if (widget.onCancel != null) _cancelButton(),
      ],
    );
  }

  Widget confirmQrScan(BuildContext context) {
    final promptText = widget.isSelfVerification
        ? messageVerificationConfirmQrScan
        : messageVerificationConfirmQrScanUser(widget.userID);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        const Center(
          child: Icon(
            Icons.qr_code_scanner_rounded,
            size: 56,
          ),
        ),
        tiamat.Text.label(
          promptText,
          key: const ValueKey('verification-qr-confirm-message'),
        ),
        tiamat.Button.success(
          key: const ValueKey('verification-qr-confirm-yes'),
          text: promptConfirmQrScanMatches,
          isLoading: widget.isBusy,
          onTap: widget.onConfirmQrScan?.call,
        ),
        tiamat.Button.danger(
          key: const ValueKey('verification-qr-confirm-no'),
          text: promptRejectQrScan,
          onTap: widget.isBusy ? null : () => widget.onRejectQrScan?.call(),
        ),
      ],
    );
  }

  Widget promptAskSas(BuildContext context) {
    if (widget.sasTypes.contains('emoji')) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          tiamat.Text.label(messageSasEmojiVerificationPrompt),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: widget.sasEmoji
                .map(
                  (e) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      EmojiWidget(
                        UnicodeEmoticon(e.emoji),
                        height: 30,
                      ),
                      const SizedBox(height: 4),
                      tiamat.Text.tiny(sasEmojiName(e)),
                    ],
                  ),
                )
                .toList(),
          ),
          tiamat.Button.success(
            key: const ValueKey('verification-sas-accept'),
            text: promptConfirmEmojiMatches,
            isLoading: widget.isBusy,
            onTap: widget.onSasAccepted?.call,
          ),
          tiamat.Button.danger(
            key: const ValueKey('verification-sas-reject'),
            text: promptEmojiDoNotMatch,
            onTap: widget.isBusy ? null : () => widget.onSasRejected?.call(),
          ),
        ],
      );
    }

    if (widget.sasTypes.contains('decimal') && widget.sasNumbers.isNotEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          tiamat.Text.label(messageSasDecimalVerificationPrompt),
          Center(
            child: Text(
              widget.sasNumbers.map((n) => n.toString()).join('   '),
              key: const ValueKey('verification-sas-numbers'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontFamily: 'Code',
                  ),
            ),
          ),
          tiamat.Button.success(
            key: const ValueKey('verification-sas-accept'),
            text: promptConfirmEmojiMatches,
            isLoading: widget.isBusy,
            onTap: widget.onSasAccepted?.call,
          ),
          tiamat.Button.danger(
            key: const ValueKey('verification-sas-reject'),
            text: promptEmojiDoNotMatch,
            onTap: widget.isBusy ? null : () => widget.onSasRejected?.call(),
          ),
        ],
      );
    }

    return waitingView(context, messageWaitingOtherPartyToConfirm);
  }

  Widget waitingView(BuildContext context, String message) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        tiamat.Text.label(message),
        loading(context),
        if (widget.onCancel != null) _cancelButton(),
      ],
    );
  }

  Widget done(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Icon(
              Icons.verified_user_rounded,
              color: Colors.green,
              size: 84,
            ),
          ),
        ),
        tiamat.Button.success(
          key: const ValueKey('verification-done-close'),
          text: messageVerificationComplete,
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget errorView(BuildContext context) {
    final code = widget.canceledCode;
    final IconData icon;
    final Color color;
    final String message;

    switch (code) {
      case 'm.user':
        icon = Icons.cancel_outlined;
        color = Theme.of(context).colorScheme.error;
        message = messageVerificationCancelled;
      case 'm.timeout':
        icon = Icons.timer_off_outlined;
        color = Theme.of(context).colorScheme.error;
        message = messageVerificationTimedOut;
      case 'm.key_mismatch':
      case 'm.invalid_key':
        icon = Icons.gpp_bad_outlined;
        color = Theme.of(context).colorScheme.error;
        message = messageVerificationKeyMismatch;
      case 'm.mismatched_sas':
        icon = Icons.gpp_bad_outlined;
        color = Theme.of(context).colorScheme.error;
        message = messageVerificationSasMismatch;
      case 'm.accepted':
        icon = Icons.info_outline;
        color = Theme.of(context).colorScheme.primary;
        message = messageVerificationAcceptedElsewhere;
      case 'm.unknown_method':
        icon = Icons.error_outline;
        color = Theme.of(context).colorScheme.error;
        message = messageVerificationUnsupportedMethod;
      case 'm.invalid_message':
        icon = Icons.gpp_bad_outlined;
        color = Theme.of(context).colorScheme.error;
        message = messageVerificationInvalidSecret;
      default:
        icon = Icons.error_outline;
        color = Theme.of(context).colorScheme.error;
        message = messageVerificationFailed;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Center(
            child: Icon(icon, color: color, size: 72),
          ),
        ),
        tiamat.Text.label(
          message,
          key: const ValueKey('verification-error-message'),
        ),
        tiamat.Button.secondary(
          key: const ValueKey('verification-error-close'),
          text: CommonStrings.promptClose,
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _cancelButton() {
    return tiamat.Button.danger(
      key: const ValueKey('verification-cancel'),
      text: CommonStrings.promptCancel,
      onTap: widget.isBusy ? null : () => widget.onCancel?.call(),
    );
  }

  Widget loading(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
