// Discord-style "server emoji" list for a space: upload several images at
// once, rename inline, remove, with a fixed quota. Members see it read-only.
// Editing goes through SpaceEmoticonComponent, which writes to the space's
// default im.ponies pack.
import 'dart:async';

import 'package:rooster/client/components/emoticon/emoticon.dart';
import 'package:rooster/client/components/emoticon/emoticon_component.dart';
import 'package:rooster/client/components/emoticon/space_emoji_library.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/utils/mime.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

class SpaceEmojiSettingsView extends StatefulWidget {
  const SpaceEmojiSettingsView(
      {required this.component, required this.editable, super.key});

  final SpaceEmoticonComponent component;
  final bool editable;

  @override
  State<SpaceEmojiSettingsView> createState() => _SpaceEmojiSettingsViewState();
}

class _SpaceEmojiSettingsViewState extends State<SpaceEmojiSettingsView> {
  StreamSubscription? _sub;
  String? _uploadStatus;
  String? _error;

  SpaceEmoticonComponent get component => widget.component;

  String labelSpaceEmojiUploadProgress(int current, int total) => Intl.message(
      "Uploading $current of $total...",
      name: "labelSpaceEmojiUploadProgress",
      args: [current, total],
      desc:
          "In a space's emoji settings, while several picked images are uploaded as emoji: which one is being uploaded, of how many");

  String messageSpaceEmojiCouldNotRead(String fileName) => Intl.message(
      "$fileName: could not read the file",
      name: "messageSpaceEmojiCouldNotRead",
      args: [fileName],
      desc:
          "In a space's emoji settings, one line of the errors after an upload: a picked image file that could not be read, with its file name");

  String messageSpaceEmojiFileFailed(String fileName, String error) =>
      Intl.message("$fileName: $error",
          name: "messageSpaceEmojiFileFailed",
          args: [fileName, error],
          desc:
              "In a space's emoji settings, one line of the errors after an upload: a picked image's file name, then why it could not be added");

  String promptSpaceEmojiRemoveConfirm(String shortcode) => Intl.message(
      "Remove :$shortcode: from this space?",
      name: "promptSpaceEmojiRemoveConfirm",
      args: [shortcode],
      desc:
          "Confirmation before removing one of a space's emoji, with the emoji's name between colons (keep the colons)");

  String get errorSpaceEmojiForbidden => Intl.message(
      "You are not allowed to change this space's emoji",
      name: "errorSpaceEmojiForbidden",
      desc:
          "Error in a space's emoji settings when the server refuses a change because we lack the permission");

  String get errorSpaceEmojiTooLarge => Intl.message(
      "The image is too large for the homeserver",
      name: "errorSpaceEmojiTooLarge",
      desc:
          "Error in a space's emoji settings when the server refuses an image for being too large");

  String errorSpaceEmojiRejected(String reason) => Intl.message(
      "The homeserver rejected the request: $reason",
      name: "errorSpaceEmojiRejected",
      args: [reason],
      desc:
          "Error in a space's emoji settings when the server refuses a change, with the server's own reason (usually in English)");

  String get errorSpaceEmojiUnknown => Intl.message("Something went wrong",
      name: "errorSpaceEmojiUnknown",
      desc:
          "Error in a space's emoji settings when a change failed for an unknown reason");

  String get labelSpaceEmojiServerEmojis => Intl.message("Server emojis",
      name: "labelSpaceEmojiServerEmojis",
      desc:
          "Header of a space's own emoji list in its settings (as Discord's server emoji: the space plays the part of a Discord server)");

  String labelSpaceEmojiSlotsUsed(int quota, int used) => Intl.plural(quota,
      one: "$used of 1 slot used",
      other: "$used of $quota slots used",
      name: "labelSpaceEmojiSlotsUsed",
      args: [quota, used],
      desc:
          "Under the header of a space's emoji list: how many of the space's emoji slots are taken, of how many there are");

  String get promptSpaceEmojiAdd => Intl.message("Add emoji",
      name: "promptSpaceEmojiAdd",
      desc:
          "Button in a space's emoji settings that picks images to upload as the space's emoji");

  String get labelSpaceEmojiHelp => Intl.message(
      "PNG, GIF or WebP. Names use letters, numbers and underscores. "
      "Every member can use these emoji in any room of the space.",
      name: "labelSpaceEmojiHelp",
      desc:
          "Help under the emoji list of a space's settings, for people who may edit it (PNG, GIF and WebP are image formats)");

  String get labelSpaceEmojiEmpty => Intl.message("No emoji yet.",
      name: "labelSpaceEmojiEmpty",
      desc: "In a space's emoji settings, while the space has no emoji");

  @override
  void initState() {
    super.initState();
    _sub = component.onStateChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _upload() async {
    final picked = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true, allowMultiple: true);
    if (picked == null) return;

    setState(() => _error = null);
    final failures = <String>[];

    for (final (i, file) in picked.files.indexed) {
      if (!mounted) return;
      setState(() => _uploadStatus =
          labelSpaceEmojiUploadProgress(i + 1, picked.files.length));

      final data = file.bytes;
      if (data == null) {
        failures.add(messageSpaceEmojiCouldNotRead(file.name));
        continue;
      }

      try {
        await component.addEmoji(
          component.suggestShortcode(file.name),
          data,
          mimeType: Mime.lookupType(file.name, data: data),
          filename: file.name,
        );
      } catch (e, s) {
        Log.onError(e, s, content: 'Failed to upload space emoji');
        failures.add(messageSpaceEmojiFileFailed(file.name, _friendlyError(e)));
      }
    }

    if (mounted) {
      setState(() {
        _uploadStatus = null;
        _error = failures.isEmpty ? null : failures.join('\n');
      });
    }
  }

  Future<String?> _rename(Emoticon emoji, String name) async {
    try {
      if (SpaceEmojiLibrary.validateShortcode(name) == emoji.shortcode) {
        return null;
      }
      await component.renameEmoji(emoji, name);
      return null;
    } catch (e, s) {
      Log.onError(e, s, content: 'Failed to rename space emoji');
      return _friendlyError(e);
    }
  }

  Future<void> _remove(Emoticon emoji) async {
    final confirm = await AdaptiveDialog.confirmation(context,
        prompt: promptSpaceEmojiRemoveConfirm(emoji.shortcode ?? ""),
        dangerous: true);
    if (confirm != true) return;

    try {
      await component.removeEmoji(emoji);
    } catch (e, s) {
      Log.onError(e, s, content: 'Failed to remove space emoji');
      if (mounted) setState(() => _error = _friendlyError(e));
    }
  }

  String _friendlyError(Object e) {
    if (e is SpaceEmojiError) return e.message;
    if (e is matrix.MatrixException) {
      if (e.error == matrix.MatrixError.M_FORBIDDEN) {
        return errorSpaceEmojiForbidden;
      }
      if (e.error == matrix.MatrixError.M_TOO_LARGE) {
        return errorSpaceEmojiTooLarge;
      }
      return errorSpaceEmojiRejected(e.errorMessage);
    }
    return errorSpaceEmojiUnknown;
  }

  @override
  Widget build(BuildContext context) {
    final emoji = component.availableEmoji;
    final used = component.usedEmojiSlots;
    final quota = component.emojiQuota;
    final full = used >= quota;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tiamat.Text.labelEmphasised(labelSpaceEmojiServerEmojis),
                  tiamat.Text.labelLow(labelSpaceEmojiSlotsUsed(quota, used)),
                ],
              ),
            ),
            if (widget.editable)
              tiamat.Button(
                text: promptSpaceEmojiAdd,
                onTap: full || _uploadStatus != null ? null : _upload,
              ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: used / quota),
        ),
        if (widget.editable)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: tiamat.Text.labelLow(labelSpaceEmojiHelp),
          ),
        if (_uploadStatus != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: tiamat.Text.label(_uploadStatus!),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: tiamat.Text.error(_error!),
          ),
        const SizedBox(height: 8),
        if (emoji.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: tiamat.Text.labelLow(labelSpaceEmojiEmpty),
          ),
        for (final e in emoji)
          _SpaceEmojiRow(
            key: ValueKey(e.shortcode),
            emoji: e,
            editable: widget.editable,
            onRename: (name) => _rename(e, name),
            onRemove: () => _remove(e),
          ),
      ],
    );
  }
}

class _SpaceEmojiRow extends StatefulWidget {
  const _SpaceEmojiRow({
    required this.emoji,
    required this.editable,
    required this.onRename,
    required this.onRemove,
    super.key,
  });

  final Emoticon emoji;
  final bool editable;

  /// Returns an error message, or null on success.
  final Future<String?> Function(String name) onRename;
  final VoidCallback onRemove;

  @override
  State<_SpaceEmojiRow> createState() => _SpaceEmojiRowState();
}

class _SpaceEmojiRowState extends State<_SpaceEmojiRow> {
  late final _controller = TextEditingController(text: widget.emoji.shortcode);
  final _focus = FocusNode();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // Focus is also lost when the row is removed.
    if (_saving || !mounted) return;
    setState(() => _saving = true);
    final error = await widget.onRename(_controller.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
      if (error != null) _controller.text = widget.emoji.shortcode!;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Image(image: widget.emoji.image!, fit: BoxFit.contain),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: widget.editable
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: _controller,
                            focusNode: _focus,
                            enabled: !_saving,
                            maxLength: SpaceEmojiLibrary.maxShortcodeLength,
                            decoration: const InputDecoration(
                              isDense: true,
                              counterText: '',
                              prefixText: ':',
                              suffixText: ':',
                            ),
                            onSubmitted: (_) => _focus.unfocus(),
                          ),
                          if (_error != null) tiamat.Text.error(_error!),
                        ],
                      )
                    : tiamat.Text.label(':${widget.emoji.shortcode}:'),
              ),
              if (widget.editable)
                tiamat.IconButton(
                  icon: Icons.delete_outline,
                  size: 20,
                  onPressed: _saving ? null : widget.onRemove,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
