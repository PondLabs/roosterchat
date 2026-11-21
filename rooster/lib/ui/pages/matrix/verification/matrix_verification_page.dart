import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/key_verification_component/matrix_key_verification_component.dart';
import 'package:rooster/client/matrix/components/key_verification_component/matrix_qr_verification_payload.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/pages/matrix/verification/matrix_verification_view.dart';

class MatrixVerificationPage extends StatefulWidget {
  final KeyVerification request;
  final MatrixKeyVerificationComponent? component;

  /// Optional override for loading a QR payload file without a camera
  /// (defaults to [FilePicker.platform.pickFiles] with `withData: true`,
  /// which works on desktop and web).
  final Future<Uint8List?> Function()? onLoadQrPayloadFile;

  const MatrixVerificationPage({
    required this.request,
    this.component,
    this.onLoadQrPayloadFile,
    super.key,
  });

  @override
  State<MatrixVerificationPage> createState() => MatrixVerificationPageState();
}

class MatrixVerificationPageState extends State<MatrixVerificationPage> {
  void Function()? _originalOnUpdate;
  bool _refreshedOnDone = false;
  bool _isBusy = false;
  String? _qrPayloadError;
  String? _ssssError;

  static String get errorVerificationQrEmpty => Intl.message(
        "Enter or load a QR verification payload first.",
        name: "errorVerificationQrEmpty",
        desc: "Shown in the no-camera QR verification fallback when the user "
            "submits an empty payload field",
      );

  static String get errorVerificationQrInvalidEncoding => Intl.message(
        "This QR payload could not be decoded. Paste the complete verification code and try again.",
        name: "errorVerificationQrInvalidEncoding",
        desc: "Shown when the pasted QR verification payload is not valid "
            "Base64, hexadecimal, or Matrix QR text",
      );

  static String get errorVerificationQrInvalidHeader => Intl.message(
        "This is not a valid Matrix verification QR code.",
        name: "errorVerificationQrInvalidHeader",
        desc: "Shown when a pasted or loaded QR payload does not start with "
            "the Matrix QR verification header",
      );

  static String get errorVerificationQrUnsupportedVersion => Intl.message(
        "This Matrix QR code version is not supported.",
        name: "errorVerificationQrUnsupportedVersion",
        desc: "Shown when a Matrix QR verification payload uses an "
            "unsupported protocol version",
      );

  static String get errorVerificationQrInvalidMode => Intl.message(
        "This QR code uses an unsupported verification mode.",
        name: "errorVerificationQrInvalidMode",
        desc: "Shown when a Matrix QR verification payload declares an "
            "unknown mode byte",
      );

  static String get errorVerificationQrInvalidSession => Intl.message(
        "This QR code does not contain a valid verification session ID.",
        name: "errorVerificationQrInvalidSession",
        desc: "Shown when a Matrix QR verification payload has a corrupted or "
            "missing transaction ID",
      );

  static String get errorVerificationQrTruncated => Intl.message(
        "This QR code payload is incomplete or corrupted.",
        name: "errorVerificationQrTruncated",
        desc: "Shown when a Matrix QR verification payload is shorter than "
            "the required keys and shared secret",
      );

  static String get errorVerificationQrWrongSession => Intl.message(
        "This QR code belongs to a different verification request.",
        name: "errorVerificationQrWrongSession",
        desc: "Shown when the pasted QR payload's transaction ID does not "
            "match the active verification request",
      );

  static String get errorVerificationSsssUnlockFailed => Intl.message(
        "Could not unlock secret storage. Check your recovery key or security phrase and try again.",
        name: "errorVerificationSsssUnlockFailed",
        desc: "Shown during verification when unlocking cross-signing keys "
            "from secret storage fails",
      );

  @override
  void initState() {
    super.initState();
    _attachRequest(widget.request);
  }

  @override
  void didUpdateWidget(MatrixVerificationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request != widget.request) {
      _detachRequest(oldWidget.request);
      _refreshedOnDone = false;
      _qrPayloadError = null;
      _ssssError = null;
      _attachRequest(widget.request);
    }
  }

  @override
  void dispose() {
    _detachRequest(widget.request);
    super.dispose();
  }

  void _attachRequest(KeyVerification request) {
    _originalOnUpdate = request.onUpdate;
    request.onUpdate = () {
      _originalOnUpdate?.call();
      _handleRequestUpdate();
    };
    if (request.state == KeyVerificationState.done) {
      _maybeRefreshDone();
    }
  }

  void _detachRequest(KeyVerification request) {
    request.onUpdate = _originalOnUpdate;
    _originalOnUpdate = null;
  }

  void _handleRequestUpdate() {
    if (widget.request.state == KeyVerificationState.done) {
      _maybeRefreshDone();
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _maybeRefreshDone() {
    if (_refreshedOnDone) return;
    _refreshedOnDone = true;
    final component = widget.component;
    if (component != null) {
      unawaited(component.refreshUserKeys(widget.request.userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final isAskSas = request.state == KeyVerificationState.askSas;
    final qrBytes = request.qrCode == null
        ? null
        : Uint8List.fromList(request.qrCode!.qrDataRawBytes);

    return MatrixVerificationPageView(
      state: request.state,
      // Read SAS values only while in askSas because they are freed afterwards.
      sasTypes: isAskSas ? request.sasTypes : const [],
      sasEmoji: isAskSas ? request.sasEmojis : const [],
      sasNumbers: isAskSas ? request.sasNumbers : const [],
      userID: request.userId,
      isSelfVerification: request.userId == request.client.userID,
      possibleMethods: request.possibleMethods,
      qrDataRawBytes: qrBytes,
      canceledCode: request.canceledCode,
      qrPayloadError: _qrPayloadError,
      ssssError: _ssssError,
      isBusy: _isBusy,
      onSasAccepted: acceptSas,
      onSasRejected: rejectSas,
      onVerificationRequestAccepted: acceptRequest,
      onVerificationRequestRejected: rejectRequest,
      onStartSas: startSas,
      onSubmitQrPayloadText: submitQrPayloadText,
      onLoadQrPayloadFile: loadQrPayloadFile,
      onQrPayloadInputChanged: clearQrError,
      onConfirmQrScan: confirmQrScan,
      onRejectQrScan: rejectQrScan,
      onUnlockSsss: unlockSsss,
      onSkipSsss: skipSsss,
      onCancel: cancelVerification,
    );
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  void clearQrError() {
    if (_qrPayloadError != null && mounted) {
      setState(() => _qrPayloadError = null);
    }
  }

  Future<void> acceptRequest() => _runBusy(() async {
        await widget.request.acceptVerification();
      });

  Future<void> rejectRequest() => _runBusy(() async {
        await widget.request.rejectVerification();
      });

  Future<void> startSas() => _runBusy(() async {
        setState(() => _qrPayloadError = null);
        await widget.request.continueVerification(matrix.EventTypes.Sas);
      });

  Future<void> acceptSas() => _runBusy(() async {
        await widget.request.acceptSas();
      });

  Future<void> rejectSas() => _runBusy(() async {
        await widget.request.rejectSas();
      });

  Future<void> submitQrPayloadText(String text) => _runBusy(() async {
        setState(() => _qrPayloadError = null);
        try {
          final bytes = MatrixQrVerificationPayload.decodeInput(text);
          await _submitValidatedQrBytes(bytes);
        } on QrPayloadFormatException catch (e) {
          if (mounted) {
            setState(() => _qrPayloadError = _formatQrError(e.error));
          }
        }
      });

  Future<void> loadQrPayloadFile() => _runBusy(() async {
        setState(() => _qrPayloadError = null);
        Uint8List? fileBytes;
        try {
          final loader = widget.onLoadQrPayloadFile;
          if (loader != null) {
            fileBytes = await loader();
          } else {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.any,
              allowMultiple: false,
              withData: true,
            );
            fileBytes = result?.files.firstOrNull?.bytes;
          }
        } catch (error, stack) {
          Log.onError(
            error,
            stack,
            content: 'Failed to read QR verification payload file',
          );
          if (mounted) {
            setState(
                () => _qrPayloadError = errorVerificationQrInvalidEncoding);
          }
          return;
        }

        if (fileBytes == null) {
          return;
        }

        try {
          final payload = MatrixQrVerificationPayload.parseFileBytes(fileBytes);
          await _submitValidatedQrBytes(payload.rawBytes);
        } on QrPayloadFormatException catch (e) {
          if (mounted) {
            setState(() => _qrPayloadError = _formatQrError(e.error));
          }
        }
      });

  Future<void> _submitValidatedQrBytes(Uint8List rawBytes) async {
    final component = widget.component;
    if (component != null) {
      await component.submitScannedQrPayload(widget.request, rawBytes);
    } else {
      await MatrixKeyVerificationComponent.submitQrPayload(
        widget.request,
        rawBytes,
      );
    }
  }

  Future<void> confirmQrScan() => _runBusy(() async {
        await widget.request.acceptQRScanConfirmation();
      });

  Future<void> rejectQrScan() => _runBusy(() async {
        final component = widget.component;
        if (component != null) {
          await component.rejectQrScanConfirmation(widget.request);
        } else if (!widget.request.isDone) {
          await widget.request.cancel('m.key_mismatch');
        }
      });

  Future<void> unlockSsss(String keyOrPassphrase) => _runBusy(() async {
        setState(() => _ssssError = null);
        try {
          await widget.request
              .openSSSS(keyOrPassphrase: keyOrPassphrase.trim());
        } catch (error, stack) {
          Log.onError(
            error,
            stack,
            content: 'Failed to unlock SSSS during key verification',
          );
          if (mounted) {
            setState(() => _ssssError = errorVerificationSsssUnlockFailed);
          }
        }
      });

  Future<void> skipSsss() => _runBusy(() async {
        setState(() => _ssssError = null);
        await widget.request.openSSSS(skip: true);
      });

  Future<void> cancelVerification() => _runBusy(() async {
        final component = widget.component;
        if (component != null) {
          await component.cancelVerification(widget.request);
        } else if (!widget.request.isDone) {
          await widget.request.cancel('m.user');
        }
      });

  String _formatQrError(QrPayloadParseError error) => switch (error) {
        QrPayloadParseError.empty => errorVerificationQrEmpty,
        QrPayloadParseError.invalidEncoding =>
          errorVerificationQrInvalidEncoding,
        QrPayloadParseError.invalidHeader => errorVerificationQrInvalidHeader,
        QrPayloadParseError.unsupportedVersion =>
          errorVerificationQrUnsupportedVersion,
        QrPayloadParseError.invalidMode => errorVerificationQrInvalidMode,
        QrPayloadParseError.invalidTransactionId =>
          errorVerificationQrInvalidSession,
        QrPayloadParseError.truncated => errorVerificationQrTruncated,
        QrPayloadParseError.transactionMismatch =>
          errorVerificationQrWrongSession,
      };
}
