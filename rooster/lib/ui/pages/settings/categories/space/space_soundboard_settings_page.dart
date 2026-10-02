// Space Soundboard admin page: add/edit/remove effects.
//
// Only visible to users with canManage (power levels). Enforced again in
// MatrixSpaceSoundboardComponent — hiding UI is not the security boundary.
// Import flow (desktop): choose an audio file, or paste a link to one or to
// a page a source extension takes (docs/source-extensions.md) -> decode a
// window of at most 1 min -> trim to at most 15 s in the editor -> encode
// and upload the clip to MXC -> store per-sound state event. Audio is then
// served from the homeserver, never hotlinked per-click.
// Each sound has an admin volume slider (fallback for sounds normalization
// gets wrong) with a preview at the volume a call would use.
import 'dart:async';
import 'dart:math' as math;

import 'package:rooster/client/components/dj/dj_extension_manifest.dart';
import 'package:rooster/client/components/emoticon/dynamic_emoticon_pack.dart';
import 'package:rooster/client/components/emoticon/emoji_pack.dart';
import 'package:rooster/client/components/emoticon/emoticon.dart';
import 'package:rooster/client/components/emoticon/emoticon_component.dart';
import 'package:rooster/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:rooster/client/components/soundboard/soundboard_component.dart';
import 'package:rooster/client/components/soundboard/soundboard_constraints.dart';
import 'package:rooster/client/components/soundboard/soundboard_emoji.dart';
import 'package:rooster/client/components/soundboard/soundboard_import_service.dart';
import 'package:rooster/client/components/soundboard/soundboard_validation.dart';
import 'package:rooster/client/components/soundboard/soundboard_sound.dart';
import 'package:rooster/client/matrix/components/dj/dj_platform.dart';
import 'package:rooster/client/matrix/components/soundboard/matrix_soundboard_emoji_image.dart';
import 'package:rooster/client/matrix/components/soundboard/matrix_space_soundboard_component.dart';
import 'package:rooster/client/matrix/components/soundboard/soundboard_import_platform.dart';
import 'package:rooster/client/matrix/components/soundboard/soundboard_preview_player.dart';
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/molecules/desktop_app_notice.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/molecules/soundboard_emoji_picker.dart';
import 'package:rooster/ui/molecules/soundboard_trim_editor.dart';
import 'package:rooster/ui/organisms/dj/dj_prompts.dart';
import 'package:rooster/ui/organisms/soundboard/soundboard_call_controller.dart';
import 'package:rooster/utils/emoji/unicode_emoji.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

/// Opens a Space's soundboard page (add a sound, edit the ones there) in a
/// popup, for the places a user reaches it from outside Space settings: the
/// call's soundboard and the entrance sound setting.
Future<void> showSpaceSoundboardDialog(
    BuildContext context, SpaceSoundboardComponent soundboard) {
  return AdaptiveDialog.show(
    context,
    title: 'Soundboard · ${soundboard.space.displayName}',
    scrollable: false,
    builder: (context) {
      final size = MediaQuery.sizeOf(context);
      final desktop = MediaQuery.of(context).desktop;
      return SizedBox(
        width: desktop ? math.min(680, size.width - 80) : size.width,
        height: math.min(640, size.height * (desktop ? 0.8 : 0.7)),
        child: SpaceSoundboardSettingsPage(soundboard: soundboard),
      );
    },
  );
}

class SpaceSoundboardSettingsPage extends StatefulWidget {
  final SpaceSoundboardComponent soundboard;
  const SpaceSoundboardSettingsPage({super.key, required this.soundboard});

  @override
  State<SpaceSoundboardSettingsPage> createState() =>
      _SpaceSoundboardSettingsPageState();
}

class _SpaceSoundboardSettingsPageState
    extends State<SpaceSoundboardSettingsPage> {
  final _linkCtrl = TextEditingController();
  final _startCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  static const _defaultEmoji = SoundboardEmoji.unicode('📢');
  var _emoji = _defaultEmoji;
  late final _changes = _RebuildOnChange(widget.soundboard);
  final _preview = SoundboardPreviewPlayer(
      userVolume: () => SoundboardCallController.userVolume);
  final _import = SoundboardImportPlatform.instance;
  late final _service = SoundboardImportService(
      encode: _import.encode, log: (line) => Log.i('Soundboard import: $line'));
  double _volume = 1.0;
  bool _busy = false;
  bool _loading = false;
  bool _previewBusy = false;
  String? _status;
  String? _error;

  /// Why the last link or file did not load, shown under the link field
  /// where the Load and Choose file buttons are.
  String? _loadError;

  // The audio being made into a sound, the part of it the trim editor
  // shows, and the selection in that part.
  SoundboardSourceFile? _source;
  SoundboardWindow? _window;
  List<double>? _peaks;
  int _startMs = 0;
  int _endMs = 0;

  // The current selection, cut, measured and encoded; null after the
  // selection changes.
  SoundboardClip? _clip;

  static const _waveformBins = 240;

  /// Loads a pasted link once the field stops changing.
  Timer? _autoLoad;
  static const _autoLoadDelay = Duration(milliseconds: 700);

  /// The selection start when the playing preview began, for the playhead.
  int _previewFromMs = 0;

  bool get _idle => !_busy && !_loading && !_previewBusy;

  @override
  void initState() {
    super.initState();
    _linkCtrl.addListener(_onLinkChanged);
  }

  /// A different link than the loaded one drops what was loaded, so "Add
  /// sound" never uploads something other than what the field says.
  void _onLinkChanged() {
    if (_loadError != null) setState(() => _loadError = null);
    _scheduleAutoLoad();
    final source = _source;
    if (source == null || !source.temporary) return;
    if (source.origin != _linkCtrl.text.trim()) setState(_dropSource);
  }

  /// A pasted link loads by itself: nobody has to find the Load button to
  /// see the trim editor.
  void _scheduleAutoLoad() {
    _autoLoad?.cancel();
    final link = _linkCtrl.text.trim();
    if (!_looksLikeLink(link) || _source?.origin == link) return;
    _autoLoad = Timer(_autoLoadDelay, () {
      if (!mounted || !_idle || _linkCtrl.text.trim() != link) return;
      if (_source?.origin == link) return;
      _loadLink();
    });
  }

  static bool _looksLikeLink(String text) {
    final uri = Uri.tryParse(text);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.contains('.');
  }

  @override
  void dispose() {
    _autoLoad?.cancel();
    _dropSource();
    _preview.dispose();
    _changes.dispose();
    _linkCtrl.removeListener(_onLinkChanged);
    _linkCtrl.dispose();
    _startCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _dropSource() {
    final source = _source;
    if (source != null) unawaited(_import.discard(source));
    _source = null;
    _window = null;
    _peaks = null;
    _clip = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.soundboard.canManage) {
      return const Center(
        child: tiamat.Text.labelLow(
            'Only space admins can manage the soundboard.'),
      );
    }
    return ListenableBuilder(
      listenable: _changes,
      builder: (context, _) {
        final sounds = widget.soundboard.sounds;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const tiamat.Text.labelEmphasised('Add sound'),
              const SizedBox(height: 8),
              if (_import.canImport)
                ..._addSection()
              else
                const DesktopAppNotice(
                    '🔊 Clip the best 15 seconds of any YouTube video, X post '
                    'or file and drop it on the soundboard, straight from the '
                    'desktop app.'),
              const SizedBox(height: 16),
              tiamat.Text.labelEmphasised('Sounds (${sounds.length})'),
              const SizedBox(height: 8),
              for (final s in sounds)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: tiamat.Tile.low(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          SoundboardEmojiView(s.emoji,
                              image: _emojiImage(s.emoji)),
                          const SizedBox(width: 10),
                          Expanded(child: tiamat.Text.label(s.name)),
                          if (s.volume != 1.0)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: tiamat.Text.labelLow(
                                  _SoundVolumeField.percent(s.volume)),
                            ),
                          tiamat.IconButton(
                            icon: Icons.edit,
                            size: 16,
                            onPressed: () => _editDialog(s),
                          ),
                          tiamat.IconButton(
                            icon: Icons.delete,
                            size: 16,
                            onPressed: () => _remove(s.soundId),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _addSection() {
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: tiamat.TextInput(
              label: 'Link',
              placeholder: 'A link to an audio file, or to a page a source '
                  'takes',
              controller: _linkCtrl,
              onSubmitted: (_) {
                _autoLoad?.cancel();
                if (_idle) _loadLink();
              },
            ),
          ),
          const SizedBox(width: 8),
          tiamat.Button.secondary(
            text: 'Load',
            isLoading: _loading,
            onTap: _idle ? _loadLink : null,
          ),
          const SizedBox(width: 8),
          tiamat.Button.secondary(
            text: 'Choose file…',
            onTap: _idle ? _chooseFile : null,
          ),
        ],
      ),
      if (_loadError != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: tiamat.Text.error(_loadError!),
        ),
      const SizedBox(height: 4),
      _SourcesNote(onAdd: () => installDjSource(context)),
      if (_loading && _status != null && _source != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: tiamat.Text.labelLow(_status!),
        ),
      ..._trimSection(),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: tiamat.TextInput(
              label: 'Name',
              placeholder: 'Airhorn',
              controller: _nameCtrl,
            ),
          ),
          const SizedBox(width: 8),
          SoundboardEmojiPickerButton(
            value: _emoji,
            packs: _emojiPacks(),
            imageFor: _emojiImage,
            onChanged: (emoji) => setState(() => _emoji = emoji),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _SoundVolumeField(
        volume: _volume,
        previewing: _previewBusy,
        playing: _preview.position,
        onStop: _preview.stop,
        onChanged: (v) {
          setState(() => _volume = v);
          final clip = _clip;
          if (clip != null) _preview.setSoundGain(clip.normalizedGain * v);
        },
        onPreview: _idle && _window != null ? _previewNewSound : null,
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: tiamat.Text.error(_error!),
        ),
      const SizedBox(height: 8),
      tiamat.Button(
        text: 'Add sound',
        isLoading: _busy,
        onTap: _idle && _window != null ? _addSound : null,
      ),
    ];
  }

  /// Whether the source may go on past the window: then the admin picks
  /// where the window starts.
  bool get _isLong {
    final source = _source;
    final window = _window;
    if (source == null || window == null) return false;
    final duration = source.durationMs;
    return window.startMs > 0 ||
        (duration == null
            ? window.durationMs >= SoundboardConstraints.maxWindowMs - 50
            : duration > SoundboardConstraints.maxWindowMs);
  }

  /// What was loaded, where the window is in it, and the trim editor.
  List<Widget> _trimSection() {
    final source = _source;
    final window = _window;
    if (source == null || window == null) {
      return [
        const SizedBox(height: 12),
        _TrimPlaceholder(status: _loading ? _status ?? 'Loading…' : null),
      ];
    }
    final clock = SoundboardImportService.clock;
    final whole = source.durationMs;
    return [
      const SizedBox(height: 12),
      tiamat.Text.label([
        source.title ?? source.origin,
        if (whole != null) clock(whole),
      ].join(' · ')),
      if (_isLong) ...[
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 120,
              child: tiamat.TextInput(
                label: 'Start at',
                placeholder: '1:30',
                controller: _startCtrl,
              ),
            ),
            const SizedBox(width: 8),
            tiamat.Button.secondary(
              text: 'Go',
              onTap: _idle ? _moveWindow : null,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: tiamat.Text.labelLow('Showing ${clock(window.startMs)}–'
                  '${clock(window.startMs + window.durationMs)}. The editor '
                  'shows up to ${SoundboardConstraints.maxWindowMs ~/ 1000} s '
                  'at a time.'),
            ),
          ],
        ),
      ],
      const SizedBox(height: 8),
      ValueListenableBuilder(
        valueListenable: _preview.position,
        builder: (context, position, _) => SoundboardTrimEditor(
          durationMs: window.durationMs,
          peaks: _peaks,
          startMs: _startMs,
          endMs: _endMs,
          playheadMs: position == null
              ? null
              : _previewFromMs + position.inMilliseconds,
          onChanged: (start, end) {
            // The preview plays the old selection: stop it.
            if (_preview.position.value != null) _preview.stop();
            setState(() {
              _startMs = start;
              _endMs = end;
              _clip = null;
            });
          },
        ),
      ),
    ];
  }

  /// Runs [load] with the add section busy, showing what goes wrong under
  /// the link field.
  Future<void> _loadWith(Future<void> Function() load) async {
    setState(() {
      _loading = true;
      _error = null;
      _loadError = null;
      _status = null;
    });
    try {
      await load();
    } on SoundboardImportError catch (e) {
      Log.w('Soundboard import failed: $e');
      if (mounted) setState(() => _loadError = e.message);
    } catch (e, s) {
      Log.onError(e, s, content: 'Soundboard import failed: $e');
      if (mounted) setState(() => _loadError = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadLink() => _loadWith(() async {
        final link = _linkCtrl.text.trim();
        if (link.isEmpty) {
          throw const SoundboardImportError(
              'Paste a link first, or choose a file');
        }
        final source = await _import.fromLink(link,
            onStatus: (status) =>
                mounted ? setState(() => _status = status) : null);
        await _open(source);
      });

  Future<void> _chooseFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose a sound',
      type: FileType.custom,
      allowedExtensions: _import.fileExtensions,
    );
    final path = result?.files.singleOrNull?.path;
    if (path == null || !mounted) return;
    await _loadWith(() async {
      final source = await _import.fromFile(path);
      _linkCtrl.clear();
      await _open(source);
    });
  }

  /// Makes [source] the one being trimmed, opened where it asks to start.
  Future<void> _open(SoundboardSourceFile source) async {
    try {
      await _openWindow(source, source.startMs);
    } catch (_) {
      await _import.discard(source);
      rethrow;
    }
    if (!mounted) return;
    if (_nameCtrl.text.trim().isEmpty && source.title != null) {
      final title = source.title!.trim();
      _nameCtrl.text = title.length > SoundboardConstraints.maxNameLength
          ? title.substring(0, SoundboardConstraints.maxNameLength)
          : title;
    }
  }

  Future<void> _openWindow(SoundboardSourceFile source, int startMs) async {
    final whole = source.durationMs;
    final start = whole == null
        ? math.max<int>(0, startMs)
        : startMs.clamp(0, math.max<int>(0, whole - 1000));
    setState(() => _status = 'Decoding…');
    final pcm = await _import.decode(source,
        startMs: start, maxMs: SoundboardConstraints.maxWindowMs);
    final peaks = pcm.peaks(_waveformBins);
    if (!mounted) {
      await _import.discard(source);
      return;
    }
    setState(() {
      if (!identical(source, _source)) _dropSource();
      _source = source;
      _window = SoundboardWindow(pcm, start);
      _peaks = peaks;
      _clip = null;
      _startMs = 0;
      _endMs = math.min(pcm.durationMs, SoundboardConstraints.maxDurationMs);
      _startCtrl.text = SoundboardImportService.clock(start);
    });
  }

  Future<void> _moveWindow() => _loadWith(() async {
        final source = _source;
        if (source == null) return;
        final start = SoundboardImportService.parseTimeMs(_startCtrl.text);
        if (start == null) {
          throw const SoundboardImportError('Write the start like 1:30 or 90s');
        }
        await _openWindow(source, start);
      });

  /// The selection, cut, measured and encoded once per selection.
  Future<SoundboardClip> _trimmed() async {
    final cached = _clip;
    if (cached != null) return cached;
    final window = _window;
    if (window == null) {
      throw const SoundboardImportError('Load a link or choose a file first');
    }
    final start = _startMs;
    final end = _endMs;
    final clip = await _service.trim(window, startMs: start, endMs: end);
    // Keep it only if the selection didn't move meanwhile.
    if (identical(window, _window) && start == _startMs && end == _endMs) {
      _clip = clip;
    }
    return clip;
  }

  Future<void> _previewNewSound() async {
    setState(() {
      _previewBusy = true;
      _error = null;
    });
    try {
      final clip = await _trimmed();
      _previewFromMs = _startMs;
      await _preview.playBytes(
          clip.bytes, clip.mimeType, clip.normalizedGain * _volume);
    } on SoundboardImportError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e, s) {
      Log.onError(e, s, content: 'Soundboard preview failed: $e');
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _previewBusy = false);
    }
  }

  Future<void> _addSound() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Reject bad input before encoding or uploading anything.
      final name = SoundboardValidator.sanitizeName(_nameCtrl.text);
      final emoji = SoundboardValidator.sanitizeSoundEmoji(_emoji);
      final source = _source;
      final clip = await _trimmed();
      // Upload the trimmed clip to the homeserver (MXC): clients play it
      // from there, never from where it came.
      final mx = (widget.soundboard as MatrixSpaceSoundboardComponent)
          .client
          .getMatrixClient();
      final mxc =
          await mx.uploadContent(clip.bytes, contentType: clip.mimeType);
      Log.i('Soundboard import: uploaded ${clip.bytes.length} bytes '
          'as $mxc');
      await widget.soundboard.addSound(
        name: name,
        emoji: emoji,
        mediaUri: mxc.toString(),
        mimeType: clip.mimeType,
        durationMs: clip.durationMs,
        normalizedGain: clip.normalizedGain,
        volume: _volume,
        // A file's path is nobody else's business.
        sourceUrl: source != null && source.temporary ? source.origin : null,
      );
      Log.i('Soundboard import: added "$name"');
      await _preview.stop();
      _linkCtrl.clear();
      _nameCtrl.clear();
      _startCtrl.clear();
      if (mounted) {
        setState(() {
          _dropSource();
          _emoji = _defaultEmoji;
          _volume = 1.0;
        });
      }
    } on SoundboardImportError catch (e) {
      Log.w('Soundboard import failed: $e');
      if (mounted) setState(() => _error = e.message);
    } on SoundboardValidationError catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } catch (e, s) {
      Log.onError(e, s, content: 'Soundboard import failed: $e');
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String soundId) async {
    try {
      await widget.soundboard.removeSound(soundId);
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    }
  }

  /// Frequently used, the Space's own emoticons, then unicode, like
  /// Discord's picker.
  List<EmoticonPack> _emojiPacks() {
    final space = widget.soundboard.space
            .getComponent<SpaceEmoticonComponent>()
            ?.ownedPacks
            .where((pack) => pack.emoji.isNotEmpty)
            .toList() ??
        [];
    final spaceKeys = {
      for (final pack in space) ...pack.emoji.map((e) => e.key),
    };
    // Recents span every pack the user has; keep unicode and this Space's.
    final recent = widget.soundboard.client
            .getComponent<RecentEmoticonComponent>()
            ?.getRecentTypedEmoticon(null)
            .where((e) => e.image == null || spaceKeys.contains(e.key))
            .toList() ??
        [];
    return [
      if (recent.isNotEmpty)
        DynamicEmoticonPack(
            identifier: 'dynamic_pack_frequently_used_soundboard',
            displayName: 'Frequently Used',
            icon: Icons.schedule,
            emoticons: recent,
            usage: EmoticonUsage.all),
      ...space,
      ...?UnicodeEmojis.packs,
    ];
  }

  ImageProvider? _emojiImage(SoundboardEmoji emoji) =>
      soundboardEmojiImage(emoji, widget.soundboard.client);

  Future<void> _editDialog(SoundboardSound sound) async {
    final nameCtrl = TextEditingController(text: sound.name);
    var picked = sound.emoji;
    final packs = _emojiPacks();
    final preview = SoundboardPreviewPlayer(
        userVolume: () => SoundboardCallController.userVolume);
    var volume = sound.volume;
    var previewing = false;
    String? previewError;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit sound'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SoundboardEmojiPickerButton(
                    value: picked,
                    packs: packs,
                    imageFor: _emojiImage,
                    onChanged: (e) => setDialogState(() => picked = e),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 240,
                    child:
                        tiamat.TextInput(label: 'Name', controller: nameCtrl),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _SoundVolumeField(
                volume: volume,
                previewing: previewing,
                onChanged: (v) {
                  setDialogState(() => volume = v);
                  preview.setSoundGain(sound.normalizedGain * v);
                },
                onPreview: previewing
                    ? null
                    : () async {
                        setDialogState(() {
                          previewing = true;
                          previewError = null;
                        });
                        try {
                          final uri =
                              await SoundboardCallController.resolvePlayableUri(
                                  widget.soundboard.client, sound);
                          await preview.playUri(
                              uri, sound.normalizedGain * volume);
                        } catch (e, s) {
                          Log.onError(e, s,
                              content: 'Soundboard preview failed: $e');
                          previewError = _friendlyError(e);
                        }
                        if (ctx.mounted) {
                          // Also shows previewError, set above.
                          setDialogState(() => previewing = false);
                        }
                      },
              ),
              if (previewError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: tiamat.Text.error(previewError!),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    await preview.dispose();
    if (ok == true) {
      try {
        // Only send the emoji when it changed, so a stored value this
        // build can't validate doesn't block renaming.
        await widget.soundboard.updateSound(sound.soundId,
            name: nameCtrl.text,
            emoji: picked == sound.emoji ? null : picked,
            volume: volume);
      } catch (e) {
        if (mounted) setState(() => _error = _friendlyError(e));
      }
    }
    nameCtrl.dispose();
  }

  String _friendlyError(Object e) {
    // Both errors carry messages written for the admin.
    if (e is SoundboardImportError) return e.message;
    if (e is SoundboardValidationError) return e.message;
    if (e is matrix.MatrixException) {
      if (e.error == matrix.MatrixError.M_FORBIDDEN) {
        return 'You do not have permission to manage sounds.';
      }
      if (e.error == matrix.MatrixError.M_TOO_LARGE) {
        return 'The homeserver rejected the file as too large.';
      }
      return 'The homeserver rejected the request: ${e.errorMessage}';
    }
    if (e is StateError) return e.message;
    return 'Could not add sound: $e';
  }
}

/// "Sound volume" slider (0..200 %) with a preview button.
class _SoundVolumeField extends StatelessWidget {
  final double volume;
  final bool previewing;
  final ValueChanged<double> onChanged;
  final VoidCallback? onPreview;

  /// While it holds a position, the preview plays and the button stops it.
  final ValueListenable<Duration?>? playing;
  final VoidCallback? onStop;

  const _SoundVolumeField({
    required this.volume,
    required this.previewing,
    required this.onChanged,
    required this.onPreview,
    this.playing,
    this.onStop,
  });

  static String percent(double volume) => '${(volume * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const tiamat.Text.labelLow('Sound volume'),
        Row(
          children: [
            const Icon(Icons.volume_up, size: 18),
            Expanded(
              child: tiamat.Slider(
                min: 0.0,
                max: SoundboardConstraints.maxSoundVolume,
                // 5 % steps.
                divisions: (SoundboardConstraints.maxSoundVolume * 20).round(),
                value: volume,
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 48,
              child: tiamat.Text.labelLow(percent(volume)),
            ),
            ValueListenableBuilder(
              valueListenable: playing ?? ValueNotifier<Duration?>(null),
              builder: (context, position, _) =>
                  position != null && onStop != null
                      ? tiamat.Button.secondary(text: 'Stop', onTap: onStop)
                      : tiamat.Button.secondary(
                          text: 'Preview',
                          isLoading: previewing,
                          onTap: onPreview,
                        ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Where the trim editor goes before anything is loaded: says what to do,
/// or what is loading.
class _TrimPlaceholder extends StatelessWidget {
  /// What is loading, or null while waiting for a link or a file.
  final String? status;

  const _TrimPlaceholder({required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = this.status;
    return Container(
      height: SoundboardTrimEditor.height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (status != null) ...[
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
          ] else ...[
            Icon(Icons.graphic_eq, color: colors.onSurfaceVariant),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: tiamat.Text.labelLow(status ??
                'Paste a link or choose a file: its audio shows up here, to '
                    'cut the part you want and hear it before adding it.'),
          ),
        ],
      ),
    );
  }
}

/// Which installed sources take links to pages for the soundboard, and a
/// way to add one.
class _SourcesNote extends StatelessWidget {
  final VoidCallback onAdd;

  const _SourcesNote({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final sources = DjPlatform.instance.sources;
    if (sources == null) return const SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: sources.installed,
      builder: (context, installed, _) {
        final names = [
          for (final source in installed)
            if (source.uses.contains(DjExtensionManifest.useSoundboard))
              source.name,
        ];
        return Row(
          children: [
            Flexible(
              child: tiamat.Text.labelLow(names.isEmpty
                  ? 'Links to pages (a video, a post) need a source extension.'
                  : 'Links to pages go through ${names.join(', ')}.'),
            ),
            TextButton(onPressed: onAdd, child: const Text('Add a source…')),
          ],
        );
      },
    );
  }
}

/// Bridges SpaceSoundboardComponent.onChanged (Stream) to Listenable.
class _RebuildOnChange extends ChangeNotifier {
  late final StreamSubscription<void> _subscription;

  _RebuildOnChange(SpaceSoundboardComponent soundboard) {
    _subscription = soundboard.onChanged.listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
