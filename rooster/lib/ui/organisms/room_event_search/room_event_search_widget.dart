import 'dart:async';

import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/event_search/event_search_component.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:rooster/ui/molecules/timeline_events/timeline_event_view_single.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:rooster/utils/debounce.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:implicitly_animated_list/implicitly_animated_list.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomEventSearchWidget extends StatefulWidget {
  const RoomEventSearchWidget({
    required this.room,
    this.close,
    this.onEventClicked,
    super.key,
  });
  final Room room;
  final void Function()? close;
  final void Function(String eventId)? onEventClicked;

  static String get roomSearchNoResults => Intl.message(
        'No results found',
        name: 'roomSearchNoResults',
        desc: 'Empty message search results',
      );
  static String get roomSearchFailed => Intl.message(
        "Couldn't search messages",
        name: 'roomSearchFailed',
        desc: 'Message search failed',
      );
  static String get roomSearchRetry => Intl.message(
        'Retry',
        name: 'roomSearchRetry',
        desc: 'Retry a failed message search',
      );
  static String get roomSearchClear => Intl.message(
        'Clear search',
        name: 'roomSearchClear',
        desc: 'Clear the message search field',
      );
  static String get roomSearchNext => Intl.message(
        'Next',
        name: 'roomSearchNext',
        desc: 'Search the next page of messages',
      );

  @override
  State<RoomEventSearchWidget> createState() => _RoomEventSearchWidgetState();
}

class _RoomEventSearchWidgetState extends State<RoomEventSearchWidget> {
  TextEditingController controller = TextEditingController();
  EventSearchSession? searchSession;

  StreamSubscription? currentSubscription;
  List<TimelineEvent>? currentResults;

  Debouncer debouncer = Debouncer(delay: const Duration(seconds: 1));

  bool loading = false;
  bool failed = false;
  // Session creation can finish after the query changed or the panel closed.
  int searchRevision = 0;

  @override
  void didUpdateWidget(covariant RoomEventSearchWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room != widget.room) onTextChanged(controller.text);
  }

  @override
  void dispose() {
    searchRevision++;
    debouncer.cancel();
    controller.dispose();
    currentSubscription?.cancel();
    searchSession?.dispose();
    searchSession = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var color = Theme.of(context).colorScheme.surfaceContainer;
    return Column(
      children: [
        tiamat.Tile.low(
          child: Row(
            children: [
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.all(1.0),
                  child: TextField(
                    autofocus: true,
                    onChanged: onTextChanged,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => submitSearch(),
                    style: Theme.of(context).textTheme.bodyMedium!,
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: CommonStrings.promptSearch,
                      suffixIcon: controller.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: RoomEventSearchWidget.roomSearchClear,
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                controller.clear();
                                onTextChanged('');
                              },
                            ),
                      prefix: const SizedBox(width: 10),
                      contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                child: tiamat.IconButton(
                  icon: Icons.close,
                  size: 20,
                  onPressed: widget.close,
                ),
              ),
            ],
          ),
        ),
        if (currentResults?.isNotEmpty == true)
          Flexible(
            child: ClipRect(
              child: ImplicitlyAnimatedList(
                itemEquality: (a, b) => a.eventId == b.eventId,
                itemData: currentResults!,
                padding: EdgeInsets.all(0),
                itemBuilder: (context, data) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Material(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          onTap: () =>
                              widget.onEventClicked?.call(data.eventId),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: TimelineEventViewSingle(
                              room: widget.room,
                              event: data,
                              key: ValueKey("search-result_${data.eventId}"),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        if (currentResults?.isEmpty == true &&
            searchSession != null &&
            loading == false &&
            !failed)
          Flexible(
            child: Center(
              child: tiamat.Text.labelLow(
                  RoomEventSearchWidget.roomSearchNoResults),
            ),
          ),
        if (failed)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                tiamat.Text.labelLow(RoomEventSearchWidget.roomSearchFailed),
                TextButton(
                  onPressed: submitSearch,
                  child: Text(RoomEventSearchWidget.roomSearchRetry),
                ),
              ],
            ),
          ),
        if (loading || (!failed && searchSession?.canContinueSearch == true))
          SizedBox(
            height: 50,
            child: loading
                ? Center(
                    child: const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : searchSession?.canContinueSearch == true
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                        child: tiamat.TextButton(
                          RoomEventSearchWidget.roomSearchNext,
                          icon: Icons.search,
                          highlighted: true,
                          highlightColor: ColorScheme.of(
                            context,
                          ).surfaceContainerLow,
                          onTap: continueSearch,
                        ),
                      )
                    : Container(),
          ),
      ],
    );
  }

  void onTextChanged(String value) {
    final revision = ++searchRevision;
    debouncer.cancel();
    currentSubscription?.cancel();
    currentSubscription = null;
    setState(() {
      currentResults = null;
      searchSession = null;
      failed = false;
      loading = value.trim().isNotEmpty;
    });
    if (loading) {
      debouncer.run(() => startSearch(value.trim(), revision));
    }
  }

  void submitSearch() {
    onTextChanged(controller.text);
    debouncer.cancel();
    if (loading) startSearch(controller.text.trim(), searchRevision);
  }

  bool isCurrent(int revision) => mounted && revision == searchRevision;

  Future<void> startSearch(String value, int revision) async {
    try {
      final search = widget.room.client.getComponent<EventSearchComponent>()!;
      final session = await search.createSearchSession(widget.room);
      if (!isCurrent(revision)) {
        await session.dispose();
        return;
      }
      final previous = searchSession;
      searchSession = session;
      await previous?.dispose();
      listen(session.startSearch(value), revision);
    } catch (_) {
      onSearchFailed(revision);
    }
  }

  void continueSearch() {
    final session = searchSession;
    if (loading || session == null || !session.canContinueSearch) return;
    setState(() => loading = true);
    currentSubscription?.cancel();
    try {
      listen(session.continueSearch(), searchRevision);
    } catch (_) {
      onSearchFailed(searchRevision);
    }
  }

  void listen(Stream<List<TimelineEvent>> stream, int revision) {
    currentSubscription = stream.listen(
      (results) {
        if (!isCurrent(revision)) return;
        setState(() {
          loading = searchSession?.currentlySearching == true;
          currentResults = List.of(results);
        });
      },
      onError: (Object error, StackTrace stack) {
        onSearchFailed(revision);
      },
      onDone: () {
        if (!isCurrent(revision)) return;
        setState(() {
          loading = false;
          currentResults ??= [];
        });
      },
      cancelOnError: true,
    );
  }

  void onSearchFailed(int revision) {
    if (!isCurrent(revision)) return;
    setState(() {
      loading = false;
      failed = true;
    });
  }
}
