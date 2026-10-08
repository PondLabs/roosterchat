import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/space_categories/channel_categories.dart';
import 'package:rooster/client/components/space_categories/space_categories_component.dart';
import 'package:rooster/client/space_child.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/navigation/adaptive_text_dialog.dart';
import 'package:rooster/ui/pages/get_or_create_room/get_or_create_room.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// What a space admin does with the headings of the space's channel list,
/// and with the channels under them. See docs/channel-categories.md.
class ChannelCategoryActions {
  static String get labelTextChannels => Intl.message("Text channels",
      name: "labelTextChannels",
      desc: "Heading in a space's sidebar over its text channels");

  static String get labelVoiceChannels => Intl.message("Voice channels",
      name: "labelVoiceChannels",
      desc: "Heading in a space's sidebar over its voice channels");

  static String get promptCreateChannel => Intl.message("Create channel",
      name: "promptCreateChannel",
      desc: "Button on a channel category heading that adds a channel under "
          "it");

  static String get promptCreateCategory => Intl.message("Create category",
      name: "promptCreateCategory",
      desc: "Menu entry that adds a heading to a space's channel list");

  static String get promptRenameCategory => Intl.message("Rename category",
      name: "promptRenameCategory",
      desc: "Menu entry that renames a heading of a space's channel list");

  static String get promptDeleteCategory => Intl.message("Delete category",
      name: "promptDeleteCategory",
      desc: "Menu entry that removes a heading of a space's channel list");

  static String promptDeleteCategoryConfirmation(String name) => Intl.message(
      "Delete the category $name? Its channels stay, back under text "
      "channels and voice channels.",
      name: "promptDeleteCategoryConfirmation",
      args: [name],
      desc: "Asks before removing a heading of a space's channel list");

  static String get promptMoveCategoryUp => Intl.message("Move up",
      name: "promptMoveCategoryUp",
      desc: "Menu entry that moves a channel category above the one before "
          "it");

  static String get promptMoveCategoryDown => Intl.message("Move down",
      name: "promptMoveCategoryDown",
      desc: "Menu entry that moves a channel category below the one after "
          "it");

  static String get promptCollapseCategory => Intl.message("Collapse",
      name: "promptCollapseCategory",
      desc: "Menu entry that hides the channels under a category");

  static String get promptExpandCategory => Intl.message("Expand",
      name: "promptExpandCategory",
      desc: "Menu entry that shows the channels under a collapsed category");

  static String get labelCategoryName => Intl.message("Category name",
      name: "labelCategoryName",
      desc: "Placeholder of the text field naming a channel category");

  static String get labelRenameBuiltInCategory =>
      Intl.message("Leave it empty to use the default name.",
          name: "labelRenameBuiltInCategory",
          desc: "Under the field renaming the built-in text or voice channel "
              "category");

  static String get promptMoveToCategory => Intl.message("Move to category",
      name: "promptMoveToCategory",
      desc: "Menu entry on a channel that puts it under another heading");

  static String get errorSaveCategories =>
      Intl.message("Could not save the categories",
          name: "errorSaveCategories",
          desc: "Title of the error shown when changing the channel categories "
              "fails");

  static SpaceCategoriesComponent? componentOf(Space space) =>
      space.getComponent<SpaceCategoriesComponent>();

  /// Whether we may change [space]'s headings.
  static bool canEdit(Space space) =>
      componentOf(space)?.canEditCategories == true;

  static ChannelKind kindOf(Room room) =>
      room.roomType == RoomType.voipRoom ? ChannelKind.voice : ChannelKind.text;

  static String nameOf(ChannelCategory category) =>
      category.name ??
      switch (category.kind) {
        ChannelCategoryKind.voice => labelVoiceChannels,
        _ => labelTextChannels,
      };

  /// Saves [change] applied to [space]'s headings as they are now, saying
  /// so when it fails.
  static Future<void> _edit(BuildContext context, Space space,
      ChannelCategories Function(ChannelCategories current) change) async {
    final component = componentOf(space);
    if (component == null) return;
    try {
      await component.setCategories(change(component.categories));
    } catch (e, s) {
      Log.onError(e, s, content: "Could not save the channel categories");
      if (context.mounted) {
        AdaptiveDialog.showError(context, e, s, title: errorSaveCategories);
      }
    }
  }

  static Future<void> createCategory(BuildContext context, Space space) async {
    final component = componentOf(space);
    if (component == null) return;
    final name = await AdaptiveTextDialog.show(context,
        title: promptCreateCategory, placeholder: labelCategoryName);
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final id = component.newCategoryId();
    await _edit(context, space, (c) => c.withCategoryAdded(id, name));
  }

  static Future<void> renameCategory(
      BuildContext context, Space space, ChannelCategory category) async {
    final name = await AdaptiveTextDialog.show(context,
        title: promptRenameCategory,
        placeholder: labelCategoryName,
        description: category.isBuiltIn ? labelRenameBuiltInCategory : null,
        defaultText: category.name);
    if (name == null || !context.mounted) return;
    await _edit(
        context, space, (c) => c.withCategoryRenamed(category.id, name));
  }

  static Future<void> deleteCategory(
      BuildContext context, Space space, ChannelCategory category) async {
    final confirmed = await AdaptiveDialog.confirmation(context,
        title: promptDeleteCategory,
        prompt: promptDeleteCategoryConfirmation(nameOf(category)),
        dangerous: true);
    if (confirmed != true || !context.mounted) return;
    await _edit(context, space, (c) => c.withCategoryRemoved(category.id));
  }

  static Future<void> moveCategory(BuildContext context, Space space,
          ChannelCategory category, int by) =>
      _edit(context, space, (c) => c.withCategoryMoved(category.id, by));

  /// Creates a channel under [category], or adds an existing room: a text
  /// or a voice channel under the built-in headings, any kind under one of
  /// the admin's.
  static Future<void> addChannel(
      BuildContext context, Space space, ChannelCategory category) async {
    final child = await GetOrCreateRoom.show(
      space.client,
      context,
      currentSpace: space,
      joinRoom: false,
      showAllRoomTypes: category.kind == ChannelCategoryKind.custom,
      createTextChat: category.kind == ChannelCategoryKind.text,
      createVoiceChat: category.kind == ChannelCategoryKind.voice,
      existingRoomsRemoveWhere: (child) =>
          child.id == space.identifier ||
          space.children.any((i) => i.id == child.id),
    );
    if (child is SpaceChildSpace) {
      await space.setSpaceChildSpace(child.child);
      return;
    }
    if (child is! SpaceChildRoom) return;

    final room = child.child;
    await space.setSpaceChildRoom(room);
    if (category.kind == ChannelCategoryKind.custom && context.mounted) {
      await _edit(
          context, space, (c) => c.withChannelIn(room.identifier, category.id));
    }
  }

  /// Asks which heading [room] goes under: one of the admin's, or the
  /// built-in one of its kind.
  static Future<void> moveChannel(
      BuildContext context, Space space, Room room) async {
    final component = componentOf(space);
    if (component == null) return;
    final categories = component.categories;
    final kind = kindOf(room);
    final current = categories.categoryOf(room.identifier, kind);
    final options = [
      ...categories.custom,
      categories.builtInFor(kind),
    ];

    final picked = await AdaptiveDialog.pickOne<ChannelCategory>(context,
        title: promptMoveToCategory,
        items: options,
        itemBuilder: (context, category, done) => SizedBox(
              height: 40,
              child: tiamat.TextButton(
                nameOf(category),
                icon: category.id == current.id
                    ? Icons.check_rounded
                    : Icons.folder_outlined,
                highlighted: category.id == current.id,
                onTap: done,
              ),
            ));
    if (picked == null || picked.id == current.id || !context.mounted) return;
    await _edit(
        context, space, (c) => c.withChannelIn(room.identifier, picked.id));
  }

  /// The menu of a heading: everyone can fold it; an admin also manages
  /// the headings.
  static List<tiamat.ContextMenuItem> menuItems(
    BuildContext context,
    Space space,
    ChannelCategory category, {
    required bool collapsed,
    required VoidCallback toggleCollapsed,
  }) {
    final categories = componentOf(space)?.categories;
    final index =
        categories?.categories.indexWhere((c) => c.id == category.id) ?? -1;
    final canEditChildren = space.permissions.canEditChildren;
    final canEditCategories = canEdit(space);

    return [
      tiamat.ContextMenuItem(
        text: collapsed ? promptExpandCategory : promptCollapseCategory,
        icon: collapsed ? Icons.unfold_more_rounded : Icons.unfold_less_rounded,
        onPressed: toggleCollapsed,
      ),
      if (canEditChildren)
        tiamat.ContextMenuItem(
          text: promptCreateChannel,
          icon: Icons.add_rounded,
          onPressed: () => addChannel(context, space, category),
        ),
      if (canEditCategories) ...[
        tiamat.ContextMenuItem(
          text: promptCreateCategory,
          icon: Icons.create_new_folder_outlined,
          onPressed: () => createCategory(context, space),
        ),
        tiamat.ContextMenuItem(
          text: promptRenameCategory,
          icon: Icons.edit_outlined,
          onPressed: () => renameCategory(context, space, category),
        ),
        if (index > 0)
          tiamat.ContextMenuItem(
            text: promptMoveCategoryUp,
            icon: Icons.arrow_upward_rounded,
            onPressed: () => moveCategory(context, space, category, -1),
          ),
        if (index != -1 && index < categories!.categories.length - 1)
          tiamat.ContextMenuItem(
            text: promptMoveCategoryDown,
            icon: Icons.arrow_downward_rounded,
            onPressed: () => moveCategory(context, space, category, 1),
          ),
        if (!category.isBuiltIn)
          tiamat.ContextMenuItem(
            text: promptDeleteCategory,
            icon: Icons.delete_outline_rounded,
            color: Theme.of(context).colorScheme.error,
            onPressed: () => deleteCategory(context, space, category),
          ),
      ],
    ];
  }
}
