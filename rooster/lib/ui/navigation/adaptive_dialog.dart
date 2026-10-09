import 'package:rooster/client/client.dart';
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/scaled_safe_area.dart';
import 'package:rooster/ui/molecules/user_panel.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:flutter/material.dart' as m;

class DialogResult<T> {
  T value;
  bool remember;

  DialogResult(this.value, {this.remember = false});
}

class AdaptiveDialog {
  static String get labelAppPickAccount => Intl.message("Pick Account",
      name: "labelAppPickAccount",
      desc: "Title of the dialog that asks which signed-in account to use, "
          "when there is more than one");

  static String get labelAppError => Intl.message("Error",
      name: "labelAppError",
      desc: "Title of the dialog that shows an error, when the place it came "
          "from gives none of its own");

  static String get messageAppAreYouSure => Intl.message("Are you sure?",
      name: "messageAppAreYouSure",
      desc: "Question in a confirmation dialog, when the action gives no "
          "question of its own");

  static String get labelAppEnterText => Intl.message("Enter Text",
      name: "labelAppEnterText",
      desc: "Title of a dialog that asks for a line of text, when the place "
          "it came from gives none of its own");

  static String get labelAppRememberChoice => Intl.message("Remember choice:",
      name: "labelAppRememberChoice",
      desc: "Beside a switch in a confirmation dialog: keep this answer and "
          "do not ask again");

  static Future<T?> pickOne<T extends Object?>(
    BuildContext context, {
    required List<T> items,
    required Widget Function(BuildContext context, T item, Function() callback)
        itemBuilder,
    String? title,
    bool scrollable = true,
    bool dismissible = true,
    double initialHeightMobile = 0.5,
  }) {
    return AdaptiveDialog.show<T>(context, title: title, builder: (context) {
      return Column(
        children: items
            .map((i) =>
                itemBuilder(context, i, () => Navigator.of(context).pop(i)))
            .toList(),
      );
    });
  }

  static Future<List<T>?> pickMultiple<T extends Object?>(
    BuildContext context, {
    required List<T> items,
    List<T> selected = const [],
    required Widget Function(BuildContext context, T item) itemBuilder,
    String? title,
    bool scrollable = true,
    bool dismissible = true,
    double initialHeightMobile = 0.5,
  }) async {
    // I had to do this weird thing to make it happy with the type cast
    // Dont know why
    var builder = (BuildContext context, dynamic i) {
      var item = i as T;
      return itemBuilder(context, item);
    };

    var result = await AdaptiveDialog.show<List<dynamic>>(
      context,
      title: title,
      dismissible: dismissible,
      scrollable: scrollable,
      builder: (context) {
        return _SelectMultipleView<T>(
          itemBuilder: builder,
          items: items,
          initialSelection: selected,
        );
      },
    );

    print("Got result:");
    print(result);

    if (result != null) {
      return result.map((i) => i as T).toList();
    }

    return null;
  }

  static Future<Client?> pickClient(
    BuildContext context, {
    String? title,
    bool scrollable = true,
    bool dismissible = true,
    double initialHeightMobile = 0.5,
  }) async {
    if (clientManager?.clients.length == 1) {
      return clientManager!.clients.first;
    }

    return AdaptiveDialog.pickOne(
      context,
      title: labelAppPickAccount,
      items: clientManager!.clients,
      itemBuilder: (context, item, callback) {
        return SizedBox(
          child: UserPanelView(
            avatar: item.self!.avatar,
            nameColor: item.self!.defaultColor,
            avatarColor: item.self!.defaultColor,
            displayName: item.self!.displayName,
            detail: item.self!.identifier,
            onClicked: callback,
          ),
        );
      },
    );
  }

  static Future<void> showError(
      BuildContext context, Object exception, StackTrace trace,
      {String? title}) {
    return show(context, builder: (context) {
      return Column(
        children: [
          tiamat.Text.body(exception.toString()),
        ],
      );
    }, title: title ?? labelAppError);
  }

  static Future<T?> show<T extends Object?>(
    BuildContext context, {
    required Widget Function(BuildContext context) builder,
    String? title,
    bool scrollable = true,
    bool dismissible = true,
    double contentPadding = 8,
    double initialHeightMobile = 0.5,
  }) async {
    if (MediaQuery.sizeOf(context).desktop) {
      return PopupDialog.show<T>(context,
          content: scrollable
              ? SingleChildScrollView(child: builder(context))
              : builder(context),
          title: title,
          contentPadding: contentPadding,
          barrierDismissible: dismissible);
    }

    return m.showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      elevation: 0,
      isDismissible: dismissible,
      backgroundColor: m.Theme.of(context).colorScheme.surfaceContainerLow,
      builder: (context) {
        return SingleChildScrollView(
            child: Container(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: ScaledSafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: tiamat.Text(
                        title,
                        type: TextType.largeTitle,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  Center(child: builder(context)),
                ],
              ),
            ),
          ),
        ));
      },
    );
  }

  static String get labelDialogConfirmation => Intl.message("Confirmation",
      name: "labelDialogConfirmation",
      desc: "label for the dialog which asks the user to confirm some action");

  /// [prompt], [title], [confirmationText] and [cancelText] fall back to
  /// "Are you sure?", "Confirmation", "Yes" and "No", translated.
  static Future<bool?> confirmation(BuildContext context,
      {String? prompt,
      String? title,
      String? confirmationText,
      String? cancelText,
      Widget Function(BuildContext)? customBuilder,
      bool dangerous = false}) async {
    var value = await show<DialogResult<bool>?>(context, builder: (context) {
      return ConfirmationDialogWidget(
        prompt: prompt,
        title: title,
        confirmationText: confirmationText,
        cancelText: cancelText,
        customBuilder: customBuilder,
        dangerous: dangerous,
      );
    }, title: title ?? labelDialogConfirmation);

    return value?.value;
  }

  static Future<DialogResult<bool>?> confirmationWithOptions(
      BuildContext context,
      {String? prompt,
      String? title,
      String? confirmationText,
      String? cancelText,
      Widget Function(BuildContext)? customBuilder,
      bool showRememberChoice = false,
      bool defaultRememberSetting = false,
      bool dangerous = false}) {
    var value = show<DialogResult<bool>?>(context, builder: (context) {
      return ConfirmationDialogWidget(
        prompt: prompt,
        title: title,
        confirmationText: confirmationText,
        cancelText: cancelText,
        customBuilder: customBuilder,
        showRememberChoice: showRememberChoice,
        defaultRememberSetting: defaultRememberSetting,
        dangerous: dangerous,
      );
    }, title: title ?? labelDialogConfirmation);

    return value;
  }

  /// [title] and [submitText] fall back to "Enter Text" and "Submit",
  /// translated.
  static Future<String?> textPrompt(BuildContext context,
      {String? title,
      String? submitText,
      String? hintText,
      String? initialText,
      bool multiline = false,
      bool dangerous = false}) {
    return show<String?>(context, builder: (context) {
      String result = "";
      TextEditingController controller =
          TextEditingController(text: initialText);

      return SizedBox(
        width: MediaQuery.sizeOf(context).desktop ? 500 : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLines: multiline ? null : 1,
                decoration: InputDecoration(hintText: hintText),
                onChanged: (value) => result = value,
              ),
              SizedBox(
                height: 10,
              ),
              tiamat.Button(
                text: submitText ?? CommonStrings.promptSubmit,
                onTap: () {
                  print(result);
                  Navigator.of(context).pop(result);
                },
              )
            ],
          ),
        ),
      );
    }, title: title ?? labelAppEnterText);
  }
}

/// [prompt], [confirmationText] and [cancelText] fall back to "Are you
/// sure?", "Yes" and "No", translated. [title] is the dialog's, shown by
/// [AdaptiveDialog.show].
class ConfirmationDialogWidget extends StatefulWidget {
  final String? prompt;
  final String? title;
  final String? confirmationText;
  final String? cancelText;
  final Widget Function(BuildContext)? customBuilder;
  final bool showRememberChoice;
  final bool defaultRememberSetting;
  final bool dangerous;

  const ConfirmationDialogWidget({
    super.key,
    this.prompt,
    this.title,
    this.confirmationText,
    this.cancelText,
    this.customBuilder,
    this.showRememberChoice = false,
    this.defaultRememberSetting = false,
    this.dangerous = false,
  });

  @override
  State<ConfirmationDialogWidget> createState() =>
      _ConfirmationDialogWidgetState();
}

class _ConfirmationDialogWidgetState extends State<ConfirmationDialogWidget> {
  bool rememberChoice = false;

  @override
  void initState() {
    rememberChoice = widget.defaultRememberSetting;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.sizeOf(context).desktop ? 500 : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
              child: Markdown(
                shrinkWrap: true,
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                    .copyWith(
                        codeblockPadding: EdgeInsets.all(8),
                        code: TextTheme.of(context).bodySmall!.copyWith(
                            fontFamily: "Code",
                            backgroundColor: ColorScheme.of(context)
                                .surfaceContainerLowest)),
                data: widget.prompt ?? AdaptiveDialog.messageAppAreYouSure,
              ),
            ),
            if (widget.customBuilder != null) widget.customBuilder!(context),
            if (widget.showRememberChoice)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: SizedBox(
                    child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: tiamat.Text.labelLow(
                          AdaptiveDialog.labelAppRememberChoice),
                    ),
                    tiamat.Switch(
                      state: rememberChoice,
                      onChanged: (value) {
                        setState(() {
                          rememberChoice = value;
                        });
                      },
                    ),
                  ],
                )),
              ),
            SizedBox(
              height: 40,
              child: tiamat.Button(
                type: widget.dangerous ? ButtonType.danger : ButtonType.primary,
                text: widget.confirmationText ?? CommonStrings.promptYes,
                onTap: () => Navigator.pop(
                    context, DialogResult(true, remember: rememberChoice)),
              ),
            ),
            const SizedBox(
              height: 5,
            ),
            tiamat.Button.secondary(
              text: widget.cancelText ?? CommonStrings.promptNo,
              onTap: () => Navigator.pop(
                  context, DialogResult(false, remember: rememberChoice)),
            )
          ],
        ),
      ),
    );
  }
}

class _SelectMultipleView<T> extends StatefulWidget {
  const _SelectMultipleView(
      {required this.itemBuilder,
      required this.items,
      this.initialSelection = const [],
      super.key});
  final List<T> items;
  final List<T> initialSelection;
  final Widget Function(BuildContext context, T item) itemBuilder;
  @override
  State<_SelectMultipleView> createState() => __SelectMultipleViewState();
}

class __SelectMultipleViewState<T> extends State<_SelectMultipleView<T>> {
  List<T> selection = List.empty(growable: true);

  @override
  void initState() {
    selection.addAll(widget.initialSelection);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
        spacing: 8,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...widget.items
              .map((i) => Material(
                    clipBehavior: Clip.antiAlias,
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          if (selection.contains(i)) {
                            selection.remove(i);
                          } else {
                            selection.add(i);
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            Checkbox(
                                value: selection.contains(i),
                                onChanged: (v) {
                                  if (v == true) {
                                    setState(() {
                                      selection.add(i);
                                    });
                                  } else {
                                    setState(() {
                                      selection.remove(i);
                                    });
                                  }

                                  print(selection);
                                }),
                            widget.itemBuilder(context, i)
                          ],
                        ),
                      ),
                    ),
                  ))
              .toList(),
          tiamat.Button(
            text: CommonStrings.promptSubmit,
            onTap: () => Navigator.of(context).pop(selection),
          )
        ]);
  }
}
