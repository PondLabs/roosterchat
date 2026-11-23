import 'package:rooster/client/client.dart';
import 'package:flutter/material.dart';

enum RoomPreviewType { room, space, inaccessible }

abstract class RoomPreview {
  String get roomId;
  ImageProvider? get avatar;
  String get displayName;
  String? get topic;
  Color get color;
  RoomType? get type;
  int? get numMembers;
  RoomVisibility? get visibility;
  String? get joinRule;
  List<String> get via;

  bool get canKnock => isKnockJoinRule(joinRule);

  static bool isKnockJoinRule(String? joinRule) =>
      joinRule == 'knock' || joinRule == 'knock_restricted';
}

class GenericRoomPreview implements RoomPreview {
  @override
  String roomId;

  @override
  ImageProvider? avatar;

  @override
  String displayName;

  @override
  String? topic;

  @override
  int? numMembers;

  @override
  RoomType? type;

  @override
  String? joinRule;

  @override
  List<String> via;

  @override
  bool get canKnock => RoomPreview.isKnockJoinRule(joinRule);

  GenericRoomPreview(this.roomId,
      {this.avatar,
      required this.displayName,
      required this.type,
      this.numMembers,
      this.visibility,
      this.joinRule,
      this.via = const [],
      this.topic});

  @override
  Color get color => Colors.grey;

  @override
  RoomVisibility? visibility;
}
