import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/space_categories/channel_categories.dart';
import 'package:rooster/client/components/space_component.dart';

/// The headings a space lists its channels under. See
/// docs/channel-categories.md.
abstract class SpaceCategoriesComponent<R extends Client, T extends Space>
    implements SpaceComponent<R, T> {
  ChannelCategories get categories;

  /// Whether we may change the headings: a space admin.
  bool get canEditCategories;

  /// Fires when the headings change, ours or someone else's edit.
  Stream<void> get onChanged;

  Future<void> setCategories(ChannelCategories categories);

  /// A new id for a heading of the admin's.
  String newCategoryId();
}
