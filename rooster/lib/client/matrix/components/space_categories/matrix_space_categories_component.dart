// Matrix adapter: one state event in the space.
//
// Type: `chat.commet.space_categories`, state_key "". Content:
//   {"categories": [{"id": "k2j4", "name": "Info", "rooms": ["!a", "!b"]},
//                   {"id": "text"}, {"id": "voice", "name": "Hangouts"}]}
// Changing it takes the power level for state events of that type, by
// default the space's admins and moderators.
import 'dart:async';

import 'package:rooster/client/components/space_categories/channel_categories.dart';
import 'package:rooster/client/components/space_categories/space_categories_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room_permissions.dart';
import 'package:rooster/client/matrix/matrix_space.dart';
import 'package:rooster/utils/rng.dart';

class MatrixSpaceCategoriesComponent
    implements SpaceCategoriesComponent<MatrixClient, MatrixSpace> {
  @override
  MatrixClient client;

  @override
  MatrixSpace space;

  final StreamController<void> _onChanged = StreamController.broadcast();

  ChannelCategories _categories = ChannelCategories.defaults;

  MatrixSpaceCategoriesComponent(this.client, this.space) {
    _read();
    client.matrixClient.onRoomState.stream
        .where((e) =>
            e.roomId == space.matrixRoom.id &&
            e.state.type == ChannelCategories.stateEventType)
        .listen((_) => _read());
    // In case the event is not among the state read at startup yet (a
    // database written before it was).
    space.fullStateLoaded.then((_) => _read());
  }

  void _read() {
    final content =
        space.matrixRoom.getState(ChannelCategories.stateEventType)?.content;
    _categories = ChannelCategories.fromJson(content);
    if (!_onChanged.isClosed) _onChanged.add(null);
  }

  @override
  ChannelCategories get categories => _categories;

  @override
  bool get canEditCategories =>
      space.matrixRoom.canChangeState(ChannelCategories.stateEventType);

  @override
  Stream<void> get onChanged => _onChanged.stream;

  @override
  Future<void> setCategories(ChannelCategories categories) async {
    final previous = _categories;
    // Shown at once; the homeserver's echo confirms it.
    _categories = categories;
    _onChanged.add(null);
    try {
      await client.matrixClient.setRoomStateWithKey(space.matrixRoom.id,
          ChannelCategories.stateEventType, '', categories.toJson());
    } catch (_) {
      _categories = previous;
      _onChanged.add(null);
      rethrow;
    }
  }

  @override
  String newCategoryId() => RandomUtils.getRandomString(12);
}
