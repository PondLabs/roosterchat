import 'package:rooster/utils/debounce.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class MatrixRoomAddLocalAliasView extends StatefulWidget {
  const MatrixRoomAddLocalAliasView(
      this.homeserver, this.isAliasAvailable, this.createAlias,
      {super.key});
  final String homeserver;
  final Future<bool> Function(String alias) isAliasAvailable;
  final Future<String?> Function(String alias) createAlias;

  @override
  State<MatrixRoomAddLocalAliasView> createState() =>
      _MatrixRoomAddLocalAliasViewState();
}

class _MatrixRoomAddLocalAliasViewState
    extends State<MatrixRoomAddLocalAliasView> {
  TextEditingController controller = TextEditingController();
  Debouncer debouncer = Debouncer(delay: const Duration(milliseconds: 500));

  bool? isAvailable;
  bool createLoading = false;

  String get labelRoomAliasPlaceholder => Intl.message("my-room",
      name: "labelRoomAliasPlaceholder",
      desc:
          "Example shown in the empty field of the dialog that makes a new room address (#my-room:server). Lowercase, words joined with hyphens, no spaces");

  String get errorRoomAliasInUse => Intl.message("Alias already in use",
      name: "errorRoomAliasInUse",
      desc:
          "In the dialog that makes a new room address: the address typed is taken");

  String get labelRoomAliasAvailable => Intl.message("Alias is available!",
      name: "labelRoomAliasAvailable",
      desc:
          "In the dialog that makes a new room address: the address typed is free");

  String get promptRoomAliasCreate => Intl.message("Create!",
      name: "promptRoomAliasCreate",
      desc: "Button that makes the new room address typed in the dialog");

  @override
  void initState() {
    super.initState();
    controller.addListener(onTextChanged);
  }

  void onTextChanged() {
    setState(() {
      isAvailable = null;
    });

    if (controller.text.isEmpty) {
      debouncer.cancel();
    } else {
      debouncer.run(checkAvailability);
    }
  }

  Future<void> checkAvailability() async {
    var result = await widget.isAliasAvailable(controller.text);
    setState(() {
      isAvailable = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tiamat.TextInput(
          controller: controller,
          placeholder: labelRoomAliasPlaceholder,
          suffixText: ":${widget.homeserver}",
          prefixText: "#",
        ),
        const SizedBox(
          height: 10,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (isAvailable == false)
              Flexible(child: tiamat.Text.error(errorRoomAliasInUse)),
            if (isAvailable == true)
              Flexible(child: tiamat.Text.label(labelRoomAliasAvailable)),
            if (isAvailable == null && controller.text.isEmpty) Container(),
            if (isAvailable == null && controller.text.isNotEmpty)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: SizedBox(
                    width: 15, height: 15, child: CircularProgressIndicator()),
              ),
            tiamat.Button(
              text: promptRoomAliasCreate,
              onTap: submit,
              isLoading: createLoading,
            )
          ],
        )
      ],
    );
  }

  Future<void> submit() async {
    if (isAvailable != true) {
      return;
    }

    setState(() {
      createLoading = true;
    });

    var text = controller.text;

    var result = await widget.createAlias(text);

    if (result != null) {
      setState(() {
        createLoading = false;
      });

      if (mounted) Navigator.of(context).pop(result);
    } else {
      setState(() {
        isAvailable = false;
      });
    }
  }
}
