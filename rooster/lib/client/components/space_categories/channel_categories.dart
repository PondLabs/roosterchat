// A space's channels under headings, as on Discord: text channels and voice
// channels apart, and headings of the space admin's own above them. Kept in
// the space as one state event; a client that does not know it lists the
// channels as before. Pure Dart. See docs/channel-categories.md.

/// What a channel is for, which decides the heading it falls under when no
/// heading of the admin's holds it.
enum ChannelKind { text, voice }

enum ChannelCategoryKind {
  /// One of the admin's.
  custom,

  /// Every text channel not under a heading of the admin's.
  text,

  /// Every voice channel not under a heading of the admin's.
  voice,
}

class ChannelCategory {
  const ChannelCategory({required this.id, this.name, this.roomIds = const []});

  static const textId = 'text';
  static const voiceId = 'voice';

  final String id;

  /// The admin's name for it. Null on a built-in heading nobody renamed,
  /// which shows its translated name instead.
  final String? name;

  /// The channels the admin put under it. Built-in headings list none: they
  /// take every channel of their kind left over.
  final List<String> roomIds;

  ChannelCategoryKind get kind => switch (id) {
        textId => ChannelCategoryKind.text,
        voiceId => ChannelCategoryKind.voice,
        _ => ChannelCategoryKind.custom,
      };

  bool get isBuiltIn => kind != ChannelCategoryKind.custom;

  ChannelCategory copyWith({String? Function()? name, List<String>? roomIds}) =>
      ChannelCategory(
        id: id,
        name: name == null ? this.name : name(),
        roomIds: roomIds ?? this.roomIds,
      );

  /// Null for anything malformed, which is then left out rather than taking
  /// the whole list down.
  static ChannelCategory? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final name = json['name'];
    final rooms = json['rooms'];
    final category = ChannelCategory(
      id: id,
      name: name is String && name.trim().isNotEmpty ? name.trim() : null,
    );
    if (category.isBuiltIn || rooms is! List) return category;
    return category.copyWith(roomIds: rooms.whereType<String>().toList());
  }

  Map<String, Object?> toJson() => {
        'id': id,
        if (name != null) 'name': name,
        if (!isBuiltIn) 'rooms': roomIds,
      };
}

/// One heading and the channels under it, text channels first.
class ChannelSection<T> {
  const ChannelSection(this.category, this.channels);

  final ChannelCategory category;
  final List<T> channels;
}

class ChannelCategories {
  ChannelCategories(Iterable<ChannelCategory> categories)
      : categories = List.unmodifiable(_withBuiltIns(categories));

  /// In the space, state key "".
  static const stateEventType = 'chat.commet.space_categories';

  /// A space nobody has set headings for: text channels, then voice.
  static final defaults = ChannelCategories(const []);

  /// Every heading in order, the two built-in ones always among them.
  final List<ChannelCategory> categories;

  /// Drops repeated ids (the first one stays), and adds a built-in heading
  /// the list lacks at its end, so no channel is ever left out.
  static List<ChannelCategory> _withBuiltIns(
      Iterable<ChannelCategory> categories) {
    final seen = <String>{};
    final result = [
      for (final category in categories)
        if (seen.add(category.id)) category,
    ];
    for (final id in [ChannelCategory.textId, ChannelCategory.voiceId]) {
      if (seen.add(id)) result.add(ChannelCategory(id: id));
    }
    return result;
  }

  factory ChannelCategories.fromJson(Map<String, Object?>? content) {
    final list = content?['categories'];
    if (list is! List) return defaults;
    return ChannelCategories(list.map(ChannelCategory.fromJson).nonNulls);
  }

  Map<String, Object?> toJson() => {
        'categories': [for (final category in categories) category.toJson()],
      };

  Iterable<ChannelCategory> get custom => categories.where((c) => !c.isBuiltIn);

  ChannelCategory? byId(String id) {
    for (final category in categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  /// The heading of the admin's that holds [roomId], if any: the first one,
  /// should two list it.
  ChannelCategory? customCategoryOf(String roomId) {
    for (final category in custom) {
      if (category.roomIds.contains(roomId)) return category;
    }
    return null;
  }

  /// The built-in heading for channels of [kind].
  ChannelCategory builtInFor(ChannelKind kind) => byId(kind == ChannelKind.voice
      ? ChannelCategory.voiceId
      : ChannelCategory.textId)!;

  /// The heading [roomId], a channel of [kind], is listed under.
  ChannelCategory categoryOf(String roomId, ChannelKind kind) =>
      customCategoryOf(roomId) ?? builtInFor(kind);

  /// With a new heading of the admin's named [name], placed before the
  /// built-in ones so it reads first, as a space's own headings do.
  ChannelCategories withCategoryAdded(String id, String name) {
    final category = ChannelCategory(id: id, name: name.trim());
    final firstBuiltIn = categories.indexWhere((c) => c.isBuiltIn);
    final at = firstBuiltIn == -1 ? categories.length : firstBuiltIn;
    return ChannelCategories([
      ...categories.take(at),
      category,
      ...categories.skip(at),
    ]);
  }

  /// With heading [id] renamed. An empty [name] gives a built-in heading its
  /// translated name back; a heading of the admin's keeps the one it had.
  ChannelCategories withCategoryRenamed(String id, String name) {
    final trimmed = name.trim();
    return ChannelCategories([
      for (final category in categories)
        if (category.id != id)
          category
        else if (trimmed.isNotEmpty)
          category.copyWith(name: () => trimmed)
        else if (category.isBuiltIn)
          category.copyWith(name: () => null)
        else
          category,
    ]);
  }

  /// Without heading [id]. Its channels go back under the built-in heading
  /// of their kind. A built-in heading cannot be removed.
  ChannelCategories withCategoryRemoved(String id) => ChannelCategories([
        for (final category in categories)
          if (category.id != id || category.isBuiltIn) category,
      ]);

  /// With heading [id] moved [by] places (up when negative), stopping at
  /// either end.
  ChannelCategories withCategoryMoved(String id, int by) {
    final from = categories.indexWhere((c) => c.id == id);
    if (from == -1) return this;
    final to = (from + by).clamp(0, categories.length - 1);
    if (to == from) return this;
    final result = categories.toList();
    result.insert(to, result.removeAt(from));
    return ChannelCategories(result);
  }

  /// With [roomId] under heading [categoryId]. A built-in heading id (or
  /// one not in the list) takes it out of the admin's headings, back under
  /// the built-in heading of its kind.
  ChannelCategories withChannelIn(String roomId, String categoryId) =>
      ChannelCategories([
        for (final category in categories)
          if (category.isBuiltIn)
            category
          else if (category.id == categoryId)
            category.copyWith(roomIds: [
              ...category.roomIds.where((id) => id != roomId),
              roomId,
            ])
          else
            category.copyWith(
                roomIds: category.roomIds.where((id) => id != roomId).toList()),
      ]);

  /// [channels], in the space's order, under their headings. Inside a
  /// heading text channels come before voice channels and otherwise keep
  /// that order. Every heading of the admin's is listed, an empty one too,
  /// for channels to be put under; a built-in heading only with channels.
  List<ChannelSection<T>> layout<T>(
    Iterable<T> channels, {
    required String Function(T channel) idOf,
    required ChannelKind Function(T channel) kindOf,
  }) {
    final text = {for (final c in categories) c.id: <T>[]};
    final voice = {for (final c in categories) c.id: <T>[]};
    for (final channel in channels) {
      final kind = kindOf(channel);
      final category = categoryOf(idOf(channel), kind);
      (kind == ChannelKind.voice ? voice : text)[category.id]!.add(channel);
    }

    return [
      for (final category in categories)
        if (!category.isBuiltIn ||
            text[category.id]!.isNotEmpty ||
            voice[category.id]!.isNotEmpty)
          ChannelSection(
              category, [...text[category.id]!, ...voice[category.id]!]),
    ];
  }
}
