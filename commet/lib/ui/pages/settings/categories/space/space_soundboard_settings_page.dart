// Space Soundboard admin page: add/edit/remove effects.
//
// Only visible to users with canManage (power levels). Enforced again in
// MatrixSpaceSoundboardComponent — hiding UI is not the security boundary.
// Import flow: paste MyInstants URL -> resolve -> download (up to 1 min) ->
// trim to at most 15 s in the editor -> upload the clip to MXC -> store
// per-sound state event. Audio is then served from the homeserver,
// never hotlinked per-click.
// Each sound has an admin volume slider (fallback for sounds normalization
// gets wrong) with a preview at the volume a call would use.
import 'dart:async';
import 'dart:math' as math;

import 'package:commet/client/components/emoticon/dynamic_emoticon_pack.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:commet/client/components/soundboard/myinstants_network_probe.dart';
import 'package:commet/client/components/soundboard/myinstants_resolver.dart';
import 'package:commet/client/components/soundboard/soundboard_component.dart';
import 'package:commet/client/components/soundboard/soundboard_constraints.dart';
import 'package:commet/client/components/soundboard/soundboard_emoji.dart';
import 'package:commet/client/components/soundboard/soundboard_import_service.dart';
import 'package:commet/client/components/soundboard/soundboard_validation.dart';
import 'package:commet/client/components/soundboard/soundboard_sound.dart';
import 'package:commet/client/matrix/components/soundboard/matrix_soundboard_emoji_image.dart';
import 'package:commet/client/matrix/components/soundboard/matrix_space_soundboard_component.dart';
import 'package:commet/client/matrix/components/soundboard/soundboard_preview_player.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/molecules/soundboard_emoji_picker.dart';
import 'package:commet/ui/molecules/soundboard_trim_editor.dart';
import 'package:commet/ui/organisms/soundboard/soundboard_call_controller.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

class SpaceSoundboardSettingsPage extends StatefulWidget {
  final SpaceSoundboardComponent soundboard;
  const SpaceSoundboardSettingsPage({super.key, required this.soundboard});

  @override
  State<SpaceSoundboardSettingsPage> createState() =>
      _SpaceSoundboardSettingsPageState();
}

class _SpaceSoundboardSettingsPageState
    extends State<SpaceSoundboardSettingsPage> {
  final _urlCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  static const _defaultEmoji = SoundboardEmoji.unicode('📢');
  var _emoji = _defaultEmoji;
  late final _changes = _RebuildOnChange(widget.soundboard);
  final _preview = SoundboardPreviewPlayer(
      userVolume: () => SoundboardCallController.userVolume);
  double _volume = 1.0;
  bool _busy = false;
  bool _loading = false;
  bool _previewBusy = false;
  String? _error;
  late final _service =
      SoundboardImportService(log: (line) => Log.i('Soundboard import: $line'));

  // Audio fetched for trimming, reused by "Preview" and "Add sound" while the
  // link is the same so it is downloaded once.
  FetchedAudio? _fetched;
  String? _fetchedUrl;
  List<double>? _peaks;
  int _startMs = 0;
  int _endMs = 0;

  // The current selection of [_fetched], cut and measured; null after the
  // selection changes.
  SoundboardClip? _clip;

  static const _waveformBins = 240;

  bool get _idle => !_busy && !_loading && !_previewBusy;

  @override
  void initState() {
    super.initState();
    // Shows or hides the trim editor as the link changes.
    _urlCtrl.addListener(_onUrlChanged);
  }

  void _onUrlChanged() => setState(() {});

  @override
  void dispose() {
    _preview.dispose();
    _changes.dispose();
    _urlCtrl.removeListener(_onUrlChanged);
    _urlCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
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
              const tiamat.Text.labelEmphasised('Add sound from MyInstants'),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: tiamat.TextInput(
                      label: 'MyInstants link',
                      placeholder: 'https://www.myinstants.com/en/instant/... '
                          '(page or .mp3)',
                      controller: _urlCtrl,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 110,
                    child: tiamat.Button.secondary(
                      text: 'Load',
                      isLoading: _loading,
                      onTap: _idle ? _load : null,
                    ),
                  ),
                ],
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
                onChanged: (v) {
                  setState(() => _volume = v);
                  final clip = _clip;
                  if (clip != null) {
                    _preview.setSoundGain(clip.normalizedGain * v);
                  }
                },
                onPreview: _idle ? _previewNewSound : null,
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
                onTap: _idle ? _addSound : null,
              ),
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

  /// The trim editor for the loaded link, or a note when it can't be
  /// trimmed. Empty until the link is loaded.
  List<Widget> _trimSection() {
    final fetched = _fetched;
    if (fetched == null || _fetchedUrl != _urlCtrl.text) return const [];
    final durationMs = fetched.durationMs;
    return [
      const SizedBox(height: 8),
      if (fetched.canTrim && durationMs != null)
        SoundboardTrimEditor(
          durationMs: durationMs,
          peaks: _peaks,
          startMs: _startMs,
          endMs: _endMs,
          onChanged: (start, end) => setState(() {
            _startMs = start;
            _endMs = end;
            _clip = null;
          }),
        )
      else
        tiamat.Text.labelLow(durationMs == null
            ? 'Only MP3 sounds can be trimmed.'
            : '${(durationMs / 1000).toStringAsFixed(2)} s. '
                'Only MP3 sounds can be trimmed.'),
    ];
  }

  Future<FetchedAudio> _fetch(String url) async {
    if (_fetched != null && _fetchedUrl == url) return _fetched!;
    final FetchedAudio fetched;
    try {
      // Each request inside is bounded by SoundboardConstraints.httpTimeout.
      fetched = await _service.importFromPageUrl(url);
    } on MyInstantsRequestError {
      if (!BuildConfig.WEB) unawaited(_probeNetwork(url));
      rethrow;
    }
    final durationMs = fetched.durationMs ?? 0;
    final peaks = fetched.pcm?.peaks(_waveformBins);
    void apply() {
      _fetched = fetched;
      _fetchedUrl = url;
      _peaks = peaks;
      _clip = null;
      _startMs = 0;
      _endMs = fetched.canTrim
          ? math.min(durationMs, SoundboardConstraints.maxDurationMs)
          : durationMs;
    }

    mounted ? setState(apply) : apply();
    return fetched;
  }

  /// The selected part of [fetched], cut and measured once per selection.
  Future<SoundboardClip> _trimmed(FetchedAudio fetched) async {
    final cached = _clip;
    if (cached != null) return cached;
    final start = _startMs;
    final end = _endMs;
    final clip = await _service.trim(fetched, startMs: start, endMs: end);
    // Keep it only if the selection didn't move meanwhile.
    if (identical(fetched, _fetched) && start == _startMs && end == _endMs) {
      _clip = clip;
    }
    return clip;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _fetch(_urlCtrl.text);
    } on MyInstantsValidationError catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } catch (e, s) {
      Log.onError(e, s, content: 'Soundboard import failed: $e');
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _previewNewSound() async {
    setState(() {
      _previewBusy = true;
      _error = null;
    });
    try {
      final fetched = await _fetch(_urlCtrl.text);
      final clip = await _trimmed(fetched);
      await _preview.playBytes(
          clip.bytes, clip.mimeType, clip.normalizedGain * _volume);
    } on MyInstantsValidationError catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
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
    final url = _urlCtrl.text;
    try {
      // Reject bad input before downloading or uploading anything.
      final name = SoundboardValidator.sanitizeName(_nameCtrl.text);
      final emoji = SoundboardValidator.sanitizeSoundEmoji(_emoji);
      final fetched = await _fetch(url);
      final clip = await _trimmed(fetched);
      // Upload the trimmed clip to the homeserver (MXC) — clients stream
      // from here, never from MyInstants per-click.
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
        durationMs: clip.durationMs ?? 3000,
        normalizedGain: clip.normalizedGain,
        volume: _volume,
        sourceUrl: MyInstantsResolver.normalizeUrl(url),
      );
      Log.i('Soundboard import: added "$name"');
      await _preview.stop();
      _urlCtrl.clear();
      _nameCtrl.clear();
      _fetched = null;
      _fetchedUrl = null;
      _peaks = null;
      _clip = null;
      if (mounted) {
        setState(() {
          _emoji = _defaultEmoji;
          _volume = 1.0;
        });
      }
    } on MyInstantsValidationError catch (e) {
      Log.w('Soundboard import failed: $e');
      if (mounted) setState(() => _error = _friendlyError(e));
    } on SoundboardValidationError catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } catch (e, s) {
      Log.onError(e, s, content: 'Soundboard import failed: $e');
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // TEMPORARY: see myinstants_network_probe.dart.
  Future<void> _probeNetwork(String url) {
    final page = Uri.tryParse(MyInstantsResolver.normalizeUrl(url));
    final homeserver = (widget.soundboard as MatrixSpaceSoundboardComponent)
        .client
        .getMatrixClient()
        .homeserver;
    return probeNetwork([
      if (page != null && MyInstantsResolver.isAllowedUrl(page.toString()))
        page
      else
        Uri.parse('https://www.myinstants.com/'),
      if (homeserver != null)
        homeserver.replace(path: '/_matrix/client/versions'),
    ], (line) => Log.i('Soundboard import $line'));
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
    // Both validation errors carry messages written for the admin.
    if (e is MyInstantsValidationError) return e.message;
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

  const _SoundVolumeField({
    required this.volume,
    required this.previewing,
    required this.onChanged,
    required this.onPreview,
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
            SizedBox(
              width: 110,
              child: tiamat.Button.secondary(
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
