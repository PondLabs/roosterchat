// ROOSTER: Typed models for the stable event and account data types of
// Matrix v1.18 and v1.19 (T1.1b). Every model reads optional fields
// tolerantly (a wrong type becomes null, never a TypeError), keeps unknown
// keys in [additionalProperties] so a round trip loses nothing, and throws a
// [FormatException] only when a required field is missing or malformed. The
// legacy `im.ponies.*` image packs and `io.element.recent_emoji` keep their
// own models and are not changed here.

import 'package:matrix/matrix_api_lite/model/matrix_event.dart';
import 'package:matrix/matrix_api_lite/utils/try_get_map_extension.dart';

Map<String, Object?> _rest(Map<String, Object?> json, List<String> known) =>
    Map.fromEntries(json.entries.where((e) => !known.contains(e.key)));

Map<String, Object?>? _map(Object? value) {
  if (value is! Map) return null;
  try {
    return Map<String, Object?>.from(value);
  } catch (_) {
    return null;
  }
}

/// Parses with [fromJson], returning null instead of throwing when the JSON
/// lacks a required field.
T? _tryParse<T>(Object? json, T Function(Map<String, Object?>) fromJson) {
  final map = _map(json);
  if (map == null) return null;
  try {
    return fromJson(map);
  } on FormatException {
    return null;
  }
}

String _required(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Expected a string in "$key"', value);
  }
  return value;
}

/// The `info` object of an `m.image` message, an `m.sticker` or an image in
/// an image pack. `is_animated` is Matrix v1.18 (MSC4230).
class MatrixImageInfo {
  String? mimetype;
  int? size;
  int? w;
  int? h;
  String? thumbnailUrl;
  Map<String, Object?>? thumbnailFile;
  Map<String, Object?>? thumbnailInfo;

  /// Whether the image is animated. Null when the sender did not say.
  bool? isAnimated;
  Map<String, Object?> additionalProperties;

  static const _known = [
    'mimetype',
    'size',
    'w',
    'h',
    'thumbnail_url',
    'thumbnail_file',
    'thumbnail_info',
    'is_animated',
  ];

  MatrixImageInfo({
    this.mimetype,
    this.size,
    this.w,
    this.h,
    this.thumbnailUrl,
    this.thumbnailFile,
    this.thumbnailInfo,
    this.isAnimated,
    Map<String, Object?>? additionalProperties,
  }) : additionalProperties = additionalProperties ?? {};

  MatrixImageInfo.fromJson(Map<String, Object?> json)
      : mimetype = json.tryGet<String>('mimetype'),
        size = json.tryGet<int>('size'),
        w = json.tryGet<int>('w'),
        h = json.tryGet<int>('h'),
        thumbnailUrl = json.tryGet<String>('thumbnail_url'),
        thumbnailFile = json.tryGetMap<String, Object?>('thumbnail_file'),
        thumbnailInfo = json.tryGetMap<String, Object?>('thumbnail_info'),
        isAnimated = json.tryGet<bool>('is_animated'),
        additionalProperties = _rest(json, _known);

  Map<String, Object?> toJson() => {
        ...additionalProperties,
        if (mimetype != null) 'mimetype': mimetype,
        if (size != null) 'size': size,
        if (w != null) 'w': w,
        if (h != null) 'h': h,
        if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
        if (thumbnailFile != null) 'thumbnail_file': thumbnailFile,
        if (thumbnailInfo != null) 'thumbnail_info': thumbnailInfo,
        if (isAnimated != null) 'is_animated': isAnimated,
      };
}

extension MatrixImageInfoEventExtension on MatrixEvent {
  /// The typed `content.info` of an image or sticker, or null without one.
  MatrixImageInfo? get imageInfo {
    final info = content.tryGetMap<String, Object?>('info');
    return info == null ? null : MatrixImageInfo.fromJson(info);
  }

  /// `content.info.is_animated` (MSC4230), null when absent or malformed.
  bool? get isAnimated => imageInfo?.isAnimated;
}

/// Where an image pack or an image in it may be used.
abstract class ImagePackUsageTypes {
  static const String emoticon = 'emoticon';
  static const String sticker = 'sticker';
}

/// One image of an `m.room.image_pack` (Matrix v1.19, MSC2545).
class MatrixImagePackImage {
  String url;
  String? body;
  MatrixImageInfo? info;

  /// Raw usage strings, so values this client does not know survive a round
  /// trip. See [ImagePackUsageTypes].
  List<String>? usage;
  Map<String, Object?> additionalProperties;

  MatrixImagePackImage({
    required this.url,
    this.body,
    this.info,
    this.usage,
    Map<String, Object?>? additionalProperties,
  }) : additionalProperties = additionalProperties ?? {};

  MatrixImagePackImage.fromJson(Map<String, Object?> json)
      : url = _required(json, 'url'),
        body = json.tryGet<String>('body'),
        info = json.tryGetFromJson('info', MatrixImageInfo.fromJson),
        usage = json.tryGetList<String>('usage'),
        additionalProperties = _rest(json, ['url', 'body', 'info', 'usage']);

  Map<String, Object?> toJson() => {
        ...additionalProperties,
        'url': url,
        if (body != null) 'body': body,
        if (info != null) 'info': info!.toJson(),
        if (usage != null) 'usage': usage,
      };
}

/// The `pack` object of an image pack.
class MatrixImagePackInfo {
  String? displayName;
  String? avatarUrl;
  List<String>? usage;
  String? attribution;
  Map<String, Object?> additionalProperties;

  MatrixImagePackInfo({
    this.displayName,
    this.avatarUrl,
    this.usage,
    this.attribution,
    Map<String, Object?>? additionalProperties,
  }) : additionalProperties = additionalProperties ?? {};

  MatrixImagePackInfo.fromJson(Map<String, Object?> json)
      : displayName = json.tryGet<String>('display_name'),
        avatarUrl = json.tryGet<String>('avatar_url'),
        usage = json.tryGetList<String>('usage'),
        attribution = json.tryGet<String>('attribution'),
        additionalProperties = _rest(
          json,
          ['display_name', 'avatar_url', 'usage', 'attribution'],
        );

  Map<String, Object?> toJson() => {
        ...additionalProperties,
        if (displayName != null) 'display_name': displayName,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (usage != null) 'usage': usage,
        if (attribution != null) 'attribution': attribution,
      };
}

/// Content of `m.room.image_pack` (Matrix v1.19, MSC2545). Images without a
/// string `url` are dropped on read.
class MatrixImagePackContent {
  Map<String, MatrixImagePackImage> images;
  MatrixImagePackInfo? pack;
  Map<String, Object?> additionalProperties;

  MatrixImagePackContent({
    required this.images,
    this.pack,
    Map<String, Object?>? additionalProperties,
  }) : additionalProperties = additionalProperties ?? {};

  MatrixImagePackContent.fromJson(Map<String, Object?> json)
      : images = {
          for (final e in (_map(json['images']) ?? const {}).entries)
            if (_tryParse(e.value, MatrixImagePackImage.fromJson)
                case final image?)
              e.key: image,
        },
        pack = json.tryGetFromJson('pack', MatrixImagePackInfo.fromJson),
        additionalProperties = _rest(json, ['images', 'pack']);

  Map<String, Object?> toJson() => {
        ...additionalProperties,
        'images': images.map((k, v) => MapEntry(k, v.toJson())),
        if (pack != null) 'pack': pack!.toJson(),
      };
}

/// Content of the `m.image_pack.rooms` account data (Matrix v1.19, MSC2545):
/// the room packs a user enabled everywhere, as room id to state key to an
/// (empty, reserved) object.
class ImagePackRoomsContent {
  Map<String, Map<String, Map<String, Object?>>> rooms;
  Map<String, Object?> additionalProperties;

  ImagePackRoomsContent({
    required this.rooms,
    Map<String, Object?>? additionalProperties,
  }) : additionalProperties = additionalProperties ?? {};

  ImagePackRoomsContent.fromJson(Map<String, Object?> json)
      : rooms = {
          for (final room in (_map(json['rooms']) ?? const {}).entries)
            if (_map(room.value) case final packs?)
              room.key: {
                for (final pack in packs.entries)
                  if (_map(pack.value) case final value?) pack.key: value,
              },
        },
        additionalProperties = _rest(json, ['rooms']);

  Map<String, Object?> toJson() => {
        ...additionalProperties,
        'rooms': rooms,
      };
}

/// One entry of `m.recent_emoji`.
class RecentEmojiEntry {
  String emoji;
  int total;
  Map<String, Object?> additionalProperties;

  RecentEmojiEntry({
    required this.emoji,
    required this.total,
    Map<String, Object?>? additionalProperties,
  }) : additionalProperties = additionalProperties ?? {};

  RecentEmojiEntry.fromJson(Map<String, Object?> json)
      : emoji = _required(json, 'emoji'),
        total = json['total'] is int
            ? json['total'] as int
            : throw FormatException('Expected an int in "total"'),
        additionalProperties = _rest(json, ['emoji', 'total']);

  Map<String, Object?> toJson() => {
        ...additionalProperties,
        'emoji': emoji,
        'total': total,
      };
}

/// Content of the `m.recent_emoji` account data (Matrix v1.18, MSC4356),
/// most recent first. Malformed entries are dropped on read.
class RecentEmojiContent {
  List<RecentEmojiEntry> recentEmoji;
  Map<String, Object?> additionalProperties;

  RecentEmojiContent({
    required this.recentEmoji,
    Map<String, Object?>? additionalProperties,
  }) : additionalProperties = additionalProperties ?? {};

  RecentEmojiContent.fromJson(Map<String, Object?> json)
      : recentEmoji = [
          for (final item in json.tryGetList<Object?>('recent_emoji') ?? [])
            if (_tryParse(item, RecentEmojiEntry.fromJson) case final entry?)
              entry,
        ],
        additionalProperties = _rest(json, ['recent_emoji']);

  Map<String, Object?> toJson() => {
        ...additionalProperties,
        'recent_emoji': recentEmoji.map((e) => e.toJson()).toList(),
      };
}

/// Content of the `m.key_backup` account data (Matrix v1.19, MSC4287): the
/// user's choice to use server-side key backup, shared between clients.
class KeyBackupContent {
  bool? enabled;
  Map<String, Object?> additionalProperties;

  KeyBackupContent({this.enabled, Map<String, Object?>? additionalProperties})
      : additionalProperties = additionalProperties ?? {};

  KeyBackupContent.fromJson(Map<String, Object?> json)
      : enabled = json.tryGet<bool>('enabled'),
        additionalProperties = _rest(json, ['enabled']);

  Map<String, Object?> toJson() => {
        ...additionalProperties,
        if (enabled != null) 'enabled': enabled,
      };
}

/// Values of `default_action` in `m.invite_permission_config`.
abstract class InvitePermissionActions {
  static const String allow = 'allow';
  static const String block = 'block';
}

/// Content of the `m.invite_permission_config` account data (Matrix v1.18,
/// MSC4380): whether the user blocks invites.
class InvitePermissionConfigContent {
  /// Raw value, so unknown actions survive a round trip. See
  /// [InvitePermissionActions].
  String? defaultAction;
  Map<String, Object?> additionalProperties;

  InvitePermissionConfigContent({
    this.defaultAction,
    Map<String, Object?>? additionalProperties,
  }) : additionalProperties = additionalProperties ?? {};

  InvitePermissionConfigContent.fromJson(Map<String, Object?> json)
      : defaultAction = json.tryGet<String>('default_action'),
        additionalProperties = _rest(json, ['default_action']);

  /// True only for an explicit `block`; anything else allows invites.
  bool get blocksInvites => defaultAction == InvitePermissionActions.block;

  Map<String, Object?> toJson() => {
        ...additionalProperties,
        if (defaultAction != null) 'default_action': defaultAction,
      };
}

/// Content of the `m.room.policy` state event (Matrix v1.18, MSC4284): the
/// room's policy server and its signing keys.
class RoomPolicyContent {
  /// Server name of the policy server.
  String? via;

  /// Algorithm to unpadded base64 public key, e.g. `ed25519`.
  Map<String, String>? publicKeys;

  /// The single `public_key` of earlier drafts of MSC4284.
  String? publicKey;
  Map<String, Object?> additionalProperties;

  RoomPolicyContent({
    this.via,
    this.publicKeys,
    this.publicKey,
    Map<String, Object?>? additionalProperties,
  }) : additionalProperties = additionalProperties ?? {};

  RoomPolicyContent.fromJson(Map<String, Object?> json)
      : via = json.tryGet<String>('via'),
        publicKeys = json.tryGetMap<String, String>('public_keys'),
        publicKey = json.tryGet<String>('public_key'),
        additionalProperties =
            _rest(json, ['via', 'public_keys', 'public_key']);

  /// The ed25519 key, from `public_keys` or the older `public_key`.
  String? get ed25519PublicKey => publicKeys?['ed25519'] ?? publicKey;

  Map<String, Object?> toJson() => {
        ...additionalProperties,
        if (via != null) 'via': via,
        if (publicKeys != null) 'public_keys': publicKeys,
        if (publicKey != null) 'public_key': publicKey,
      };
}

/// Content of the `m.room_key_bundle` to-device event (Matrix v1.19,
/// MSC4268): where to download the encrypted bundle of a room's keys shared
/// on invite. [file] is the `EncryptedFile` JSON, kept as sent.
class RoomKeyBundleContent {
  String roomId;
  Map<String, Object?> file;
  Map<String, Object?> additionalProperties;

  RoomKeyBundleContent({
    required this.roomId,
    required this.file,
    Map<String, Object?>? additionalProperties,
  }) : additionalProperties = additionalProperties ?? {};

  RoomKeyBundleContent.fromJson(Map<String, Object?> json)
      : roomId = _required(json, 'room_id'),
        file = _map(json['file']) ??
            (throw FormatException('Expected an object in "file"')),
        additionalProperties = _rest(json, ['room_id', 'file']);

  /// Null when `room_id` or `file` is missing or malformed.
  static RoomKeyBundleContent? tryFromJson(Map<String, Object?> json) =>
      _tryParse(json, RoomKeyBundleContent.fromJson);

  Map<String, Object?> toJson() => {
        ...additionalProperties,
        'room_id': roomId,
        'file': file,
      };
}

/// The `application` of an `m.rtc.member`, e.g. `{"type": "m.call"}`.
class RtcMemberApplication {
  String? type;
  Map<String, Object?> additionalProperties;

  RtcMemberApplication({this.type, Map<String, Object?>? additionalProperties})
      : additionalProperties = additionalProperties ?? {};

  RtcMemberApplication.fromJson(Map<String, Object?> json)
      : type = json.tryGet<String>('type'),
        additionalProperties = _rest(json, ['type']);

  Map<String, Object?> toJson() => {
        ...additionalProperties,
        if (type != null) 'type': type,
      };
}

/// The `member` of an `m.rtc.member`: who joined, from which device.
class RtcMemberIdentity {
  String? id;
  String? userId;
  String? deviceId;
  Map<String, Object?> additionalProperties;

  RtcMemberIdentity({
    this.id,
    this.userId,
    this.deviceId,
    Map<String, Object?>? additionalProperties,
  }) : additionalProperties = additionalProperties ?? {};

  RtcMemberIdentity.fromJson(Map<String, Object?> json)
      : id = json.tryGet<String>('id'),
        userId = json.tryGet<String>('user_id'),
        deviceId = json.tryGet<String>('device_id'),
        additionalProperties = _rest(json, ['id', 'user_id', 'device_id']);

  Map<String, Object?> toJson() => {
        ...additionalProperties,
        if (id != null) 'id': id,
        if (userId != null) 'user_id': userId,
        if (deviceId != null) 'device_id': deviceId,
      };
}

/// Content of an `m.rtc.member` event (MSC4143): one device's membership of
/// a MatrixRTC slot. Empty content means the member left.
class RtcMemberContent {
  String? slotId;
  RtcMemberApplication? application;
  RtcMemberIdentity? member;
  List<Map<String, Object?>>? rtcTransports;
  List<String>? versions;
  Map<String, Object?> additionalProperties;

  static const _known = [
    'slot_id',
    'application',
    'member',
    'rtc_transports',
    'versions',
  ];

  RtcMemberContent({
    this.slotId,
    this.application,
    this.member,
    this.rtcTransports,
    this.versions,
    Map<String, Object?>? additionalProperties,
  }) : additionalProperties = additionalProperties ?? {};

  RtcMemberContent.fromJson(Map<String, Object?> json)
      : slotId = json.tryGet<String>('slot_id'),
        application =
            json.tryGetFromJson('application', RtcMemberApplication.fromJson),
        member = json.tryGetFromJson('member', RtcMemberIdentity.fromJson),
        rtcTransports = json
            .tryGetList<Object?>('rtc_transports')
            ?.map(_map)
            .whereType<Map<String, Object?>>()
            .toList(),
        versions = json.tryGetList<String>('versions'),
        additionalProperties = _rest(json, _known);

  /// True for the empty content that ends a membership.
  bool get isLeave =>
      slotId == null &&
      application == null &&
      member == null &&
      rtcTransports == null &&
      versions == null &&
      additionalProperties.isEmpty;

  Map<String, Object?> toJson() => {
        ...additionalProperties,
        if (slotId != null) 'slot_id': slotId,
        if (application != null) 'application': application!.toJson(),
        if (member != null) 'member': member!.toJson(),
        if (rtcTransports != null) 'rtc_transports': rtcTransports,
        if (versions != null) 'versions': versions,
      };
}
