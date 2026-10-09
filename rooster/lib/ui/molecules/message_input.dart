import 'dart:async';

import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/emoticon/dynamic_emoticon_pack.dart';
import 'package:rooster/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:rooster/client/components/gif/gif_component.dart';
import 'package:rooster/client/components/polls/poll_component.dart';
import 'package:rooster/config/build_config.dart';
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/adaptive_context_menu.dart';
import 'package:rooster/ui/atoms/emoji_widget.dart';
import 'package:rooster/ui/atoms/keyboard_adaptor.dart';
import 'package:rooster/ui/atoms/random_emoji_button.dart';
import 'package:rooster/ui/atoms/rich_text_field.dart';
import 'package:rooster/ui/molecules/attachment_icon.dart';
import 'package:rooster/ui/molecules/overlapping_panels.dart';
import 'package:rooster/ui/molecules/poll_creator.dart';
import 'package:rooster/ui/molecules/timeline_events/events/timeline_event_view_reply.dart';
import 'package:rooster/ui/organisms/attachment_processor/attachment_processor.dart';
import 'package:rooster/ui/molecules/emoji_picker.dart';
import 'package:rooster/ui/molecules/emoticon_picker.dart';
import 'package:rooster/ui/molecules/gif_picker.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/organisms/chat/chat.dart';
import 'package:rooster/client/components/emoticon/emoji_pack.dart';
import 'package:rooster/client/components/gif/gif_search_result.dart';
import 'package:rooster/utils/autofill_utils.dart';
import 'package:rooster/utils/debounce.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:just_the_tooltip/just_the_tooltip.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:pasteboard/pasteboard.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import '../../client/attachment.dart';
import '../../client/components/emoticon/emoticon.dart';

enum MessageInputSendResult { success, unhandled }

class AttachmentPicker {
  IconData icon;
  String label;

  Function() execute;

  AttachmentPicker(
      {required this.icon, required this.label, required this.execute});
}

class MessageInput extends StatefulWidget {
  const MessageInput(
      {super.key,
      required this.client,
      this.room,
      this.maxHeight = 200,
      this.onSendMessage,
      this.isRoomE2EE = false,
      this.onFocusChanged,
      this.readIndicator,
      this.relatedEventBody,
      this.relatedEventSenderColor,
      this.relatedEventSenderName,
      this.interactionType,
      this.focusKeyboard,
      this.setInputText,
      this.isProcessing = false,
      this.initialText,
      this.enabled = true,
      this.editLastMessage,
      this.hintText,
      this.attachments,
      this.addAttachment,
      this.onTextUpdated,
      this.removeAttachment,
      this.typingIndicatorWidget,
      this.availibleEmoticons,
      this.availibleStickers,
      this.compact = false,
      this.gifComponent,
      this.enableKeyboardAdapter = true,
      this.onReadReceiptsClicked,
      this.findOverrideClient,
      this.onTapOverrideClient,
      this.disableEnterToSend = false,
      this.sendGif,
      this.sendFavoriteGif,
      this.showGifSearch = true,
      this.size = 35,
      this.iconScale = 0.5,
      this.showAttachmentButton = true,
      this.sendSticker,
      this.processAutofill,
      this.cancelReply});
  final double maxHeight;
  final double size;
  final double iconScale;
  final bool isRoomE2EE;
  final bool disableEnterToSend;
  final MessageInputSendResult Function(String message,
      {Client? overrideClient})? onSendMessage;
  final Widget? readIndicator;
  final String? relatedEventBody;
  final String? relatedEventSenderName;
  final String? hintText;
  final String? initialText;
  final bool showAttachmentButton;
  final bool compact;
  final bool enableKeyboardAdapter;
  final Color? relatedEventSenderColor;
  final List<PendingFileAttachment>? attachments;
  final EventInteractionType? interactionType;
  final Stream<void>? focusKeyboard;
  final bool showGifSearch;
  final Stream<String>? setInputText;
  final bool isProcessing;
  final bool enabled;
  final Room? room;
  final Client client;
  final Widget? typingIndicatorWidget;
  final List<EmoticonPack>? availibleEmoticons;
  final List<EmoticonPack>? availibleStickers;
  final GifComponent? gifComponent;
  final void Function()? onReadReceiptsClicked;
  final void Function(Emoticon sticker)? sendSticker;
  final Future<void> Function(GifSearchResult gif)? sendGif;
  final Future<void> Function(FavoriteGif gif)? sendFavoriteGif;
  final void Function(bool focused)? onFocusChanged;
  final Function(String currentText)? onTextUpdated;
  final void Function()? cancelReply;
  final void Function()? editLastMessage;
  final Client? Function(String input)? findOverrideClient;
  final void Function(Client overrideClient)? onTapOverrideClient;
  final void Function(PendingFileAttachment attachment)? addAttachment;
  final void Function(PendingFileAttachment attachment)? removeAttachment;
  final List<AutofillSearchResult> Function(String text)? processAutofill;

  @override
  State<MessageInput> createState() => MessageInputState();
}

class MessageInputState extends State<MessageInput> {
  late FocusNode textFocus;
  FocusNode emojiSearchFocus = FocusNode();
  FocusNode stickerSearchFocus = FocusNode();
  FocusNode gifSearchFocus = FocusNode();
  FocusNode gifPickerSearchFocus = FocusNode();

  late TextEditingController controller;
  late JustTheController emojiOverlayController = JustTheController();
  JustTheController gifTooltipController = JustTheController();

  // ROOSTER: on mobile the picker panel shows the gif picker instead of emoji
  bool showGifPickerPanel = false;

  bool get canSendGifs =>
      widget.showGifSearch &&
      widget.gifComponent != null &&
      widget.sendGif != null;

  String get tooltipGifButton => Intl.message("GIF",
      desc: "Tooltip for the button that opens the gif picker",
      name: "tooltipGifButton");

  String get labelEnableGifSearchTitle => Intl.message("Enable GIF search?",
      desc:
          "Title of the prompt shown when opening the gif picker while gif search is disabled",
      name: "labelEnableGifSearchTitle");

  String labelEnableGifSearchPrompt(proxyUrl, serviceName) => Intl.message(
      "GIF search is provided by $serviceName. Your searches will be sent through $proxyUrl. You can change this later in Settings.",
      desc: "Explains what enabling gif search does",
      args: [proxyUrl, serviceName],
      name: "labelEnableGifSearchPrompt");

  String get promptEnableGifSearch => Intl.message("Enable",
      desc: "Confirms enabling gif search", name: "promptEnableGifSearch");

  String get promptCancelEnableGifSearch => Intl.message("Cancel",
      desc: "Cancels enabling gif search", name: "promptCancelEnableGifSearch");

  String labelChatSendingAs(String name) => Intl.message("Sending as: $name",
      name: "labelChatSendingAs",
      args: [name],
      desc: "Under the message box when the message will be sent from "
          "another of the user's accounts (picked by typing its prefix), "
          "with that account's display name");

  String get labelChatMentionsHeader => Intl.message("MENTIONS",
      name: "labelChatMentionsHeader",
      desc: "Header, in capitals, of the list of people to mention that "
          "opens above the message box while typing @");

  String labelChatMentionPeopleCount(int howMany) => Intl.plural(howMany,
      one: "1 person",
      other: "$howMany people",
      name: "labelChatMentionPeopleCount",
      args: [howMany],
      desc: "Beside the header of the mention list: how many people match "
          "what was typed after @");

  String get labelChatMentionNoMatches => Intl.message("No one found",
      name: "labelChatMentionNoMatches",
      desc: "In the mention list when nobody matches what was typed after @");

  String get labelChatMentionNavigateHint => Intl.message("Navigate",
      name: "labelChatMentionNavigateHint",
      desc: "Keyboard hint at the bottom of the mention list, after the up "
          "and down arrow keys: they move through the list");

  String get labelChatKeyEnter => Intl.message("Enter",
      name: "labelChatKeyEnter",
      desc: "The Enter key as printed on keyboards, drawn as a key cap in the "
          "keyboard hints at the bottom of the mention list");

  String get labelChatMentionSelectHint => Intl.message("Select",
      name: "labelChatMentionSelectHint",
      desc: "Keyboard hint at the bottom of the mention list, after the Enter "
          "key: it picks the highlighted person");

  String get labelChatMentionEveryone =>
      Intl.message("Mention everyone in the room",
          name: "labelChatMentionEveryone",
          desc: "Under @room in the mention list: picking it notifies "
              "everyone in the room");

  String get promptChatAddPoll => Intl.message("Poll",
      name: "promptChatAddPoll",
      desc: "Entry in the menu of the send button, while the message box is "
          "empty, that opens the poll creator");

  String get labelPollCreateTitle => Intl.message("Create Poll",
      name: "labelPollCreateTitle",
      desc: "Title of the dialog where a new poll is written");

  String get promptChatAttachGallery => Intl.message("Gallery",
      name: "promptChatAttachGallery",
      desc: "Choice when adding an attachment to a message (Android): pick "
          "photos from the phone's gallery");

  String get promptChatAttachFile => Intl.message("File",
      name: "promptChatAttachFile",
      desc: "Choice when adding an attachment to a message: pick any file");

  String get promptChatAttachMedia => Intl.message("Media",
      name: "promptChatAttachMedia",
      desc: "Choice when adding an attachment to a message (Android, "
          "developer mode): pick photos and videos");

  String get promptChatAttachTakePhoto => Intl.message("Take a photo",
      name: "promptChatAttachTakePhoto",
      desc: "Choice when adding an attachment to a message (Android): take a "
          "photo with the camera and attach it");

  StreamSubscription? keyboardFocusSubscription;
  StreamSubscription? setInputTextSubscription;
  StreamSubscription? onScopePopInvoked;
  OverlayEntry? entry;
  final layerLink = LayerLink();
  bool showEmotePicker = false;
  bool emotePickerActive = false;
  bool hasEmotePickerOpened = false;
  List<AutofillSearchResult>? autoFillResults;
  Client? senderOverride;
  JustTheController emojiTooltipController = JustTheController();

  KeyboardAdaptorController keyboardAdaptorController =
      KeyboardAdaptorController();

  int? autoFillSelection;
  (int, int)? autoFillRange;
  ScrollController autofillScrollController = ScrollController();

  void unfocus() {
    textFocus.unfocus();
  }

  void onKeyboardFocusRequested() {
    textFocus.requestFocus();
  }

  void onSetInputText(String newText) {
    controller.text = newText;
    controller.selection =
        TextSelection(baseOffset: newText.length, extentOffset: newText.length);

    onTextfieldUpdated(newText);
  }

  @override
  void dispose() {
    keyboardFocusSubscription?.cancel();
    setInputTextSubscription?.cancel();
    preferencesSubscription?.cancel();
    onScopePopInvoked?.cancel();
    // Everything this made, released: the chat subtree is rebuilt on every
    // room switch, and these kept each old composer alive.
    controller.removeListener(controllerListener);
    controller.dispose();
    textFocus.removeListener(onTextFocusChanged);
    textFocus.dispose();
    emojiSearchFocus.dispose();
    stickerSearchFocus.dispose();
    gifSearchFocus.dispose();
    gifPickerSearchFocus.dispose();
    emojiOverlayController.dispose();
    gifTooltipController.dispose();
    emojiTooltipController.dispose();
    autofillScrollController.dispose();
    super.dispose();
  }

  StreamSubscription? preferencesSubscription;

  @override
  void initState() {
    controller = RichTextEditingController(
        client: widget.client, room: widget.room, text: widget.initialText);
    controller.addListener(controllerListener);
    keyboardFocusSubscription =
        widget.focusKeyboard?.listen((_) => onKeyboardFocusRequested());

    setInputTextSubscription = widget.setInputText?.listen(onSetInputText);
    onScopePopInvoked = EventBus.onPopInvoked.stream.listen(onPopped);

    textFocus = FocusNode(onKeyEvent: onKey);
    textFocus.addListener(onTextFocusChanged);

    preferencesSubscription =
        preferences.onSettingChanged.listen((_) => setState(() {}));

    if (preferences.autoFocusMessageTextBox.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        textFocus.requestFocus();
      });
    }

    super.initState();
  }

  String? lastSearchText;

  String? mentionCandidatesRoomId;

  // Rooms lazy-load their members, so only people seen recently are known
  // locally. Fetch the whole list once so anyone can be mentioned, then
  // search again with what the user has typed.
  Future<void> loadAllMentionCandidates() async {
    final room = widget.room;
    if (room == null ||
        room.isMembersListComplete ||
        mentionCandidatesRoomId == room.identifier) {
      return;
    }
    mentionCandidatesRoomId = room.identifier;

    try {
      await room.fetchMembersList(cache: true);
    } catch (_) {
      mentionCandidatesRoomId = null;
      return;
    }

    if (!mounted || widget.room != room || !isMentionAutofill) return;

    final range = autoFillRange!;
    final text = controller.text.substring(range.$1, range.$2);
    final results = widget.processAutofill?.call(text);
    setState(() {
      autoFillResults = results;
      if (results == null || results.isEmpty) {
        autoFillSelection = null;
      } else if (autoFillSelection != null) {
        autoFillSelection = autoFillSelection!.clamp(0, results.length - 1);
      }
      updateAutofillScroll();
    });
  }

  bool get isMentionAutofill {
    final range = autoFillRange;
    if (range == null || range.$1 < 0 || range.$2 > controller.text.length) {
      return false;
    }
    return controller.text.substring(range.$1, range.$2).startsWith('@');
  }

  void moveAutoFillSelection(int delta) {
    final results = autoFillResults;
    if (results == null || results.isEmpty) return;

    setState(() {
      final current = autoFillSelection ?? (delta > 0 ? -1 : 0);
      autoFillSelection = (current + delta) % results.length;
      updateAutofillScroll();
    });
  }

  void onTextfieldUpdated(String value) {
    widget.onTextUpdated?.call(controller.text);
    var range = getAutofillTextRange();

    setState(() {
      senderOverride = widget.findOverrideClient?.call(controller.text);
    });

    if (range.$1 == -1 || range.$2 == -1) {
      return;
    }

    var text = value.substring(range.$1, range.$2);

    if (text == "") {
      setState(() {
        autoFillResults = null;
        autoFillSelection = null;
        autoFillRange = null;
      });
    }

    if (text == lastSearchText) {
      return;
    }

    if (text.isEmpty) {
      setState(() {
        autoFillResults = [];
        autoFillSelection = null;
        updateAutofillScroll();
      });

      return;
    }

    if (text.startsWith('@')) loadAllMentionCandidates();

    var result = widget.processAutofill?.call(text);
    autoFillRange = range;

    setState(() {
      autoFillResults = result;

      if (MediaQuery.sizeOf(context).desktop && result?.isNotEmpty == true) {
        autoFillSelection = 0;
      } else {
        autoFillSelection = null;
      }
      updateAutofillScroll();
    });
  }

  (int, int) getAutofillTextRange({int? cursorPosition}) {
    var cursor = controller.selection.base.offset;

    if (controller.text == "") {
      return (0, 0);
    }

    int start = cursorPosition ?? cursor;
    int end = controller.text.length;

    if (start > 0) {
      start -= 1;
      if (controller.text[start] == ' ') {
        return (0, 0);
      }
    }

    for (int i = start; i >= 0; i--) {
      var char = controller.text[i];
      if (char == ' ') {
        if (i == controller.text.length) {
          start = controller.text.length - 1;
        } else {
          start = i + 1;
        }

        break;
      }

      if (i <= 0) {
        start = 0;
      }
    }

    for (var i = start + 1; i < controller.text.length; i++) {
      var char = controller.text[i];
      if (char == ' ') {
        end = i;
        break;
      }
    }

    return (start, end);
  }

  Debouncer sendDebouncer = Debouncer(delay: Duration(milliseconds: 20));
  void sendMessage() {
    sendDebouncer.run(() {
      if (widget.attachments == null || widget.attachments!.isEmpty) {
        if (controller.text.isEmpty) return;
        if (controller.text.trim().isEmpty) return;
      }

      var result = widget.onSendMessage
          ?.call(controller.text.trim(), overrideClient: senderOverride);

      if (result == MessageInputSendResult.success) {
        controller.text = "";
      }
    });
  }

  void showMoreAttachmentOptions() {}

  // This duration is to try and hide the transition from keyboard popup animation
  Debouncer removeHeightOverrideDebouncer =
      Debouncer(delay: Duration(seconds: 1));

  bool get isInEmojiPicker => showEmotePicker && !textFocus.hasFocus;

  Future<void> toggleEmojiOverlay({bool gif = false}) async {
    var keyboardOpen = await isKeyboardOpen();
    print("Keyboard open: $keyboardOpen");

    setState(() {
      if (MediaQuery.sizeOf(context).mobile) {
        if (showEmotePicker && !keyboardOpen && showGifPickerPanel != gif) {
          // Panel is already open on the other picker, just switch
          showGifPickerPanel = gif;
          emotePickerActive = true;
        } else if (showEmotePicker && !keyboardOpen) {
          // STUPID: since we use android api to dismiss keyboard,
          // requesting focus normally doesnt work, but if we do this
          // we can get the onscreen keyboard back
          unfocus();
          Future.delayed(Duration(milliseconds: 100)).then((_) {
            textFocus.requestFocus();
          });
          emotePickerActive = false;
          clearKeyboardOverride();
        } else {
          showGifPickerPanel = gif;
          showEmotePicker = true;
          emotePickerActive = true;
          keyboardAdaptorController.keepCurrentSize?.call();
          removeHeightOverrideDebouncer.cancel();
          if (textFocus.hasFocus) {
            dismissKeyboard();
          }
        }
      }

      if (MediaQuery.sizeOf(context).desktop) {
        showEmotePicker = !showEmotePicker;
        emotePickerActive = showEmotePicker;
        emojiTooltipController.showTooltip(autoClose: false);
      }

      if (showEmotePicker) {
        hasEmotePickerOpened = true;
      }
    });
  }

  void clearKeyboardOverride({bool debounce = true}) {
    final func = () {
      if (showEmotePicker) {
        showEmotePicker = false;
        emotePickerActive = false;
      }

      if (!showEmotePicker) {
        keyboardAdaptorController.clearOverride?.call();
      }
    };

    if (!debounce) {
      removeHeightOverrideDebouncer.cancel();
      func();
    }

    setState(() {
      emotePickerActive = false;
    });

    removeHeightOverrideDebouncer.run(func);
  }

  void dismissKeyboard() {
    if (BuildConfig.ANDROID) {
      const platform = const MethodChannel('com.pondlabs.rooster/utils');
      platform.invokeMethod("dismissKeyboard");
    }
  }

  Future<bool> isKeyboardOpen() async {
    if (BuildConfig.ANDROID) {
      const platform = const MethodChannel('com.pondlabs.rooster/utils');
      var result = await platform.invokeMethod<bool>("isKeyboardOpen");
      return result!;
    } else {
      return textFocus.hasFocus;
    }
  }

  void onTextFocusChanged() {
    if (textFocus.hasFocus) {
      clearKeyboardOverride();
    }
    // The mention panel only shows while the text box has focus
    if (mounted && isMentionAutofill) {
      setState(() {});
      if (textFocus.hasFocus) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => scrollMentionSelectionIntoView());
      }
    }
  }

  void updateAutofillScroll() {
    if (!autofillScrollController.hasClients) {
      return;
    }
    if (autoFillSelection == null) {
      autofillScrollController.jumpTo(0);
      return;
    }

    if (isMentionAutofill) {
      // Runs after layout, so a fresh result list has its new extents
      WidgetsBinding.instance
          .addPostFrameCallback((_) => scrollMentionSelectionIntoView());
      return;
    }

    int totalChars = 0;
    int selectionChars = 0;
    for (int i = 0; i < autoFillResults!.length; i++) {
      totalChars += autoFillResults![i].result.length;

      if (autoFillSelection! > i) {
        selectionChars += autoFillResults![i].result.length;
      }
    }

    var maxOffset = autofillScrollController.position.maxScrollExtent;

    var amount = selectionChars.toDouble() / totalChars.toDouble();
    var offset = (maxOffset * amount) - 50;

    if (offset < 0) {
      offset = 0;
    }

    var distance = (offset - autofillScrollController.offset).abs();
    var maxDistance =
        autofillScrollController.position.viewportDimension * 0.25;

    if (distance > maxDistance) {
      autofillScrollController.animateTo(offset,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOutExpo);
    }
  }

  void scrollMentionSelectionIntoView() {
    final selection = autoFillSelection;
    final count = autoFillResults?.length ?? 0;
    if (!mounted ||
        selection == null ||
        count == 0 ||
        !autofillScrollController.hasClients) {
      return;
    }

    // Every row has the prototype's height, so the content splits evenly
    final position = autofillScrollController.position;
    final itemExtent =
        (position.maxScrollExtent + position.viewportDimension) / count;
    final itemTop = selection * itemExtent;
    final itemBottom = itemTop + itemExtent;

    double? target;
    if (itemTop < position.pixels) {
      target = itemTop;
    } else if (itemBottom > position.pixels + position.viewportDimension) {
      target = itemBottom - position.viewportDimension;
    }
    if (target == null) return;

    autofillScrollController.animateTo(
        target.clamp(0.0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic);
  }

  bool isKnownAutofillMatch(String text) {
    if (text.startsWith("@") || text.startsWith("!")) {
      return text.isValidMatrixId;
    }

    if (text.startsWith(":") && text.endsWith(":")) {
      return true;
    } else {
      return false;
    }
  }

  TextSelection? prevSelection;

  void controllerListener() {
    if (PlatformUtils.isAndroid) {
      return;
    }

    if (preferences.disableTextCursorManagement.value) {
      return;
    }

    var startFill =
        getAutofillTextRange(cursorPosition: controller.selection.baseOffset);

    var endFill =
        getAutofillTextRange(cursorPosition: controller.selection.extentOffset);

    var len = controller.selection.start - controller.selection.end;

    var baseOffset = controller.selection.baseOffset;
    var extentOffset = controller.selection.extentOffset;

    if (baseOffset == -1 || extentOffset == -1) {
      return;
    }

    var text = controller.text.substring(startFill.$1, startFill.$2);
    var endText = controller.text.substring(endFill.$1, endFill.$2);
    if (isKnownAutofillMatch(text)) {
      // go forward
      if ((prevSelection != null &&
          prevSelection!.baseOffset < controller.selection.baseOffset)) {
        baseOffset = startFill.$2;
      } else {
        // go backward
        if (baseOffset > startFill.$1 && baseOffset != startFill.$2) {
          baseOffset = startFill.$1;
        }
      }
    }

    if (isKnownAutofillMatch(endText) && len != 0) {
      // go forward
      if ((prevSelection != null &&
          prevSelection!.extentOffset < controller.selection.extentOffset)) {
        extentOffset = endFill.$2;
      } else {
        // go backward
        if (extentOffset > endFill.$1) {
          extentOffset = endFill.$1;
        }
      }
    }

    if (len == 0) {
      extentOffset = baseOffset;
    }
    controller.selection =
        TextSelection(baseOffset: baseOffset, extentOffset: extentOffset);

    prevSelection = controller.selection;
  }

  KeyEventResult onKey(FocusNode node, KeyEvent event) {
    final hasAutofillOptions =
        autoFillResults?.isNotEmpty == true && autoFillRange != null;
    final isKeyDown = event is KeyDownEvent || event is KeyRepeatEvent;

    if (hasAutofillOptions &&
        isKeyDown &&
        (event.logicalKey == LogicalKeyboardKey.arrowDown ||
            event.logicalKey == LogicalKeyboardKey.arrowUp)) {
      moveAutoFillSelection(
          event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1);
      return KeyEventResult.handled;
    }

    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        hasAutofillOptions &&
        autoFillSelection != null) {
      applyAutoFill(autoFillResults![autoFillSelection!]);
      return KeyEventResult.handled;
    }

    if (BuildConfig.MOBILE) return KeyEventResult.ignored;

    if (!preferences.disableTextCursorManagement.value) {
      if (HardwareKeyboard.instance
          .isLogicalKeyPressed(LogicalKeyboardKey.backspace)) {
        var selection = controller.selection.baseOffset;
        var selectionEnd = controller.selection.extentOffset;

        var range = getAutofillTextRange();

        if (range.$1 < selection) {
          selection = range.$1;
        }

        if (range.$2 > selectionEnd) {
          selectionEnd = range.$2;
        }

        var text = controller.text.substring(range.$1, range.$2);

        if (isKnownAutofillMatch(text)) {
          controller.text =
              controller.text.replaceRange(selection, selectionEnd, "");
          onTextfieldUpdated(controller.text);
          return KeyEventResult.handled;
        }
      }
    }

    if (HardwareKeyboard.instance
        .isLogicalKeyPressed(LogicalKeyboardKey.keyV)) {
      if (HardwareKeyboard.instance.isControlPressed) {
        readImageFromClipboard();
        return KeyEventResult.ignored;
      }
    }

    if (HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.tab)) {
      if (autoFillResults == null || autoFillResults!.isEmpty) {
        autoFillSelection = null;
        return KeyEventResult.ignored;
      } else {
        if (autoFillSelection == null) {
          setState(() {
            autoFillSelection = 0;
            updateAutofillScroll();
          });
        } else {
          setState(() {
            autoFillSelection = (autoFillSelection! + 1);
            if (autoFillSelection! >= autoFillResults!.length) {
              autoFillSelection = 0;
            }

            updateAutofillScroll();
          });
        }

        return KeyEventResult.handled;
      }
    }

    if (widget.disableEnterToSend != true) {
      if (HardwareKeyboard.instance
          .isLogicalKeyPressed(LogicalKeyboardKey.enter)) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          return KeyEventResult.ignored;
        }

        sendMessage();
        return KeyEventResult.handled;
      }
    }

    if (HardwareKeyboard.instance
        .isLogicalKeyPressed(LogicalKeyboardKey.escape)) {
      doCancelInteraction();
      return KeyEventResult.handled;
    }

    if (HardwareKeyboard.instance
            .isLogicalKeyPressed(LogicalKeyboardKey.arrowUp) &&
        controller.text.isEmpty) {
      widget.editLastMessage?.call();
    }

    return KeyEventResult.ignored;
  }

  void applyAutoFill(AutofillSearchResult result) {
    var replacement = result.slug;

    var checkWhitespaceAt = autoFillRange!.$2;

    if (checkWhitespaceAt < controller.text.length) {
      if (controller.text[checkWhitespaceAt] != " ") {
        replacement = "$replacement ";
      }
    } else {
      replacement = "$replacement ";
    }

    controller.text = controller.text
        .replaceRange(autoFillRange!.$1, autoFillRange!.$2, replacement);
    setState(() {
      autoFillSelection = null;
      autoFillResults = null;
      autoFillRange = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    var padding = const EdgeInsets.fromLTRB(0, 0, 0, 0);

    return Material(
      color: Colors.transparent,
      child: TextFieldTapRegion(
        child: IgnorePointer(
          ignoring: widget.isProcessing,
          child: Opacity(
            opacity: widget.isProcessing ? 0.5 : 1,
            child: KeyboardAdaptor(
              enabled: widget.enableKeyboardAdapter,
              paddingContent:
                  (MediaQuery.sizeOf(context).mobile && showEmotePicker)
                      ? (showGifPickerPanel && canSendGifs
                          ? buildGifPicker()
                          : buildEmojiPicker())
                      : Container(),
              shouldPushContent: () {
                if (emojiSearchFocus.hasFocus) {
                  return true;
                }

                if (gifPickerSearchFocus.hasFocus) {
                  return true;
                }

                if (stickerSearchFocus.hasFocus) {
                  return true;
                }

                if (gifSearchFocus.hasFocus) {
                  return true;
                }

                return false;
              },
              controller: keyboardAdaptorController,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.typingIndicatorWidget != null)
                    widget.typingIndicatorWidget!,
                  if (widget.interactionType != null) interactionText(),
                  if (widget.attachments != null &&
                      widget.attachments!.isNotEmpty)
                    displayAttachments(),
                  if (isMentionAutofill &&
                      autoFillResults != null &&
                      textFocus.hasFocus)
                    mentionAutofillPanel(),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: Padding(
                      padding: padding,
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.enabled && widget.showAttachmentButton)
                              addAttachmentButton(),
                            Flexible(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: Container(
                                  decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerLow),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      textInput(context),
                                      if (widget.enabled && canSendGifs)
                                        toggleGifButton(),
                                      if (widget.enabled) toggleEmojiButton(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (widget.enabled) sendMessageButton()
                          ]),
                    ),
                  ),
                  if (!widget.compact)
                    SizedBox(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 2, 0, 0),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const SizedBox(height: 30),
                              if (senderOverride != null) senderOverrideView(),
                              if (autoFillResults != null && !isMentionAutofill)
                                autofillResultsList(),
                              if (autoFillResults == null || isMentionAutofill)
                                const Expanded(child: SizedBox()),
                            ]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget senderOverrideView() {
    final profile = senderOverride?.self;
    if (profile == null) {
      return Container();
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        height: 30,
        child: ConstrainedBox(
          // A long name, or a longer language, is cut short rather than
          // pushing the row past the edge.
          constraints: const BoxConstraints(maxWidth: 300),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 2, 2),
            child: Material(
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.hardEdge,
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: InkWell(
                onTap: () {
                  widget.onTapOverrideClient?.call(senderOverride!);
                },
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 5,
                      ),
                      tiamat.Avatar(
                          radius: 10,
                          image: profile.avatar,
                          placeholderColor: profile.defaultColor,
                          placeholderText: profile.displayName),
                      SizedBox(
                        width: 10,
                      ),
                      Flexible(
                        child: tiamat.Text.labelLow(
                          labelChatSendingAs(profile.displayName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 5,
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget mentionAutofillPanel() {
    final results = autoFillResults ?? const <AutofillSearchResult>[];
    final colors = Theme.of(context).colorScheme;
    final visibleResults = results;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Material(
        color: colors.surfaceContainerHigh,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: tiamat.Text.labelLow(
                        labelChatMentionsHeader,
                        color: colors.onSurfaceVariant,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    tiamat.Text.labelLow(
                      labelChatMentionPeopleCount(results.length),
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              if (visibleResults.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: tiamat.Text.labelLow(
                    labelChatMentionNoMatches,
                    color: colors.onSurfaceVariant,
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    controller: autofillScrollController,
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    itemCount: visibleResults.length,
                    prototypeItem: mentionAutofillItem(0),
                    itemBuilder: (context, index) => mentionAutofillItem(index),
                  ),
                ),
              Divider(
                height: 1,
                color: colors.outlineVariant.withValues(alpha: 0.5),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 9, 14, 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.keyboard_arrow_up,
                      size: 17,
                      color: colors.onSurfaceVariant,
                    ),
                    Icon(
                      Icons.keyboard_arrow_down,
                      size: 17,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 5),
                    // Takes the room between the two hints, and gives way
                    // first when a language's words are long.
                    Expanded(
                      child: tiamat.Text.labelLow(
                        labelChatMentionNavigateHint,
                        color: colors.onSurfaceVariant,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _KeyboardHint(label: labelChatKeyEnter),
                    const SizedBox(width: 5),
                    tiamat.Text.labelLow(
                      labelChatMentionSelectHint,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget mentionAutofillItem(int index) {
    final results = autoFillResults!;
    final colors = Theme.of(context).colorScheme;
    final result = results[index];
    final selected = autoFillSelection == index;
    final avatar = result is AutofillSearchResultAvatar ? result : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected
            ? colors.secondaryContainer.withValues(
                alpha: 0.72,
              )
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => applyAutoFill(result),
          child: Container(
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 7,
            ),
            child: Row(
              children: [
                if (avatar != null)
                  tiamat.Avatar(
                    image: avatar.image,
                    radius: 17,
                    placeholderColor: avatar.fallbackColor,
                    placeholderText: avatar.result,
                  )
                else
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: colors.secondaryContainer,
                    child: Icon(
                      Icons.alternate_email,
                      size: 17,
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      tiamat.Text.name(result.result),
                      // One line each: every row takes the first row's
                      // height (the list's prototype item).
                      if (avatar != null)
                        tiamat.Text.labelLow(
                          avatar.slug,
                          color: colors.onSurfaceVariant,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      else
                        tiamat.Text.labelLow(
                          labelChatMentionEveryone,
                          color: colors.onSurfaceVariant,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.keyboard_return_rounded,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Expanded autofillResultsList() {
    return Expanded(
      child: ShaderMask(
        shaderCallback: (rect) {
          return const LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.center,
            colors: [
              Colors.purple,
              Colors.transparent,
            ],
            stops: [
              0.0,
              0.1,
            ],
          ).createShader(rect);
        },
        blendMode: BlendMode.dstOut,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
          child: SizedBox(
            height: 30,
            child: Listener(
              onPointerSignal: (event) {
                if (!MediaQuery.sizeOf(context).desktop) return;
                if (event is PointerScrollEvent) {
                  final offset = event.scrollDelta.dy;

                  autofillScrollController.jumpTo(
                      (autofillScrollController.offset + offset).clamp(0,
                          autofillScrollController.position.maxScrollExtent));
                }
              },
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(0, 0, 300, 0),
                itemCount: autoFillResults!.length,
                controller: autofillScrollController,
                shrinkWrap: true,
                itemBuilder: (context, index) {
                  bool selected = false;
                  var data = autoFillResults![index];
                  if (autoFillSelection != null) {
                    selected = data == autoFillResults![autoFillSelection!];
                  }

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Material(
                      color: selected
                          ? Theme.of(context).colorScheme.secondary
                          : Colors.transparent,
                      child: InkWell(
                        onTap: () => applyAutoFill(data),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 1, 4, 1),
                          child: Row(
                            children: [
                              if (data is AutofillSearchResultEmoticon)
                                EmojiWidget(data.emoticon),
                              if (data is AutofillSearchResultAvatar)
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(0, 0, 3, 0),
                                  child: tiamat.Avatar(
                                      image: data.image,
                                      radius: 10,
                                      placeholderColor: data.fallbackColor,
                                      placeholderText: data.result),
                                ),
                              tiamat.Text.labelLow(
                                data.result,
                                color: selected
                                    ? Theme.of(context).colorScheme.onSecondary
                                    : Theme.of(context).colorScheme.secondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget sendMessageButton() {
    bool canSend =
        controller.text.isNotEmpty || widget.attachments?.isNotEmpty == true;

    var pollComponent = widget.room?.client.getComponent<PollComponent>();

    double targetValue = canSend ? 1 : 0;
    return Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
        child: TweenAnimationBuilder(
          tween: Tween<double>(begin: 0, end: targetValue),
          duration: Durations.medium1,
          builder: (context, value, child) {
            return ClipRRect(
              borderRadius: BorderRadiusGeometry.circular(widget.size),
              child: Material(
                child: AdaptiveContextMenu(
                  modal: true,
                  items: canSend
                      ? List.empty()
                      : [
                          if (pollComponent != null)
                            tiamat.ContextMenuItem(
                              text: promptChatAddPoll,
                              icon: Icons.poll,
                              onPressed: () async {
                                var createArgs =
                                    await AdaptiveDialog.show<PollCreateArgs>(
                                        context,
                                        title: labelPollCreateTitle,
                                        builder: (context) => PollCreator());

                                if (createArgs != null) {
                                  print(createArgs);
                                  pollComponent.createPoll(
                                      widget.room!, createArgs);
                                }
                              },
                            )
                        ],
                  child: SizedBox(
                      width: widget.size,
                      height: widget.size,
                      child: tiamat.CircleButton(
                        icon: canSend ? Icons.send : Icons.more_horiz,
                        radius: widget.size * widget.iconScale,
                        onPressed: canSend
                            ? () {
                                sendMessage();
                              }
                            : null,
                        color: Color.lerp(
                            Theme.of(context).colorScheme.primary.withAlpha(0),
                            Theme.of(context).colorScheme.primary,
                            value),
                        iconColor: Color.lerp(
                            Theme.of(context).colorScheme.secondary,
                            Theme.of(context).colorScheme.onPrimary,
                            value),
                      )),
                ),
              ),
            );
          },
        ));
  }

  Widget toggleEmojiButton() {
    var button = SizedBox(
        width: widget.size,
        height: widget.size,
        child: RandomEmojiButton(
            size: widget.size,
            onTap: toggleEmojiOverlay,
            toggled: MediaQuery.sizeOf(context).mobile
                ? (emojiTooltipController.value == TooltipStatus.isShowing ||
                    (emotePickerActive == true && !showGifPickerPanel))
                : false));

    if (MediaQuery.sizeOf(context).mobile) return button;

    return Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 2, 0),
        child: JustTheTooltip(
          isModal: true,
          preferredDirection: AxisDirection.up,
          controller: emojiTooltipController,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
          onDismiss: () {
            if (MediaQuery.sizeOf(context).desktop) {
              textFocus.requestFocus();
            }
          },
          content: ClipRRect(
            borderRadius: BorderRadiusGeometry.circular(8),
            child: Material(
              child: Container(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: SizedBox(
                  height: 500,
                  width: 500,
                  child: buildEmojiPicker(skipIfNeverOpened: false),
                ),
              ),
            ),
          ),
          child: button,
        ));
  }

  Widget toggleGifButton() {
    Widget buildButton(bool toggled) => SizedBox(
          width: widget.size,
          height: widget.size,
          child: Tooltip(
            message: tooltipGifButton,
            child: tiamat.IconButton(
              icon: Icons.gif_box_outlined,
              size: widget.size * widget.iconScale * 1.3,
              iconColor: toggled ? Theme.of(context).colorScheme.primary : null,
              onPressed: onGifButtonPressed,
            ),
          ),
        );

    if (MediaQuery.sizeOf(context).mobile) {
      return buildButton(emotePickerActive && showGifPickerPanel);
    }

    return JustTheTooltip(
      isModal: true,
      preferredDirection: AxisDirection.up,
      controller: gifTooltipController,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      onDismiss: () {
        if (MediaQuery.sizeOf(context).desktop) {
          textFocus.requestFocus();
        }
      },
      content: ClipRRect(
        borderRadius: BorderRadiusGeometry.circular(8),
        child: Material(
          child: Container(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: SizedBox(
              height: 500,
              width: 450,
              child: buildGifPicker(),
            ),
          ),
        ),
      ),
      child: ValueListenableBuilder(
        valueListenable: gifTooltipController,
        builder: (context, value, _) =>
            buildButton(value == TooltipStatus.isShowing),
      ),
    );
  }

  Future<void> onGifButtonPressed() async {
    if (MediaQuery.sizeOf(context).desktop &&
        gifTooltipController.value == TooltipStatus.isShowing) {
      closeGifPicker();
      return;
    }

    if (!preferences.tenorGifSearchEnabled.value) {
      var enable = await AdaptiveDialog.confirmation(context,
          title: labelEnableGifSearchTitle,
          prompt:
              labelEnableGifSearchPrompt(preferences.proxyUrl.value, "KLIPY"),
          confirmationText: promptEnableGifSearch,
          cancelText: promptCancelEnableGifSearch);

      if (enable != true || !mounted) return;
      await preferences.tenorGifSearchEnabled.set(true);
      if (!mounted) return;
    }

    if (MediaQuery.sizeOf(context).desktop) {
      gifTooltipController.showTooltip(autoClose: false);
    } else {
      await toggleEmojiOverlay(gif: true);
    }
  }

  void closeGifPicker() {
    if (!mounted) return;

    if (MediaQuery.sizeOf(context).desktop) {
      gifTooltipController.hideTooltip();
      // Back to typing, as when the picker is dismissed by clicking outside
      textFocus.requestFocus();
    } else {
      setState(() {
        clearKeyboardOverride(debounce: false);
      });
    }
  }

  Widget buildGifPicker() {
    var gifs = widget.gifComponent!;

    return StreamBuilder(
      stream: gifs.onFavoritesChanged,
      builder: (context, _) => GifPicker(
        focus: gifPickerSearchFocus,
        favorites: gifs.favorites,
        search: gifs.search,
        trending: gifs.trending,
        placeholderText: gifs.searchPlaceholder,
        onDismiss: closeGifPicker,
        gifPicked: (gif) async => sendGifInBackground(
            () => widget.sendGif?.call(gif), closeGifPicker),
        favoritePicked: (gif) async => sendGifInBackground(
            () => widget.sendFavoriteGif?.call(gif), closeGifPicker),
        onUnfavoriteGif: (gif) => gifs.removeFavorite(gif),
      ),
    );
  }

  Expanded textInput(BuildContext context) {
    var height = Theme.of(context).textTheme.bodyMedium!.fontSize!;
    var padding = widget.size - height;
    var hintStyle = TextTheme.of(context).bodyMedium;
    hintStyle = hintStyle?.copyWith(color: hintStyle.color?.withAlpha(120));
    return Expanded(
      child: Stack(
        children: [
          TapRegion(
            onTapInside: (event) => onTextFocusChanged(),
            child: TextField(
              focusNode: textFocus,
              onChanged: onTextfieldUpdated,
              controller: controller,
              readOnly: !widget.enabled || widget.isProcessing,
              textAlignVertical: TextAlignVertical.center,
              style: Theme.of(context).textTheme.bodyMedium!,
              maxLines: null,
              contextMenuBuilder: contextMenuBuilder,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                  contentPadding:
                      EdgeInsets.fromLTRB(8, padding / 2, 4, padding / 2),
                  border: InputBorder.none,
                  isDense: true,
                  hintStyle: hintStyle,
                  hintText: widget.hintText),
            ),
          ),
        ],
      ),
    );
  }

  Padding addAttachmentButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: tiamat.IconButton(
          icon: Icons.add,
          size: widget.size * widget.iconScale,
          onPressed: addAttachment,
        ),
      ),
    );
  }

  double get emotePickerHeight =>
      (MediaQuery.of(context).size.height / (BuildConfig.MOBILE ? 2.5 : 3)) /
      preferences.appScale.value;

  Widget buildEmojiPicker({bool skipIfNeverOpened = true}) {
    var recent = widget.client
        .getComponent<RecentEmoticonComponent>()
        ?.getRecentTypedEmoticon(widget.room);

    var availableEmoji = widget.availibleEmoticons!.toList();

    if (recent != null && recent.isNotEmpty) {
      availableEmoji.insert(
          0,
          DynamicEmoticonPack(
              identifier: "dynamic_pack_frequently_used_typing",
              displayName: EmojiPicker.labelChatEmojiFrequentlyUsed,
              icon: Icons.schedule,
              emoticons: recent,
              usage: EmoticonUsage.all));
    }

    return (!hasEmotePickerOpened && skipIfNeverOpened)
        ? Container()
        : EmoticonPicker(
            emoji: availableEmoji,
            emojiSearchFocus: emojiSearchFocus,
            stickerSearchFocus: stickerSearchFocus,
            gifSearchFocus: gifSearchFocus,
            searchDelegate: (search) => AutofillUtils.searchEmoticon(search,
                    client: widget.client, room: widget.room, limit: 50)
                .whereType<AutofillSearchResultEmoticon>()
                .toList(),
            stickers: widget.availibleStickers ?? [],
            onEmojiPressed: insertEmoticon,
            packListAxis: BuildConfig.DESKTOP ? Axis.vertical : Axis.horizontal,
            allowGifSearch:
                widget.showGifSearch && preferences.tenorGifSearchEnabled.value,
            gifComponent: widget.gifComponent,
            onStickerPressed: (emoticon) {
              widget.sendSticker?.call(emoticon);
              setState(() {
                clearKeyboardOverride(debounce: false);
              });
            },
            onFavoritePicked: (gif) async => sendGifInBackground(
                () => widget.sendFavoriteGif?.call(gif), closeEmotePicker),
            onGifPressed: (gif) async => sendGifInBackground(
                () => widget.sendGif?.call(gif), closeEmotePicker));
  }

  void closeEmotePicker() {
    if (!mounted) return;
    setState(() {
      clearKeyboardOverride(debounce: false);
    });
  }

  /// Closes the picker, then sends. The gif shows up in the chat as sending
  /// straight away while its upload carries on, and holding the picker open
  /// for the upload made sending look stuck. A failure is reported here,
  /// since the picker that used to show it is gone.
  void sendGifInBackground(
      Future<void>? Function() send, void Function() close) {
    close();
    final messenger = ScaffoldMessenger.maybeOf(context);
    Future.sync(send).catchError((Object e, StackTrace s) {
      Log.onError(e, s, content: "Failed to send gif");
      messenger?.showSnackBar(
          SnackBar(content: Text(GifPicker.labelGifPickerSendFailed)));
    });
  }

  Future<void> handlePickedAttachment(PendingFileAttachment attachment) async {
    if (mounted) {
      var processedFile = await AdaptiveDialog.show<PendingFileAttachment>(
        scrollable: false,
        context,
        builder: (context) {
          return AttachmentProcessor(
            attachment: attachment,
          );
        },
      );

      if (processedFile != null) {
        widget.addAttachment?.call(processedFile);
      }
    }
  }

  void addAttachment() async {
    var pickers = [
      if (PlatformUtils.isAndroid)
        AttachmentPicker(
            icon: Icons.photo,
            label: promptChatAttachGallery,
            execute: () async {
              var picker = ImagePicker();
              var result = await picker.pickMultiImage();
              for (var file in result) {
                var data = await file.readAsBytes();
                await handlePickedAttachment(PendingFileAttachment(
                    name: file.name,
                    mimeType: file.mimeType,
                    size: data.lengthInBytes,
                    data: data));
              }
            }),
      AttachmentPicker(
          icon: Icons.attach_file,
          label: promptChatAttachFile,
          execute: () async {
            FilePickerResult? result = await FilePicker.platform.pickFiles(
                type: FileType.any, withData: true, allowMultiple: true);
            if (result == null) return;

            for (var file in result.files) {
              var attachment = PendingFileAttachment(
                  name: file.name,
                  path: PlatformUtils.isWeb ? null : file.path,
                  data: file.bytes,
                  size: file.bytes?.length);

              await handlePickedAttachment(attachment);
            }
          }),
      if (PlatformUtils.isAndroid && preferences.developerMode.value)
        AttachmentPicker(
            icon: Icons.perm_media,
            label: promptChatAttachMedia,
            execute: () async {
              var picker = ImagePicker();
              var result = await picker.pickMultipleMedia();
              for (var file in result) {
                var data = await file.readAsBytes();
                await handlePickedAttachment(PendingFileAttachment(
                    name: file.name,
                    mimeType: file.mimeType,
                    size: data.lengthInBytes,
                    data: data));
              }
            }),
      if (PlatformUtils.isAndroid)
        AttachmentPicker(
            icon: Icons.camera_alt,
            label: promptChatAttachTakePhoto,
            execute: () async {
              var picker = ImagePicker();
              var file = await picker.pickImage(source: ImageSource.camera);
              if (file == null) return;

              var data = await file.readAsBytes();
              await handlePickedAttachment(PendingFileAttachment(
                  name: file.name,
                  mimeType: file.mimeType,
                  size: data.lengthInBytes,
                  data: data));
            }),
    ];

    if (pickers.length == 1) {
      pickers.first.execute();
    } else {
      final picker = await AdaptiveDialog.pickOne(context,
          items: pickers,
          itemBuilder: (context, item, onTapped) => SizedBox(
                height: 50,
                child: tiamat.TextButton(
                  item.label,
                  icon: item.icon,
                  onTap: onTapped,
                ),
              ));

      picker?.execute();
    }
  }

  void doCancelInteraction() {
    if (widget.interactionType == EventInteractionType.edit) {
      controller.clear();
    }

    widget.cancelReply?.call();
  }

  void insertEmoticon(Emoticon emote) {
    if (widget.room != null) {
      var recents = widget.client.getComponent<RecentEmoticonComponent>();
      recents?.typedEmoticon(widget.room!, emote);
    }

    var text = controller.text;
    var selection = controller.selection;
    int start = selection.start;
    int end = selection.end;
    String slug = emote.slug;

    if (start == -1 && end == -1) {
      if (!text.endsWith(" ")) text += " ";
      text += emote.slug;
      controller.text = text;
      return;
    }

    //Add whitespace where necessary
    if (emote.slug.startsWith(":") || emote.slug.endsWith(":")) {
      if (start > 0) {
        var startChar = text[start - 1];
        if (startChar != " ") slug = " $slug";
      }

      if (end < text.length) {
        var endChar = text[end];
        if (endChar != " ") slug = "$slug ";
      } else {
        slug = "$slug ";
      }
    }

    controller.text = text.replaceRange(start, end, slug);
    var newOffset = start + slug.length;
    controller.selection =
        TextSelection(baseOffset: newOffset, extentOffset: newOffset);
  }

  Widget interactionText() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 0, 4),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: tiamat.IconButton(
                icon: Icons.cancel_outlined,
                size: 16,
                onPressed: doCancelInteraction,
              ),
            ),
            Icon(widget.interactionType == EventInteractionType.reply
                ? Icons.keyboard_arrow_right_rounded
                : widget.interactionType == EventInteractionType.edit
                    ? Icons.edit
                    : null),
            tiamat.Text.name(
              widget.relatedEventSenderName!,
              color: widget.relatedEventSenderColor,
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                child: tiamat.Text(
                  widget.relatedEventBody ??
                      TimelineEventViewReply.labelMessageReplyUnknownBody,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget displayAttachments() {
    return SizedBox(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widget.attachments!.map((e) {
          final name = e.name ?? e.path?.split(RegExp(r"[/\\]")).last ?? "";
          // Its name under it, cut short to fit; the whole of it on hover.
          return Tooltip(
            message: name,
            child: Padding(
              padding: const EdgeInsets.all(2.0),
              child: SizedBox(
                width: 64,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: GestureDetector(
                        onTap: () {},
                        child: SizedBox(
                          height: 40,
                          width: 40,
                          child: AttachmentIcon(
                            e,
                            removeAttachment: () =>
                                widget.removeAttachment?.call(e),
                          ),
                        ),
                      ),
                    ),
                    if (name.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget contextMenuBuilder(
      BuildContext buildContext, EditableTextState editableTextState) {
    return AdaptiveTextSelectionToolbar.editable(
      anchors: editableTextState.contextMenuAnchors,
      clipboardStatus: ClipboardStatus.pasteable,
      // to apply the normal behavior when click on copy (copy in clipboard close toolbar)
      // use an empty function `() {}` to hide this option from the toolbar
      onCopy: () =>
          editableTextState.copySelection(SelectionChangedCause.toolbar),
      // to apply the normal behavior when click on cut
      onCut: () =>
          editableTextState.cutSelection(SelectionChangedCause.toolbar),
      onPaste: () async {
        var clipboard = await Clipboard.getData("text/plain");

        if (clipboard != null) {
          return editableTextState.pasteText(SelectionChangedCause.toolbar);
        }

        editableTextState.hideToolbar();

        if (BuildConfig.DESKTOP) {
          await readImageFromClipboard();
        }
      },
      // to apply the normal behavior when click on select all
      onSelectAll: () =>
          editableTextState.selectAll(SelectionChangedCause.toolbar),
      onLiveTextInput: null, onLookUp: null, onSearchWeb: null,
      onShare: null,
    );
  }

  Future<void> readImageFromClipboard() async {
    var image = await Pasteboard.image;
    if (image == null) {
      return;
    }

    var processedAttachment =
        await AdaptiveDialog.show<PendingFileAttachment>(context,
            scrollable: false,
            builder: (context) => AttachmentProcessor(
                  attachment:
                      PendingFileAttachment(data: image, size: image.length),
                ));

    if (processedAttachment != null) {
      setState(() {
        widget.addAttachment?.call(processedAttachment);
      });
    }
  }

  void onPopped(ScopePopped event) {
    if (event.handled) {
      return;
    }

    if (event.currentMobileSide == RevealSide.left) {
      return;
    }

    if (showEmotePicker) {
      clearKeyboardOverride(debounce: false);
      event.handled = true;
    }
  }
}

class _KeyboardHint extends StatelessWidget {
  const _KeyboardHint({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}
