import 'package:intl/intl.dart';

class RoomCreationStrings {
  static String get labelCreateRoom =>
      Intl.message("Create Room", name: "labelCreateRoom");

  static String get labelPickExistingRoom => Intl.message(
        "Existing Room",
        name: "labelPickExistingRoom",
      );

  static String get labelJoinRoom => Intl.message(
        "Join Room",
        name: "labelJoinRoom",
      );

  static String get labelRoomTypeTextChat => Intl.message("Text Chat",
      name: "labelRoomTypeTextChat",
      desc: "Label for creating a regular text based chat room");

  static String get labelRoomTypeVoiceChat => Intl.message(
        "Voice Chat",
        name: "labelRoomTypeVoiceChat",
      );

  static String get labelRoomTypePhotoAlbum => Intl.message(
        "Photo Album",
        name: "labelRoomTypePhotoAlbum",
      );

  static String get labelRoomTypeCalendar => Intl.message(
        "Calendar",
        name: "labelRoomTypeCalendar",
      );

  static String get labelRoomTypeSpace => Intl.message(
        "Space",
        name: "labelRoomTypeSpace",
      );

  static String get labelRoomCreateRoomHeading => Intl.message("Create Room:",
      name: "labelRoomCreateRoomHeading",
      desc:
          "In the dialog that adds a room, over the kinds of room that can be created (text chat, voice chat, photo album, calendar, space)");

  static String get labelRoomCreateErrorTitle => Intl.message("Error",
      name: "labelRoomCreateErrorTitle",
      desc:
          "Title of the dialog that shows why creating a room or space failed");

  // Made-up channel names in the examples that show what a space or a voice
  // chat looks like, in the dialog that adds a room. Any names that sound like
  // a group of friends' channels will do.

  static String get labelRoomSampleNameGeneral => Intl.message("General",
      name: "labelRoomSampleNameGeneral",
      desc:
          "Example channel name (the usual main chat) in the pictures of a space and of a voice chat, in the dialog that adds a room");

  static String get labelRoomSampleNameRandom => Intl.message("Random",
      name: "labelRoomSampleNameRandom",
      desc:
          "Example channel name (off-topic chat) in the picture of a space, in the dialog that adds a room");

  static String get labelRoomSampleNameHelp => Intl.message("help",
      name: "labelRoomSampleNameHelp",
      desc:
          "Example channel name, lowercase on purpose, in the picture of a space, in the dialog that adds a room");

  static String get labelRoomSampleNameShipposting => Intl.message(
      "shipposting",
      name: "labelRoomSampleNameShipposting",
      desc:
          "Example channel name, a joke (posting about fictional couples, a play on 'shitposting'), lowercase on purpose, in the picture of a space, in the dialog that adds a room. Any playful channel name will do");

  static String get labelRoomSampleNameModding => Intl.message("Modding",
      name: "labelRoomSampleNameModding",
      desc:
          "Example channel name (about game mods) in the picture of a space, in the dialog that adds a room");

  static String get labelRoomSampleNameSupport => Intl.message("Support",
      name: "labelRoomSampleNameSupport",
      desc:
          "Example channel name in the picture of a space, in the dialog that adds a room");

  static String get labelRoomSampleNameChat => Intl.message("Chat",
      name: "labelRoomSampleNameChat",
      desc:
          "Example channel name in the picture of a space, in the dialog that adds a room");

  static String get labelRoomSampleNameWisdom => Intl.message("Wisdom",
      name: "labelRoomSampleNameWisdom",
      desc:
          "Example channel name in the picture of a space, in the dialog that adds a room");

  static String get labelRoomSampleNameShowcase => Intl.message("Showcase",
      name: "labelRoomSampleNameShowcase",
      desc:
          "Example channel name (where people show what they made) in the picture of a space, in the dialog that adds a room");

  static String get labelRoomSampleNameCommunity => Intl.message("Community",
      name: "labelRoomSampleNameCommunity",
      desc:
          "Example channel name in the picture of a space, in the dialog that adds a room");

  static String get labelRoomSampleNameSuggestions => Intl.message(
      "Suggestions",
      name: "labelRoomSampleNameSuggestions",
      desc:
          "Example channel name in the picture of a space, in the dialog that adds a room");

  static String get labelRoomSampleNameAnnouncements => Intl.message(
      "Announcements",
      name: "labelRoomSampleNameAnnouncements",
      desc:
          "Example channel name in the picture of a space, in the dialog that adds a room");

  static String get labelRoomSampleNameGaming => Intl.message("Gaming",
      name: "labelRoomSampleNameGaming",
      desc:
          "Example voice channel name (playing games together) in the picture of a space, in the dialog that adds a room");

  static String get labelRoomSampleNameMovieNight => Intl.message("Movie Night",
      name: "labelRoomSampleNameMovieNight",
      desc:
          "Example voice channel name in the picture of a space, in the dialog that adds a room");

  static String get labelRoomSampleNamePhotoDump => Intl.message(
      "Random Photo Dump",
      name: "labelRoomSampleNamePhotoDump",
      desc:
          "Example photo album name (a place to throw any photos) in the picture of a space, in the dialog that adds a room");

  static String get labelRoomSampleNameClips => Intl.message("Clips",
      name: "labelRoomSampleNameClips",
      desc:
          "Example photo album name (short videos, such as game clips) in the picture of a space, in the dialog that adds a room");

  static String get labelRoomSampleNameArt => Intl.message("Art",
      name: "labelRoomSampleNameArt",
      desc:
          "Example photo album name in the picture of a space, in the dialog that adds a room");

  static String get labelRoomSampleNameCalendar => Intl.message("Calendar",
      name: "labelRoomSampleNameCalendar",
      desc:
          "Example calendar name in the picture of a space, in the dialog that adds a room");

  static String get labelRoomSampleNameWorkSchedule => Intl.message(
      "Work Schedule",
      name: "labelRoomSampleNameWorkSchedule",
      desc:
          "Example calendar name in the picture of a space, in the dialog that adds a room");
}
