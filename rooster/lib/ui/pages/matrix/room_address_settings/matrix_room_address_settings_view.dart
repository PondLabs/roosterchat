import 'dart:async';

import 'package:rooster/config/layout_config.dart';
import 'package:rooster/ui/atoms/tiny_pill.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/pages/matrix/room_address_settings/matrix_room_add_local_alias_view.dart';
import 'package:flutter/material.dart';
import 'package:implicitly_animated_list/implicitly_animated_list.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class MatrixRoomAddressSettingsView extends StatefulWidget {
  const MatrixRoomAddressSettingsView(this.knownAliases,
      {this.mainAlias,
      this.userHomeserver,
      required this.mainAliasChangedStream,
      required this.isAliasAvailable,
      required this.canChangeMainAlias,
      required this.canAddLocalAlias,
      required this.createAlias,
      required this.deleteAlias,
      required this.setMainAlias,
      required this.publishAlias,
      required this.unpublishAlias,
      required this.publishedAliases,
      super.key});
  final List<String> knownAliases;
  final List<String> publishedAliases;
  final String? mainAlias;
  final String? userHomeserver;
  final bool canChangeMainAlias;
  final bool canAddLocalAlias;
  final Stream<String?> mainAliasChangedStream;
  final Future<bool> Function(String alias) setMainAlias;
  final Future<bool> Function(String alias) deleteAlias;
  final Future<bool> Function(String alias) isAliasAvailable;
  final Future<String?> Function(String alias) createAlias;
  final Future<void> Function(String alias) publishAlias;
  final Future<void> Function(String alias) unpublishAlias;
  @override
  State<MatrixRoomAddressSettingsView> createState() =>
      _MatrixRoomAddressSettingsViewState();
}

class _MatrixRoomAddressSettingsViewState
    extends State<MatrixRoomAddressSettingsView> {
  String? errorMessage;
  StreamSubscription? subscription;

  String get labelRoomAddresses => Intl.message("Room Addresses",
      name: "labelRoomAddresses",
      desc:
          "Header of the section of a room's (or space's) general settings that lists its addresses (aliases such as #name:server)");

  String get labelRoomAddressesOther => Intl.message("Other Addresses:",
      name: "labelRoomAddressesOther",
      desc:
          "In a room's address settings, over the list of all the room's addresses, under the choice of its main address");

  String get labelRoomAddressesNoneLocal => Intl.message(
      "This room does not currently have any local Addresses",
      name: "labelRoomAddressesNoneLocal",
      desc:
          "In a room's address settings, while the room has no address on our server");

  String get tooltipRoomAddressUnpublish => Intl.message("Unpublish Address",
      name: "tooltipRoomAddressUnpublish",
      desc:
          "Tooltip of the globe toggle next to a published room address: stop listing it as one of the room's addresses");

  String get tooltipRoomAddressPublish => Intl.message("Publish Address",
      name: "tooltipRoomAddressPublish",
      desc:
          "Tooltip of the globe toggle next to a room address that is not published: list it as one of the room's addresses for everyone to see");

  String get labelRoomAddressMain => Intl.message("Main",
      name: "labelRoomAddressMain",
      desc:
          "Small badge next to the room address that is the room's main one, in the room's address settings");

  String get tooltipRoomAddressDeleteLocal => Intl.message(
      "Delete local address",
      name: "tooltipRoomAddressDeleteLocal",
      desc:
          "Tooltip of the button that deletes a room address made on our own server");

  String get tooltipRoomAddressAddLocal => Intl.message("Add local address",
      name: "tooltipRoomAddressAddLocal",
      desc:
          "Tooltip of the + button that makes a new room address on our own server");

  String get labelRoomAddressAddLocalTitle => Intl.message("Add Local Address",
      name: "labelRoomAddressAddLocalTitle",
      desc:
          "Title of the dialog that makes a new room address on our own server");

  String get promptRoomAddressSelectMain => Intl.message(
      "Select a main room address",
      name: "promptRoomAddressSelectMain",
      desc:
          "Hint of the dropdown that picks a room's main address, while none is picked");

  String get labelRoomAddressNoMain => Intl.message(
      "This room does not have a set main alias",
      name: "labelRoomAddressNoMain",
      desc:
          "In a room's address settings, for people who may not change it, while the room has no main address");

  String promptRoomAddressDeleteConfirm(String address) => Intl.message(
      "Are you sure you want to delete the address '$address'?",
      name: "promptRoomAddressDeleteConfirm",
      args: [address],
      desc:
          "Confirmation before deleting one of a room's addresses, with the address (such as #name:server)");

  String errorRoomAddressDeleteForbidden(String address) => Intl.message(
      "You do not have permission to delete '$address'",
      name: "errorRoomAddressDeleteForbidden",
      args: [address],
      desc:
          "Error in a room's address settings when deleting an address failed, with the address (such as #name:server)");

  @override
  void initState() {
    subscription = widget.mainAliasChangedStream.listen(onMainAliasChanged);

    super.initState();
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  void onMainAliasChanged(String? value) {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Panel(
      header: labelRoomAddresses,
      mode: TileType.surfaceContainerLow,
      child: Column(
        children: [
          if (widget.knownAliases.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
              child: mainAliasSelector(),
            ),
          aliasList(),
        ],
      ),
    );
  }

  Widget aliasList() {
    double boxSize = MediaQuery.sizeOf(context).mobile ? 40 : 30;
    double iconSize = MediaQuery.sizeOf(context).mobile ? 25 : 20;
    return Panel(
      mode: TileType.surfaceContainer,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          tiamat.Text.labelLow(labelRoomAddressesOther),
          if (widget.knownAliases.isEmpty)
            SizedBox(
              height: 50,
              child: Center(
                child: tiamat.Text.labelLow(labelRoomAddressesNoneLocal),
              ),
            ),
          ImplicitlyAnimatedList(
            shrinkWrap: true,
            itemData: widget.knownAliases,
            itemBuilder: (context, data) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IgnorePointer(
                        ignoring: isEditable(data) == false,
                        child: SizedBox(
                            width: boxSize,
                            height: boxSize,
                            child: tiamat.Tooltip(
                              text: isPublished(data)
                                  ? tooltipRoomAddressUnpublish
                                  : tooltipRoomAddressPublish,
                              child: tiamat.IconToggle(
                                icon: Icons.public,
                                size: iconSize,
                                state: isPublished(data),
                                onPressed: (newState) {
                                  if (newState) {
                                    widget.publishAlias(data);
                                  } else {
                                    widget.unpublishAlias(data);
                                  }
                                },
                              ),
                            )),
                      ),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: tiamat.Text.label(data),
                        ),
                      ),
                      if (data == widget.mainAlias)
                        TinyPill(labelRoomAddressMain),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: boxSize,
                      height: boxSize,
                      child: isEditable(data)
                          ? tiamat.Tooltip(
                              text: tooltipRoomAddressDeleteLocal,
                              child: tiamat.IconButton(
                                icon: Icons.close,
                                size: iconSize,
                                onPressed: () => deleteAlias(data),
                                iconColor: Theme.of(context).colorScheme.error,
                              ),
                            )
                          : Container(),
                    ),
                  ),
                ],
              );
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              errorMessage == null
                  ? Container()
                  : Flexible(child: tiamat.Text.error(errorMessage!)),
              SizedBox(
                width: 40,
                height: 40,
                child: tiamat.Tooltip(
                  preferredDirection: AxisDirection.left,
                  text: tooltipRoomAddressAddLocal,
                  child: tiamat.CircleButton(
                    icon: Icons.add,
                    onPressed: showAddAliasDialog,
                  ),
                ),
              )
            ],
          )
        ],
      ),
    );
  }

  void showAddAliasDialog() {
    AdaptiveDialog.show(
      context,
      title: labelRoomAddressAddLocalTitle,
      builder: (context) {
        return MatrixRoomAddLocalAliasView(widget.userHomeserver!,
            widget.isAliasAvailable, widget.createAlias);
      },
    );
  }

  Widget mainAliasSelector() {
    return IgnorePointer(
      ignoring: widget.canChangeMainAlias == false,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          tiamat.DropdownSelector(
            items: widget.knownAliases,
            value: widget.mainAlias,
            itemHeight: 60,
            hint: tiamat.Text.labelLow(widget.canChangeMainAlias
                ? promptRoomAddressSelectMain
                : labelRoomAddressNoMain),
            onItemSelected: (item) => widget.setMainAlias(item!),
            itemBuilder: (item) {
              return Row(
                children: [
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: tiamat.Text.label(item!),
                    ),
                  ),
                  if (item == widget.mainAlias) TinyPill(labelRoomAddressMain),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> deleteAlias(String item) async {
    var confirmation = await AdaptiveDialog.confirmation(context,
        prompt: promptRoomAddressDeleteConfirm(item));

    if (confirmation != true) {
      return;
    }

    var result = await widget.deleteAlias(item);

    if (result == false) {
      setState(() {
        errorMessage = errorRoomAddressDeleteForbidden(item);
      });
    }
  }

  bool isEditable(String item) {
    if (item.split(":").last == widget.userHomeserver) {
      return true;
    }

    return false;
  }

  bool isPublished(String item) {
    return widget.publishedAliases.contains(item);
  }
}
