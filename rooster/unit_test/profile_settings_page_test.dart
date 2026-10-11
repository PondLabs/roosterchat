// Settings > Profile (profile_editor.dart): edits stay in a draft the preview
// shows, and Save writes only what changed.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/components/user_color/user_color_component.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/organisms/user_profile/user_profile_view.dart';
import 'package:rooster/ui/pages/settings/categories/account/profile/name_color_palette.dart';
import 'package:rooster/ui/pages/settings/categories/account/profile/profile_editor.dart';
import 'package:rooster/ui/pages/settings/desktop_settings_page.dart';
import 'package:rooster/ui/pages/settings/settings_category.dart';
import 'package:rooster/ui/pages/settings/settings_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

const me = "@alice:example.org";

class _Profile implements Profile {
  @override
  String get identifier => me;
  @override
  String get displayName => "Alice";
  @override
  ImageProvider? get avatar => null;
  @override
  ImageProvider? get banner => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileComponent implements UserProfileComponent {
  _ProfileComponent(this.badges);
  final List<ProfileBadge> badges;

  @override
  Future<Profile> getProfile(String identifier) async => _Profile();
  @override
  Future<List<ProfileBadge>> getAvailableBadges() async => badges;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Colors implements UserColorComponent {
  _Colors(this.own);
  final NameColor? own;
  final written = <NameColor?>[];

  @override
  Future<NameColor?> getOwnPublicColor() async => own;
  @override
  Future<void> setOwnPublicColor(NameColor? color) async => written.add(color);
  @override
  Color? getOverride(String identifier) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements Client {
  _Client(this.components);
  final List<Component> components;
  final names = <String>[];
  bool nameFails = false;

  @override
  Profile? self = _Profile();
  @override
  String get identifier => "client";
  @override
  Future<void> setDisplayName(String name) async {
    if (nameFails) throw Exception("M_FORBIDDEN");
    names.add(name);
  }

  @override
  T? getComponent<T extends Component>() =>
      components.whereType<T>().firstOrNull;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Category implements SettingsCategory {
  @override
  String? get title => null;
  @override
  List<SettingsTab> get tabs => [
        SettingsTab(label: "A", pageBuilder: (_) => const Text("page A")),
        SettingsTab(label: "B", pageBuilder: (_) => const Text("page B")),
      ];
}

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'),
            (call) async => "Europe/Lisbon");
  });

  late _Client client;
  late _Colors colors;

  Future<void> pumpEditor(WidgetTester tester,
      {NameColor? own, List<ProfileBadge> badges = const []}) async {
    colors = _Colors(own);
    client = _Client([_ProfileComponent(badges), colors]);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(body: ProfileEditor(client: client)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  String previewName(WidgetTester tester) =>
      tester.widget<UserProfileView>(find.byType(UserProfileView)).displayName;

  testWidgets('every section shows, badges only when there are some',
      (tester) async {
    await pumpEditor(tester);

    for (final heading in [
      "Picture and banner",
      "Name",
      "About you",
      "Colors",
      "Preview",
      "In chat",
    ]) {
      expect(find.text(heading), findsOneWidget, reason: heading);
    }
    expect(find.text("Show my local time"), findsOneWidget);
    expect(find.byType(UserProfileView), findsOneWidget);
    expect(find.text("Badges"), findsNothing);
    expect(find.text("You have unsaved changes."), findsNothing);
  });

  testWidgets('on a wide pane the preview sits beside the form',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpEditor(tester);

    final card = tester.getRect(find.byType(UserProfileView));
    final form = tester.getRect(find.byKey(ProfileEditor.nameFieldKey));
    expect(card.left, greaterThan(form.right));
    expect(card.width, 380);
  });

  testWidgets('a new name shows in the preview and Reset takes it back',
      (tester) async {
    await pumpEditor(tester);
    expect(previewName(tester), "Alice");

    await tester.enterText(find.byKey(ProfileEditor.nameFieldKey), "Ally");
    await tester.pumpAndSettle();
    expect(previewName(tester), "Ally");
    expect(find.text("You have unsaved changes."), findsOneWidget);

    await tap(tester, find.text("Reset"));
    expect(previewName(tester), "Alice");
    expect(find.text("You have unsaved changes."), findsNothing);
    expect(client.names, isEmpty);
  });

  testWidgets('Save writes the trimmed name and the picked name color',
      (tester) async {
    await pumpEditor(tester);

    await tap(tester, find.byKey(const ValueKey("profile-name-color-2")));
    await tester.enterText(find.byKey(ProfileEditor.nameFieldKey), "  Ally ");
    await tap(tester, find.byKey(ProfileEditor.saveKey));

    expect(client.names, ["Ally"]);
    expect(colors.written, [namePalette[2]]);
    expect(find.text("You have unsaved changes."), findsNothing);
  });

  testWidgets('what fails to save stays to try again, what saved does not',
      (tester) async {
    await pumpEditor(tester);
    client.nameFails = true;

    await tap(tester, find.byKey(const ValueKey("profile-name-color-4")));
    await tester.enterText(find.byKey(ProfileEditor.nameFieldKey), "Ally");
    await tap(tester, find.byKey(ProfileEditor.saveKey));

    expect(colors.written, [namePalette[4]]);
    expect(client.names, isEmpty);
    expect(find.text("You have unsaved changes."), findsOneWidget);
    expect(find.textContaining("could not be saved"), findsOneWidget);
    expect(previewName(tester), "Ally");

    client.nameFails = false;
    await tap(tester, find.byKey(ProfileEditor.saveKey));

    expect(client.names, ["Ally"]);
    expect(colors.written, [namePalette[4]]);
    expect(find.text("You have unsaved changes."), findsNothing);
  });

  testWidgets('settings can open on a given tab', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [ThemeSettings()]),
      home: DesktopSettingsPage(settings: [_Category()], initialTab: (0, 1)),
    ));
    await tester.pumpAndSettle();

    expect(find.text("page B"), findsOneWidget);
    expect(find.text("page A"), findsNothing);
  });

  testWidgets('choosing Automatic removes the name color', (tester) async {
    await pumpEditor(tester, own: namePalette[5]);

    await tap(
        tester, find.byKey(const ValueKey("profile-name-color-automatic")));
    await tap(tester, find.byKey(ProfileEditor.saveKey));

    expect(colors.written, [null]);
    expect(client.names, isEmpty);
  });
}
