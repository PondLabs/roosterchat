import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MatrixWidgetCapabilityString {
  final String raw;
  final String capability;
  final String? eventType;
  final String? eventKey;

  MatrixWidgetCapabilityString(this.capability,
      {this.eventType, this.eventKey, required this.raw});

  static MatrixWidgetCapabilityString parse(String name) {
    var split = name.split((":"));
    var parsedName = split.first;

    String? eventType;
    String? eventKey;

    if (split.length == 1) {
      return MatrixWidgetCapabilityString(parsedName, raw: name);
    }

    var splitRemainder = split.sublist(1).join(":");

    var eventTypeSplit = splitRemainder.split("#");

    eventType = eventTypeSplit.first;

    if (eventType.endsWith("#")) {
      eventKey = "";
    }

    if (eventTypeSplit.length >= 2) {
      eventKey = eventTypeSplit.sublist(1).join("#");
    }

    return MatrixWidgetCapabilityString(parsedName,
        eventType: eventType, eventKey: eventKey, raw: name);
  }
}

enum WidgetPermissionSeverity {
  low,
  mild,
  high,
  critical,
}

class MatrixWidgetPermissionGroup {
  List<MatrixWidgetCapabilityString> permissions;

  String name;

  String description;

  WidgetPermissionSeverity severity;

  bool defaultValue;

  IconData icon;

  MatrixWidgetPermissionGroup({
    required this.name,
    required this.permissions,
    required this.severity,
    required this.defaultValue,
    required this.description,
    required this.icon,
  });

  // Shown when a room widget (a small web app added to a room) asks for
  // permissions: a group's name and what it lets the widget do.

  static String get labelWidgetPermissionCustomEvents => Intl.message(
      "Custom Events",
      name: "labelWidgetPermissionCustomEvents",
      desc:
          "A group of permissions a room widget asks for: sending and receiving the widget's own kinds of Matrix events");

  static String get labelWidgetPermissionCustomEventsDescription => Intl.message(
      "Send and receive custom event data",
      name: "labelWidgetPermissionCustomEventsDescription",
      desc:
          "What the 'Custom Events' permissions let a room widget do, in the dialog where it asks for them");

  static String get labelWidgetPermissionMedia => Intl.message("Media",
      name: "labelWidgetPermissionMedia",
      desc:
          "A group of permissions a room widget asks for: uploading and downloading files");

  static String get labelWidgetPermissionMediaDescription => Intl.message(
      "Upload and download files from your homeserver",
      name: "labelWidgetPermissionMediaDescription",
      desc:
          "What the 'Media' permissions let a room widget do, in the dialog where it asks for them");

  static String get labelWidgetPermissionReadRoom => Intl.message(
      "Read Room Information",
      name: "labelWidgetPermissionReadRoom",
      desc:
          "A group of permissions a room widget asks for: reading the room's name, members and settings");

  static String get labelWidgetPermissionReadRoomDescription => Intl.message(
      "Read information about the current room state, such as name and members",
      name: "labelWidgetPermissionReadRoomDescription",
      desc:
          "What the 'Read Room Information' permissions let a room widget do, in the dialog where it asks for them");

  static String get labelWidgetPermissionManageChat => Intl.message(
      "Manage Chat",
      name: "labelWidgetPermissionManageChat",
      desc:
          "A group of permissions a room widget asks for: reading, sending and deleting the room's messages");

  static String get labelWidgetPermissionManageChatDescription => Intl.message(
      "Read, send and delete messages in this room",
      name: "labelWidgetPermissionManageChatDescription",
      desc:
          "What the 'Manage Chat' permissions let a room widget do, in the dialog where it asks for them");

  static String get labelWidgetPermissionAdmin => Intl.message("Admin Powers",
      name: "labelWidgetPermissionAdmin",
      desc:
          "A group of permissions a room widget asks for: changing who may do what in the room");

  static String get labelWidgetPermissionAdminDescription => Intl.message(
      "Change permissions and user roles / power levels.\nAdditional confirmation will be asked later, when the widget attempts to make changes",
      name: "labelWidgetPermissionAdminDescription",
      desc:
          "What the 'Admin Powers' permissions let a room widget do, in the dialog where it asks for them. Two lines");

  static String get labelWidgetPermissionCalls => Intl.message(
      "Call Permissions",
      name: "labelWidgetPermissionCalls",
      desc:
          "A group of permissions a room widget asks for: what a call widget needs to run a call");

  static String get labelWidgetPermissionCallsDescription => Intl.message(
      "Make, manage and join calls",
      name: "labelWidgetPermissionCallsDescription",
      desc:
          "What the 'Call Permissions' let a room widget do, in the dialog where it asks for them");

  static String get labelWidgetPermissionNavigate => Intl.message(
      "Open Rooms and Stay on Screen",
      name: "labelWidgetPermissionNavigate",
      desc:
          "A group of permissions a room widget asks for: opening rooms and profiles from matrix.to links, and staying visible");

  static String get labelWidgetPermissionNavigateDescription => Intl.message(
      "Open rooms and profiles for you, and stay visible while you use the app",
      name: "labelWidgetPermissionNavigateDescription",
      desc:
          "What the 'Open Rooms and Stay on Screen' permissions let a room widget do, in the dialog where it asks for them");

  static String get labelWidgetPermissionUserDirectory => Intl.message(
      "Search Users",
      name: "labelWidgetPermissionUserDirectory",
      desc:
          "A group of permissions a room widget asks for: searching the homeserver's list of users");

  static String get labelWidgetPermissionUserDirectoryDescription => Intl.message(
      "Search your homeserver's user directory",
      name: "labelWidgetPermissionUserDirectoryDescription",
      desc:
          "What the 'Search Users' permission lets a room widget do, in the dialog where it asks for it");

  static List<MatrixWidgetPermissionGroup> permissionGroups() {
    return [
      adminPowers(),
      modifyChats(),
      callPermissions(),
      readRoomInformation(),
      media(),
      navigate(),
      userDirectory(),
    ];
  }

  static (List<MatrixWidgetPermissionGroup>, List<MatrixWidgetCapabilityString>)
      groupPermissions(List<String> capabilities) {
    final templateGroups = permissionGroups();

    Map<String, MatrixWidgetPermissionGroup> groups = {};

    for (var template in templateGroups) {
      groups[template.name] = MatrixWidgetPermissionGroup(
          name: template.name,
          defaultValue: template.defaultValue,
          permissions: List.empty(growable: true),
          severity: template.severity,
          icon: template.icon,
          description: template.description);
    }

    groups["custom_events"] = MatrixWidgetPermissionGroup(
        name: labelWidgetPermissionCustomEvents,
        defaultValue: true,
        permissions: List.empty(growable: true),
        icon: Icons.code,
        severity: WidgetPermissionSeverity.low,
        description: labelWidgetPermissionCustomEventsDescription);

    List<MatrixWidgetCapabilityString> ungrouped = List.empty(growable: true);

    for (var capability in capabilities) {
      var parsed = MatrixWidgetCapabilityString.parse(capability);

      bool grouped = false;

      for (var template in templateGroups) {
        if (template.permissions.any((i) =>
            i.capability == parsed.capability &&
            (i.eventType == null || i.eventType == parsed.eventType))) {
          groups[template.name]!.permissions.add(parsed);
          grouped = true;
          break;
        }
      }

      if (grouped == false) {
        if ([
          "org.matrix.msc2762.send.event",
          "org.matrix.msc2762.receive.event",
          "org.matrix.msc2762.send.state_event",
          "org.matrix.msc2762.receive.state_event",
          "org.matrix.msc3819.send.to_device",
          "org.matrix.msc3819.receive.to_device",
        ].contains(parsed.capability)) {
          if (parsed.eventType != null &&
              parsed.eventType!.startsWith("m.") == false) {
            groups["custom_events"]!.permissions.add(parsed);
            grouped = true;
          }
        }
      }

      if (!grouped) {
        ungrouped.add(parsed);
      }
    }

    return (
      groups.values.where((i) => i.permissions.isNotEmpty).toList(),
      ungrouped
    );
  }

  // Unticked until the user ticks them: these act outside the widget.
  static MatrixWidgetPermissionGroup navigate() {
    return MatrixWidgetPermissionGroup(
        name: labelWidgetPermissionNavigate,
        description: labelWidgetPermissionNavigateDescription,
        severity: WidgetPermissionSeverity.mild,
        defaultValue: false,
        icon: Icons.open_in_new_rounded,
        permissions: [
          "org.matrix.msc2931.navigate",
          "m.always_on_screen",
        ].map((i) => MatrixWidgetCapabilityString.parse(i)).toList());
  }

  static MatrixWidgetPermissionGroup userDirectory() {
    return MatrixWidgetPermissionGroup(
        name: labelWidgetPermissionUserDirectory,
        description: labelWidgetPermissionUserDirectoryDescription,
        severity: WidgetPermissionSeverity.mild,
        defaultValue: false,
        icon: Icons.person_search_rounded,
        permissions: [
          "org.matrix.msc3973.user_directory_search",
        ].map((i) => MatrixWidgetCapabilityString.parse(i)).toList());
  }

  static MatrixWidgetPermissionGroup media() {
    return MatrixWidgetPermissionGroup(
        name: labelWidgetPermissionMedia,
        description: labelWidgetPermissionMediaDescription,
        severity: WidgetPermissionSeverity.low,
        defaultValue: true,
        icon: Icons.file_copy_rounded,
        permissions: [
          "org.matrix.msc4039.upload_file",
          "org.matrix.msc4039.download_file"
        ].map((i) => MatrixWidgetCapabilityString.parse(i)).toList());
  }

  static MatrixWidgetPermissionGroup readRoomInformation() {
    return MatrixWidgetPermissionGroup(
        name: labelWidgetPermissionReadRoom,
        description: labelWidgetPermissionReadRoomDescription,
        severity: WidgetPermissionSeverity.low,
        defaultValue: true,
        icon: Icons.tag,
        permissions: [
          "org.matrix.msc2762.receive.state_event:m.room.create",
          "org.matrix.msc2762.receive.state_event:m.room.name",
          "org.matrix.msc2762.receive.state_event:m.room.member",
          "org.matrix.msc2762.receive.state_event:m.room.encryption",
          "org.matrix.msc2762.receive.state_event:m.room.power_levels",
        ].map((i) => MatrixWidgetCapabilityString.parse(i)).toList());
  }

  static MatrixWidgetPermissionGroup modifyChats() {
    return MatrixWidgetPermissionGroup(
        name: labelWidgetPermissionManageChat,
        description: labelWidgetPermissionManageChatDescription,
        defaultValue: false,
        icon: Icons.message_rounded,
        severity: WidgetPermissionSeverity.high,
        permissions: [
          "org.matrix.msc2762.send.event:m.room.redaction",
          "org.matrix.msc2762.receive.event:m.room.redaction",
          "org.matrix.msc2762.send.event:m.reaction",
          "org.matrix.msc2762.receive.event:m.reaction",
          "org.matrix.msc2762.send.event:m.room.message",
          "org.matrix.msc2762.timeline",
        ].map((i) => MatrixWidgetCapabilityString.parse(i)).toList());
  }

  static MatrixWidgetPermissionGroup adminPowers() {
    return MatrixWidgetPermissionGroup(
        name: labelWidgetPermissionAdmin,
        description: labelWidgetPermissionAdminDescription,
        defaultValue: true,
        icon: Icons.security,
        severity: WidgetPermissionSeverity.mild,
        permissions: [
          "org.matrix.msc2762.send.state_event:m.room.power_levels",
        ].map((i) => MatrixWidgetCapabilityString.parse(i)).toList());
  }

  static MatrixWidgetPermissionGroup callPermissions() {
    return MatrixWidgetPermissionGroup(
        name: labelWidgetPermissionCalls,
        description: labelWidgetPermissionCallsDescription,
        icon: Icons.call_rounded,
        defaultValue: true,
        severity: WidgetPermissionSeverity.mild,
        permissions: [
          "org.matrix.msc2762.send.event:io.element.call.encryption_keys",
          "org.matrix.msc3819.receive.to_device:io.element.call.encryption_keys",
          "org.matrix.msc2762.send.event:io.element.call.reaction",
          "org.matrix.msc2762.send.event:org.matrix.msc4310.rtc.decline",
          "org.matrix.msc2762.send.event:org.matrix.msc4143.rtc.member",
          "org.matrix.msc2762.receive.event:io.element.call.encryption_keys",
          "org.matrix.msc2762.receive.event:io.element.call.reaction",
          "org.matrix.msc2762.receive.event:org.matrix.msc4310.rtc.decline",
          "org.matrix.msc2762.receive.event:org.matrix.msc4143.rtc.member",
          "org.matrix.msc2762.send.state_event:org.matrix.msc3401.call.member",
          "org.matrix.msc2762.receive.state_event:org.matrix.msc3401.call.member",
          "org.matrix.msc3819.send.to_device:m.call.invite",
          "org.matrix.msc3819.send.to_device:m.call.candidates",
          "org.matrix.msc3819.send.to_device:m.call.answer",
          "org.matrix.msc3819.send.to_device:m.call.hangup",
          "org.matrix.msc3819.send.to_device:m.call.reject",
          "org.matrix.msc3819.send.to_device:m.call.select_answer",
          "org.matrix.msc3819.send.to_device:m.call.negotiate",
          "org.matrix.msc3819.send.to_device:m.call.sdp_stream_metadata_changed",
          "org.matrix.msc3819.send.to_device:org.matrix.call.sdp_stream_metadata_changed",
          "org.matrix.msc3819.send.to_device:m.call.replaces",
          "org.matrix.msc3819.send.to_device:io.element.call.encryption_keys",
          "org.matrix.msc3819.receive.to_device:m.call.invite",
          "org.matrix.msc3819.receive.to_device:m.call.candidates",
          "org.matrix.msc3819.receive.to_device:m.call.answer",
          "org.matrix.msc3819.receive.to_device:m.call.hangup",
          "org.matrix.msc3819.receive.to_device:m.call.reject",
          "org.matrix.msc3819.receive.to_device:m.call.select_answer",
          "org.matrix.msc3819.receive.to_device:m.call.negotiate",
          "org.matrix.msc3819.receive.to_device:m.call.sdp_stream_metadata_changed",
          "org.matrix.msc3819.receive.to_device:org.matrix.call.sdp_stream_metadata_changed",
          "org.matrix.msc3819.receive.to_device:m.call.replaces",
          "org.matrix.msc2762.send.event:org.matrix.msc4075.call.notify",
          "org.matrix.msc2762.send.event:org.matrix.msc4075.rtc.notification",
          // Maybe these dont need to be in this category?
          "org.matrix.msc4157.send.delayed_event",
          "org.matrix.msc4157.update_delayed_event",
          "org.matrix.msc4407.send.sticky_event",
          "org.matrix.msc4407.receive.sticky_event",
        ].map((i) => MatrixWidgetCapabilityString.parse(i)).toList());
  }
}
