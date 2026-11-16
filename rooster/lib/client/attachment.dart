import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:rooster/cache/file_provider.dart';
import 'package:rooster/diagnostic/speed_log/file_send_trace.dart';
import 'package:rooster/utils/image/image_header.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';
import 'package:rooster/utils/mime.dart';
import 'package:rooster/utils/network/upload_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:mime/mime.dart' as mime;

abstract class Attachment {
  late String? name;
}

abstract class ProcessedAttachment {}

class PendingFileAttachment {
  String? name;
  String? path;
  Uint8List? data;
  String? mimeType;
  int? size;

  Uint8List? thumbnailFile;
  String? thumbnailMime;
  Size? dimensions;
  Duration? length;

  PendingFileAttachment(
      {this.name, this.path, this.data, this.mimeType, this.size}) {
    assert(path != null || data != null);

    mimeType ??= Mime.lookupType(path ?? name ?? "", data: data);
  }

  /// When it was attached to the composer, on the speed log's clock.
  Duration? attachedAt;

  /// Its send from the composer, once Send was pressed.
  AttachmentSend? sending;

  Future<bool>? _location;
  bool? _hasLocation;

  /// Whether the file's metadata says where it was taken (GPS tags): the
  /// question asked before sending it. Read once, from the bytes in memory
  /// or from the file on disk, which the Exif reader reads only as far as
  /// it needs (12 bytes for a format that cannot hold Exif). Started when
  /// the file is attached, so Send usually finds the answer known.
  Future<bool> locationCheck() => _location ??= _readLocation();

  /// [locationCheck]'s answer, null until it is known.
  bool? get hasLocation => _hasLocation;

  Future<bool> _readLocation() async {
    Map<String, IfdTag> exif = const {};
    try {
      final data = this.data;
      if (data != null) {
        exif = await readExifFromBytes(data);
      } else if (path != null && await File(path!).exists()) {
        exif = await readExifFromFile(File(path!));
      }
    } catch (_) {
      // Metadata the reader cannot make sense of says nothing about where
      // the file was taken; the file is sent as before.
    }
    return _hasLocation = exif.keys.any((e) => e.toLowerCase().contains("gps"));
  }

  Future<void> resolve() async {
    if (data != null) return;

    if (path != null) {
      var file = File(path!);
      if (await file.exists()) {
        data = await file.readAsBytes();
        mimeType = mime.lookupMimeType(file.path, headerBytes: data);
      }
    }
  }

  Future<ImagePreparation?>? _imagePreparation;
  Uint8List? _preparedData;
  PreparationCancel? _cancelPreparation;
  bool _discarded = false;

  /// Starts preparing the picture to be sent (size, thumbnail, blurhash;
  /// see `image_preparation.dart`), in the background, so Send finds it
  /// ready. Called when the file is attached; does nothing for a file that
  /// is not a picture or cannot be read.
  Future<void> startImagePreparation({ImagePreparer? preparer}) async {
    // Only a picture is read now: a video or an archive picked by path
    // stays on disk until Send, as before.
    if (!Mime.imageTypes.contains(mimeType)) return;
    try {
      await resolve();
    } catch (_) {
      // Locked or gone for now: nothing is prepared, and Send reads the
      // file again and reports what it finds, as it did before.
      return;
    }
    await imagePreparation(preparer: preparer);
  }

  /// The preparation of the file's current bytes: the one already started
  /// when they have not changed since, else a new one. Null for a file
  /// that is not a picture, and for a picture the engine cannot decode.
  Future<ImagePreparation?> imagePreparation({ImagePreparer? preparer}) {
    final data = this.data;
    if (_discarded || data == null || !Mime.imageTypes.contains(mimeType)) {
      return Future.value(null);
    }
    if (_imagePreparation == null || !identical(_preparedData, data)) {
      _cancelPreparation?.cancel();
      final cancel = _cancelPreparation = PreparationCancel();
      _preparedData = data;
      _imagePreparation =
          (preparer ?? ImagePreparer.instance).prepare(data, cancel: cancel);
    }
    return _imagePreparation!;
  }

  /// The attachment was taken out of the composer before Send: its
  /// preparation leaves the queue, or its result is thrown away, and none
  /// is started again.
  void discard() {
    _discarded = true;
    _cancelPreparation?.cancel();
    _cancelPreparation = null;
    _imagePreparation = null;
    _preparedData = null;
  }

  ImageProvider? getAsImage() {
    if (Mime.imageTypes.contains(mimeType)) {
      if (data != null) {
        return Image.memory(data!).image;
      } else {
        return Image.file(File(path!)).image;
      }
    }

    return null;
  }
}

/// The size a picture is shown at, from its header (no decode): what a
/// pending message reserves for it before it is drawn.
Size? pictureSizeOf(Uint8List? bytes) {
  if (bytes == null) return null;
  final header = readImageHeader(bytes);
  if (header == null) return null;
  return Size(header.width.toDouble(), header.height.toDouble());
}

/// The longest side a local picture is decoded at for a pending message:
/// the timeline draws it at most 500 wide and 200 high.
const int localPictureDecodeSide = 1000;

/// A local picture as a pending message draws it. The composer's slot and
/// the room's pending event both use this for the same bytes, so the
/// picture is decoded once and the second one finds it in the image cache.
ImageProvider localPicture(Uint8List bytes) => ResizeImage(MemoryImage(bytes),
    width: localPictureDecodeSide,
    height: localPictureDecodeSide,
    policy: ResizeImagePolicy.fit);

/// Where a file sent from the composer stands. The app keeps it per
/// transaction id ([AttachmentSend.transactionId]): the Matrix SDK
/// publishes no "uploading" of its own.
enum AttachmentSendStage {
  /// Waiting for its picture's preparation (or its file to be read):
  /// nothing has been handed to the room yet.
  preparing,

  /// Handed to the room: encrypted (in an encrypted room) and uploaded.
  /// Its [AttachmentSend.upload] says how far: encrypting, the count while
  /// the connection takes bytes, waiting for the server, retrying.
  uploading,

  /// Uploaded; its event is being sent.
  sending,

  /// The server answered with the event's id.
  sent,

  /// It did not reach the room: shown, never hidden.
  failed,
}

/// One file sent from the composer, from Send until the server answers or
/// it fails. The chat Send was pressed in ([chatKey], [threadId]) shows
/// it until the room's own pending event takes over ([echoed]) there; that
/// event finds it by [transactionId] to show its stage and time. When the
/// pending event does not show in that chat (a thread's, or the other
/// account's room), the chat keeps showing it until it is sent.
class AttachmentSend extends ChangeNotifier {
  AttachmentSend({
    required this.roomKey,
    String? chatKey,
    this.threadId,
    required this.attachment,
    this.trace,
  })  : chatKey = chatKey ?? roomKey,
        startedAt = clock() {
    _showFile();
  }

  /// The clock the elapsed time is read on: the speed log's. Tests replace
  /// it.
  static Duration Function() clock = FileSendTrace.now;

  /// [Room.localId] of the room it goes to.
  final String roomKey;

  /// [Room.localId] of the chat Send was pressed in: [roomKey], or the same
  /// room in the other account when a prefix picked that one.
  final String chatKey;
  final String? threadId;

  /// Whether the room's own pending event shows in the chat it was sent
  /// from. It does not in a thread's chat (the SDK's pending event has no
  /// thread relation) nor for a message sent as the other account.
  bool get echoShownInItsChat => threadId == null && chatKey == roomKey;

  /// Its file, until the room's pending event shows it: then it is let go.
  PendingFileAttachment? attachment;

  /// Its `file_send` span in the speed log.
  final FileSendTrace? trace;

  /// When Send was pressed for it, or "Retry" after it failed.
  Duration startedAt;

  /// When it was sent or failed: its clock stops there.
  Duration? _endedAt;

  /// Time from [startedAt] to now, or to when it was sent or failed.
  Duration get elapsed => (_endedAt ?? clock()) - startedAt;

  AttachmentSendStage _stage = AttachmentSendStage.preparing;
  AttachmentSendStage get stage => _stage;

  String? _transactionId;

  /// The transaction id the room sends it under, once handed over.
  String? get transactionId => _transactionId;

  bool _echoed = false;

  /// The room's own pending event for it is in the timeline.
  bool get echoed => _echoed;

  /// The picture (or video poster) to show while it is pending; null for
  /// another file, or until its bytes are read.
  Uint8List? preview;

  /// The size to reserve for it, when known.
  Size? size;

  /// Its file's type and name, kept once the file is let go.
  String? mimeType;
  String? name;

  /// Its file's size in bytes, when known: shown at every stage.
  int? fileBytes;

  /// Its uploads, as the HTTP client reports them while the SDK sends it
  /// (`runForUpload` around the send). Apart from this object's own
  /// listeners, so a count does not rebuild every chat's list.
  final UploadProgress upload = UploadProgress();

  bool _encrypting = false;

  /// The room is encrypting it (an encrypted room), before its upload.
  bool get encrypting => _encrypting;

  bool get isPicture => Mime.imageTypes.contains(mimeType);

  bool get isVideo => Mime.videoTypes.contains(mimeType);

  bool get isFinished =>
      _stage == AttachmentSendStage.sent ||
      _stage == AttachmentSendStage.failed;

  void _showFile() {
    final file = attachment;
    if (file == null) return;
    mimeType = file.mimeType;
    name = file.name;
    fileBytes = file.size ?? file.data?.length ?? fileBytes;
    if (Mime.imageTypes.contains(file.mimeType)) {
      preview = file.data;
      size = pictureSizeOf(file.data) ?? size;
    } else if (Mime.videoTypes.contains(file.mimeType)) {
      preview = file.thumbnailFile;
      size = file.dimensions ?? pictureSizeOf(file.thumbnailFile) ?? size;
    }
    _watchPicture();
  }

  ImageStream? _picture;
  ImageStreamListener? _pictureListener;

  /// Follows the decode of the local picture, the one image the chat's slot
  /// and the room's pending event both draw ([localPicture]), so the speed
  /// log knows when it was first painted: at the end of the first frame
  /// after it is decoded. Holding the stream keeps it decoded meanwhile.
  void _watchPicture() {
    final preview = this.preview;
    if (preview == null || _picture != null || isFinished) return;
    final SchedulerBinding scheduler;
    try {
      scheduler = SchedulerBinding.instance;
    } catch (_) {
      return; // No frames to paint in (a plain unit test).
    }
    trace?.showsPreview();
    final stream =
        _picture = localPicture(preview).resolve(ImageConfiguration.empty);
    final listener = _pictureListener = ImageStreamListener((_, __) {
      _stopWatchingPicture();
      scheduler.addPostFrameCallback((_) => trace?.previewPainted());
      scheduler.ensureVisualUpdate();
    }, onError: (_, __) => _stopWatchingPicture());
    stream.addListener(listener);
  }

  void _stopWatchingPicture() {
    final listener = _pictureListener;
    _pictureListener = null;
    if (listener != null) _picture?.removeListener(listener);
  }

  /// Its file was read (a file picked by path is read at Send): the
  /// picture can be shown now.
  void fileRead() {
    _showFile();
    notifyListeners();
  }

  /// Handed to the room under [transactionId]: [bytes] of file, and
  /// [uploadBytes] to upload with its thumbnail.
  void handedOver(String transactionId, {int? bytes, int? uploadBytes}) {
    _transactionId = transactionId;
    fileBytes = bytes ?? fileBytes;
    upload.expectedBytes = uploadBytes ?? bytes ?? fileBytes;
    _set(AttachmentSendStage.uploading);
  }

  /// The room said it is encrypting the file.
  void encryptingFile() {
    if (_encrypting || _stage != AttachmentSendStage.uploading) return;
    _encrypting = true;
    notifyListeners();
  }

  /// The room's pending event for it is in the timeline: the chat's own
  /// slot gives way to it, and the file is let go.
  void echo() {
    if (_echoed) return;
    _echoed = true;
    attachment = null;
    trace?.echoed();
    notifyListeners();
  }

  /// Uploaded: its event is being sent.
  void uploaded() => _set(AttachmentSendStage.sending);

  /// "Retry" on its failed message: it is being uploaded again, its time
  /// counted from now.
  void retrying() {
    if (_stage != AttachmentSendStage.failed) return;
    startedAt = clock();
    _endedAt = null;
    _stage = AttachmentSendStage.uploading;
    _encrypting = false;
    upload.reset();
    notifyListeners();
  }

  void sent() {
    _set(AttachmentSendStage.sent);
    _stopWatchingPicture();
    trace?.finish(ok: true);
    AttachmentSends.instance.remove(this);
  }

  void failed() {
    _set(AttachmentSendStage.failed);
    _stopWatchingPicture();
    trace?.finish(ok: false);
  }

  void _set(AttachmentSendStage stage) {
    if (_stage == stage || isFinished) return;
    _stage = stage;
    if (isFinished) _endedAt = clock();
    notifyListeners();
  }
}

/// The files being sent from the composer, in every room and account.
class AttachmentSends extends ChangeNotifier {
  static final AttachmentSends instance = AttachmentSends();

  final List<AttachmentSend> _sends = [];

  void add(AttachmentSend send) {
    _sends.add(send);
    send.addListener(notifyListeners);
    notifyListeners();
  }

  /// Takes [send] off the list: sent, or a failure the person dismissed.
  void remove(AttachmentSend send) {
    if (!_sends.remove(send)) return;
    send.removeListener(notifyListeners);
    notifyListeners();
  }

  /// The files the chat of [chatKey] (and [threadId]) shows itself: those
  /// sent from it whose pending event is not in its timeline (yet, or at
  /// all), until they are sent.
  List<AttachmentSend> inComposerOf(String chatKey, String? threadId) => [
        for (final send in _sends)
          if (send.chatKey == chatKey &&
              send.threadId == threadId &&
              (!send.echoed || !send.echoShownInItsChat) &&
              send.stage != AttachmentSendStage.sent)
            send
      ];

  /// The send whose pending event in [roomKey] has [transactionId] as its
  /// id.
  AttachmentSend? byTransaction(String roomKey, String transactionId) {
    for (final send in _sends) {
      if (send.roomKey == roomKey && send.transactionId == transactionId) {
        return send;
      }
    }
    return null;
  }

  /// Every send listed, for tests.
  List<AttachmentSend> get all => List.unmodifiable(_sends);

  /// Empties the list, for tests.
  void clear() {
    for (final send in [..._sends]) {
      remove(send);
    }
  }
}

/// "Retry" on a file message whose file this device no longer holds (the
/// app was restarted since): the message stays as it is, failed, and the
/// person is told to attach the file again.
class AttachmentNoLongerHeld implements Exception {
  const AttachmentNoLongerHeld();
}

class FileAttachment implements Attachment {
  @override
  String? name;
  int? fileSize;
  String? mimeType;
  FileProvider file;
  FileAttachment(this.file, {required this.name, this.fileSize, this.mimeType});
}

class ImageAttachment extends FileAttachment {
  final ImageProvider image;
  final double? width;
  final double? height;

  double get aspectRatio =>
      (width != null && height != null) ? (width! / height!) : 1;

  ImageAttachment(
    this.image,
    super.file, {
    required super.name,
    required super.mimeType,
    super.fileSize,
    this.width,
    this.height,
  });
}

class VideoAttachment extends FileAttachment {
  final ImageProvider? thumbnail;
  final double? width;
  final double? height;
  final Duration? duration;

  double get aspectRatio =>
      (width != null && height != null) ? (width! / height!) : 1;

  final Uri? streamUrl;

  VideoAttachment(super.file,
      {super.name,
      required super.mimeType,
      this.thumbnail,
      this.streamUrl,
      this.width,
      this.height,
      this.duration,
      super.fileSize});
}

/// A video still being sent from this device: its poster, or nothing until
/// there is one, at the video's size.
class PendingVideoAttachment extends FileAttachment {
  PendingVideoAttachment(super.file,
      {this.poster,
      required super.name,
      super.mimeType,
      super.fileSize,
      this.width,
      this.height});

  final ImageProvider? poster;
  final double? width;
  final double? height;

  double get aspectRatio =>
      (width != null && height != null && height! > 0) ? (width! / height!) : 1;
}
