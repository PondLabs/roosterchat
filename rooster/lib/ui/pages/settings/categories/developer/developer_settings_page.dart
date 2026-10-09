import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:rooster/client/components/push_notification/linux/linux_notifier.dart';
import 'package:rooster/client/components/push_notification/notification_content.dart';
import 'package:rooster/client/components/push_notification/notification_manager.dart';
import 'package:rooster/config/app_config.dart';
import 'package:rooster/config/build_config.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/diagnostic/diagnostics.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/code_block.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/navigation/navigation_utils.dart';
import 'package:rooster/ui/pages/developer/benchmarks/timeline_viewer_benchmark.dart';
import 'package:rooster/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:rooster/ui/pages/settings/categories/app/double_preference_slider.dart';
import 'package:rooster/ui/pages/settings/categories/developer/cumulative_diagnostics_widget.dart';
import 'package:rooster/utils/background_tasks/background_task_manager.dart';
import 'package:rooster/utils/background_tasks/mock_tasks.dart';
import 'package:rooster/utils/system_processes_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:window_manager/window_manager.dart';

class DeveloperSettingsPage extends StatefulWidget {
  const DeveloperSettingsPage({super.key});

  @override
  State<DeveloperSettingsPage> createState() => _DeveloperSettingsPageState();
}

class _DeveloperSettingsPageState extends State<DeveloperSettingsPage> {
  String get labelDeveloperOtherSettings => Intl.message("Other Settings",
      name: "labelDeveloperOtherSettings",
      desc: "Header of the last panel in Developer settings, holding the "
          "developer toggles that have no section of their own");

  String get labelDeveloperDisableTextCursorManagement =>
      Intl.message("Disable Text Cursor Management",
          name: "labelDeveloperDisableTextCursorManagement",
          desc: "Title of a developer setting that stops the rich text editor "
              "from moving the text cursor by itself");

  String get labelDeveloperDisableTextCursorManagementDescription => Intl.message(
      "As part of the implementation for the rich text editor, we sometimes have to make automated changes to the text cursor. This disables that",
      name: "labelDeveloperDisableTextCursorManagementDescription",
      desc: "Description under the developer setting 'Disable Text Cursor "
          "Management'");

  String get labelDeveloperUseSharedIsolateInBackground =>
      Intl.message("Use shared database isolate in background",
          name: "labelDeveloperUseSharedIsolateInBackground",
          desc: "Title of a developer setting: background tasks use the same "
              "database isolate (a Dart worker thread) as the app");

  String get labelDeveloperShowTranslationKeys =>
      Intl.message("Show translation keys",
          name: "labelDeveloperShowTranslationKeys",
          desc: "Title of a developer setting that shows each string's "
              "translation key instead of its text, to check translations");

  String get labelDeveloperShowTranslationKeysDescription =>
      Intl.message("Shows each string's key instead of its text",
          name: "labelDeveloperShowTranslationKeysDescription",
          desc: "Description under the developer setting 'Show translation "
              "keys'");

  String get labelDeveloperPseudoTranslations =>
      Intl.message("Pseudo-translations",
          name: "labelDeveloperPseudoTranslations",
          desc: "Title of a developer setting that shows every string "
              "accented and stretched, the way a long language would, to find "
              "text that is cut off or not translated");

  String get labelDeveloperPseudoTranslationsDescription => Intl.message(
      "Shows every string accented and a lot longer, between brackets, to find text that gets cut off or is not translated",
      name: "labelDeveloperPseudoTranslationsDescription",
      desc: "Description under the developer setting 'Pseudo-translations'");

  String get labelDeveloperKeyboardOffset => Intl.message("Keyboard Offset",
      name: "labelDeveloperKeyboardOffset",
      desc: "Title of a developer slider: how far the app moves up when the "
          "on-screen keyboard opens");

  String get labelDeveloperKeyboardOffsetDescription => Intl.message(
      "Amount to shift the app view up by when the onscreen keyboard is shown",
      name: "labelDeveloperKeyboardOffsetDescription",
      desc: "Description under the developer slider 'Keyboard Offset'");

  String get labelDeveloperPerformance => Intl.message("Performance",
      name: "labelDeveloperPerformance",
      desc: "Title of the Developer settings section with performance "
          "measurements");

  String get labelDeveloperDiagnosticsGeneral => Intl.message("General",
      name: "labelDeveloperDiagnosticsGeneral",
      desc: "In Developer settings > Performance: the group of performance "
          "measurements that are not about the database");

  String get labelDeveloperDiagnosticsInitialLoad =>
      Intl.message("Initial Load Database Diagnostics",
          name: "labelDeveloperDiagnosticsInitialLoad",
          desc: "In Developer settings > Performance: the group of database "
              "timings measured while the app first loads");

  String get labelDeveloperDiagnosticsPostLoad =>
      Intl.message("Post Load Database Diagnostics",
          name: "labelDeveloperDiagnosticsPostLoad",
          desc: "In Developer settings > Performance: the group of database "
              "timings measured after the app has loaded");

  String get labelDeveloperRendering => Intl.message("Rendering",
      name: "labelDeveloperRendering",
      desc: "Title of the Developer settings section with drawing (rendering) "
          "debug options");

  String get labelDeveloperShowRepaints => Intl.message("Show repaints",
      name: "labelDeveloperShowRepaints",
      desc: "Developer toggle that colours every area of the screen each time "
          "it is drawn again");

  String get labelDeveloperShowPerformanceOverlay => Intl.message(
      "Show performance overlay",
      name: "labelDeveloperShowPerformanceOverlay",
      desc: "Developer toggle that shows Flutter's frame timing graphs over "
          "the app");

  String get labelDeveloperRequiresRestart => Intl.message("Requires restart",
      name: "labelDeveloperRequiresRestart",
      desc: "Under a developer toggle: it only takes effect after the app is "
          "restarted");

  String get labelDeveloperBenchmarks => Intl.message("Benchmarks",
      name: "labelDeveloperBenchmarks",
      desc: "Title of the Developer settings section with performance tests");

  String get promptDeveloperTimelineViewer => Intl.message("Timeline Viewer",
      name: "promptDeveloperTimelineViewer",
      desc: "Button in Developer settings > Benchmarks that opens a test chat "
          "timeline full of generated messages");

  String get promptDeveloperNotificationBadgesStressTest =>
      Intl.message("Notification Badges Stress Test",
          name: "promptDeveloperNotificationBadgesStressTest",
          desc: "Button in Developer settings > Benchmarks that changes the "
              "unread count badge on the taskbar thousands of times");

  String get labelDeveloperWindowSize => Intl.message("Window Size",
      name: "labelDeveloperWindowSize",
      desc: "Title of the Developer settings section with buttons that resize "
          "the window");

  String get promptDeveloperMaximizeWindow => Intl.message("Maximize",
      name: "promptDeveloperMaximizeWindow",
      desc: "Button in Developer settings > Window Size that maximizes the "
          "window");

  String get labelDeveloperNotifications => Intl.message("Notifications",
      name: "labelDeveloperNotifications",
      desc: "Title of the Developer settings section with buttons that show "
          "test notifications");

  String get promptDeveloperMessageNotification =>
      Intl.message("Message Notification",
          name: "promptDeveloperMessageNotification",
          desc: "Button in Developer settings > Notifications that shows a "
              "test notification for a message");

  String get messageDeveloperTestMessage => Intl.message("Test Message!",
      name: "messageDeveloperTestMessage",
      desc: "Text of the test message notification sent from Developer "
          "settings > Notifications");

  String get promptDeveloperCallNotification =>
      Intl.message("Call Notification",
          name: "promptDeveloperCallNotification",
          desc: "Button in Developer settings > Notifications that shows a "
              "test notification for an incoming call");

  String get labelDeveloperTestIncomingCall => Intl.message("Incoming Call!",
      name: "labelDeveloperTestIncomingCall",
      desc: "Title of the test incoming call notification sent from Developer "
          "settings > Notifications");

  String get messageDeveloperTestCallNotification =>
      Intl.message("Test Call Notification",
          name: "messageDeveloperTestCallNotification",
          desc: "Text of the test incoming call notification sent from "
              "Developer settings > Notifications");

  String get labelDeveloperShortcuts => Intl.message("Shortcuts",
      name: "labelDeveloperShortcuts",
      desc: "Title of the Developer settings section (Android) about the "
          "launcher shortcuts the app creates for chats");

  String get promptDeveloperClearShortcuts => Intl.message("Clear Shortcuts",
      name: "promptDeveloperClearShortcuts",
      desc: "Button in Developer settings > Shortcuts (Android) that removes "
          "every launcher shortcut the app created");

  String get labelDeveloperBackgroundTasks => Intl.message("Background Tasks",
      name: "labelDeveloperBackgroundTasks",
      desc: "Title of the Developer settings section with buttons that start "
          "fake background tasks, to test how they are shown");

  String get promptDeveloperTaskWithProgress => Intl.message("With progress",
      name: "promptDeveloperTaskWithProgress",
      desc: "Button in Developer settings > Background Tasks: starts a fake "
          "task that shows how far along it is");

  String get promptDeveloperTaskIndeterminate => Intl.message("Indeterminate",
      name: "promptDeveloperTaskIndeterminate",
      desc: "Button in Developer settings > Background Tasks: starts a fake "
          "task with no progress to show");

  String get promptDeveloperAsyncTaskWithCrash => Intl.message(
      "Async task with crash",
      name: "promptDeveloperAsyncTaskWithCrash",
      desc: "Button in Developer settings > Background Tasks: starts a fake "
          "task that fails after a few seconds");

  String get labelDeveloperAsyncTask => Intl.message("Async task",
      name: "labelDeveloperAsyncTask",
      desc: "Name of the fake failing background task started from Developer "
          "settings, shown in the list of running tasks");

  String get labelDeveloperError => Intl.message("Error",
      name: "labelDeveloperError",
      desc: "Title of the Developer settings section with buttons that cause "
          "an error or write to the log, to test error handling");

  String get promptDeveloperThrowError => Intl.message("Throw an error",
      name: "promptDeveloperThrowError",
      desc: "Button in Developer settings > Error that makes the app fail on "
          "purpose");

  String get promptDeveloperPrintSomething => Intl.message("Print Something",
      name: "promptDeveloperPrintSomething",
      desc: "Button in Developer settings > Error that writes a line to the "
          "log");

  String get labelDeveloperDangerous => Intl.message("Dangerous",
      name: "labelDeveloperDangerous",
      desc: "Title of the Developer settings section with tools that run "
          "programs on the computer");

  String get promptDeveloperGetProcessList => Intl.message("Get Process List",
      name: "promptDeveloperGetProcessList",
      desc: "Button in Developer settings > Dangerous that lists the programs "
          "running on the computer");

  String get promptDeveloperExecuteShellCommand =>
      Intl.message("Execute Shell Command",
          name: "promptDeveloperExecuteShellCommand",
          desc: "Button in Developer settings > Dangerous, and the title of "
              "the dialog it opens, to run a command line on the computer");

  String get promptDeveloperDumpDatabases => Intl.message("Dump Databases",
      name: "promptDeveloperDumpDatabases",
      desc: "Title of a Developer settings section and its button: copies the "
          "app's database files into a folder you pick");

  @override
  Widget build(BuildContext context) {
    return Column(
        children: [
      performance(),
      benchmarks(),
      windowSize(),
      notificationTests(),
      rendering(),
      error(),
      if (PlatformUtils.isAndroid) shortcuts(),
      backgroundTasks(),
      dumpDatabases(),
      executeShellCommand(),
      tiamat.Panel(
        header: labelDeveloperOtherSettings,
        mode: TileType.surfaceContainerLow,
        child: Column(
          children: [
            if (!BuildConfig.MOBILE)
              BooleanPreferenceToggle(
                preference: preferences.disableTextCursorManagement,
                title: labelDeveloperDisableTextCursorManagement,
                description:
                    labelDeveloperDisableTextCursorManagementDescription,
              ),
            BooleanPreferenceToggle(
                preference: preferences.useSharedIsolateInBackgroundTasks,
                title: labelDeveloperUseSharedIsolateInBackground),
            DoublePreferenceSlider(
              preference: preferences.customOnscreenKeyboardViewOffset,
              title: labelDeveloperKeyboardOffset,
              min: 0.0,
              max: 1000,
              description: labelDeveloperKeyboardOffsetDescription,
            ),
          ],
        ),
      )
    ].map<Widget>((e) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 3, 0, 3),
        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: e),
      );
    }).toList());
  }

  Widget performance() {
    return ExpansionTile(
        title: tiamat.Text.labelEmphasised(labelDeveloperPerformance),
        initiallyExpanded: false,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        collapsedBackgroundColor:
            Theme.of(context).colorScheme.surfaceContainerLow,
        children: [
          CumulativeDiagnosticsWidget(
              diagnostics: Diagnostics.general,
              title: labelDeveloperDiagnosticsGeneral),
          CumulativeDiagnosticsWidget(
              diagnostics: Diagnostics.initialLoadDatabaseDiagnostics,
              title: labelDeveloperDiagnosticsInitialLoad),
          CumulativeDiagnosticsWidget(
              diagnostics: Diagnostics.postLoadDatabaseDiagnostics,
              title: labelDeveloperDiagnosticsPostLoad),
        ]);
  }

  Widget rendering() {
    return ExpansionTile(
        title: tiamat.Text.labelEmphasised(labelDeveloperRendering),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        collapsedBackgroundColor:
            Theme.of(context).colorScheme.surfaceContainerLow,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                      child: tiamat.Text.label(labelDeveloperShowRepaints)),
                  tiamat.Switch(
                    state: debugRepaintRainbowEnabled,
                    onChanged: (value) {
                      setState(() {
                        debugRepaintRainbowEnabled = value;
                      });
                    },
                  ),
                ],
              ),
              BooleanPreferenceToggle(
                preference: preferences.showPerformanceOverlay,
                title: labelDeveloperShowPerformanceOverlay,
                description: labelDeveloperRequiresRestart,
              ),
              // Both apply at once (AppLanguage listens to them); see
              // docs/localization.md, Layout.
              BooleanPreferenceToggle(
                preference: preferences.pseudoTranslations,
                title: labelDeveloperPseudoTranslations,
                description: labelDeveloperPseudoTranslationsDescription,
              ),
              BooleanPreferenceToggle(
                  preference: preferences.debugTranslations,
                  title: labelDeveloperShowTranslationKeys,
                  description: labelDeveloperShowTranslationKeysDescription),
            ]),
          )
        ]);
  }

  Widget benchmarks() {
    return ExpansionTile(
        title: tiamat.Text.labelEmphasised(labelDeveloperBenchmarks),
        initiallyExpanded: false,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        collapsedBackgroundColor:
            Theme.of(context).colorScheme.surfaceContainerLow,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              tiamat.Button(
                text: promptDeveloperTimelineViewer,
                onTap: () => NavigationUtils.navigateTo(
                    context, const BenchmarkTimelineViewer()),
              ),
              tiamat.Button(
                  text: promptDeveloperNotificationBadgesStressTest,
                  onTap: () async {
                    for (int i = 0; i < 10000; i++) {
                      int v = i % 9;
                      (NotificationManager.notifier as LinuxNotifier?)
                          ?.service
                          .update(count: v, countVisible: v != 0);

                      await Future.delayed(Duration(milliseconds: 100));

                      print("Notification Badge Stress Test: $i");
                    }
                  })
            ],
          ),
        ]);
  }

  Widget windowSize() {
    return ExpansionTile(
        title: tiamat.Text.labelEmphasised(labelDeveloperWindowSize),
        initiallyExpanded: false,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        collapsedBackgroundColor:
            Theme.of(context).colorScheme.surfaceContainerLow,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              tiamat.Button(
                text: promptDeveloperMaximizeWindow,
                onTap: () => windowManager.maximize(),
              ),
              tiamat.Button(
                text: "1280x720",
                onTap: () => windowManager.setSize(const Size(1280, 720)),
              ),
              tiamat.Button(
                text: "1280x800 (Steamdeck)",
                onTap: () => windowManager.setSize(const Size(1280, 800)),
              ),
              tiamat.Button(
                text: "1920x1080",
                onTap: () => windowManager.setSize(const Size(1920, 1080)),
              ),
              tiamat.Button(
                text: "2560x1440",
                onTap: () => windowManager.setSize(const Size(2560, 1440)),
              ),
              tiamat.Button(
                text: "3840x2160",
                onTap: () => windowManager.setSize(const Size(3840, 2160)),
              ),
              tiamat.Button(
                text: "1170x2532 (iPhone 12 Pro)",
                onTap: () => windowManager.setSize(const Size(1170, 2532)),
              ),
            ],
          ),
          const SizedBox(
            height: 5,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              tiamat.Button(
                text: "1:1",
                onTap: () => setAspectRatio(1),
              ),
              tiamat.Button(
                text: "16:9",
                onTap: () => setAspectRatio(16 / 9),
              ),
            ],
          )
        ]);
  }

  void setAspectRatio(double ratio) async {
    var size = await windowManager.getSize();
    var newWidth = size.height * ratio;
    await windowManager.setSize(Size(newWidth, size.height));
  }

  Widget notificationTests() {
    return ExpansionTile(
        title: tiamat.Text.labelEmphasised(labelDeveloperNotifications),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        collapsedBackgroundColor:
            Theme.of(context).colorScheme.surfaceContainerLow,
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            tiamat.Button(
              text: promptDeveloperMessageNotification,
              onTap: () async {
                var client = clientManager!.clients.first;
                var room = client.rooms.first;
                var user = client.self!;
                NotificationManager.notify(MessageNotificationContent(
                  senderName: user.displayName,
                  senderImage: user.avatar,
                  senderId: user.identifier,
                  roomName: room.displayName,
                  roomId: room.identifier,
                  roomImage: await room.getShortcutImage(),
                  content: messageDeveloperTestMessage,
                  clientId: client.identifier,
                  eventId: "fake_event_id",
                  isDirectMessage: true,
                ));
              },
            ),
            tiamat.Button(
              text: promptDeveloperCallNotification,
              onTap: () async {
                if (!BuildConfig.ANDROID) {
                  clientManager?.callManager.startRingtone();
                }

                var client = clientManager!.clients.first;
                var room = client.rooms.first;
                var user = client.self!;
                NotificationManager.notify(CallNotificationContent(
                  title: labelDeveloperTestIncomingCall,
                  senderImage: user.avatar,
                  senderId: user.identifier,
                  roomName: room.displayName,
                  roomId: room.identifier,
                  senderName: user.displayName,
                  senderImageId: "fake_call_avatar_id",
                  roomImage: await room.getShortcutImage(),
                  content: messageDeveloperTestCallNotification,
                  clientId: client.identifier,
                  callId: "fake_call_id",
                  isDirectMessage: true,
                ));
              },
            ),
          ])
        ]);
  }

  Widget shortcuts() {
    return ExpansionTile(
      title: tiamat.Text.labelEmphasised(labelDeveloperShortcuts),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      collapsedBackgroundColor:
          Theme.of(context).colorScheme.surfaceContainerLow,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          tiamat.Button(
            text: promptDeveloperClearShortcuts,
            onTap: () async {
              await shortcutsManager.clearAllShortcuts();
            },
          ),
        ])
      ],
    );
  }

  Widget backgroundTasks() {
    return ExpansionTile(
      title: tiamat.Text.labelEmphasised(labelDeveloperBackgroundTasks),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      collapsedBackgroundColor:
          Theme.of(context).colorScheme.surfaceContainerLow,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          tiamat.Button(
              text: promptDeveloperTaskWithProgress,
              onTap: () => backgroundTaskManager
                  .addTask(FakeBackgroundTaskWithProgress())),
          tiamat.Button(
              text: promptDeveloperTaskIndeterminate,
              onTap: () => backgroundTaskManager.addTask(FakeBackgroundTask())),
          tiamat.Button(
              text: promptDeveloperAsyncTaskWithCrash,
              onTap: () => backgroundTaskManager.addTask(AsyncTask(() async {
                    await Future.delayed(const Duration(seconds: 5));
                    throw Exception("This background task failed!");
                  }, labelDeveloperAsyncTask))),
        ])
      ],
    );
  }

  Widget error() {
    return ExpansionTile(
      title: tiamat.Text.labelEmphasised(labelDeveloperError),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      collapsedBackgroundColor:
          Theme.of(context).colorScheme.surfaceContainerLow,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          tiamat.Button(
              text: promptDeveloperThrowError,
              onTap: () {
                // This should also throw an error!
                String? empty;
                empty!.split(" ");
              }),
          tiamat.Button(
              text: promptDeveloperPrintSomething,
              onTap: () {
                print("Hello, world!");
              }),
        ])
      ],
    );
  }

  Widget executeShellCommand() {
    return ExpansionTile(
      title: tiamat.Text.labelEmphasised(labelDeveloperDangerous),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      collapsedBackgroundColor:
          Theme.of(context).colorScheme.surfaceContainerLow,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          tiamat.Button(
            text: promptDeveloperGetProcessList,
            onTap: () async {
              var list = await SystemProcessesUtils.getProcessList();
              AdaptiveDialog.show(
                context,
                builder: (context) {
                  return Codeblock(
                      text: list
                          .map((i) =>
                              "[${i.processId}] = ${i.command}  ${i.args}")
                          .join("\n"));
                },
              );
            },
          ),
          tiamat.Button(
              text: promptDeveloperExecuteShellCommand,
              onTap: () async {
                var text = await AdaptiveDialog.textPrompt(context,
                    title: promptDeveloperExecuteShellCommand);
                if (text != null) {
                  var command = text.split(" ");
                  var exe = command.first;
                  var args = command.sublist(1);

                  var process = await Process.start(exe, args);

                  AdaptiveDialog.show(context,
                      builder: (context) => ProcessOutputViewer(process));
                }
              }),
        ])
      ],
    );
  }

  Widget dumpDatabases() {
    return ExpansionTile(
      title: tiamat.Text.labelEmphasised(promptDeveloperDumpDatabases),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      collapsedBackgroundColor:
          Theme.of(context).colorScheme.surfaceContainerLow,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          tiamat.Button(
              text: promptDeveloperDumpDatabases,
              onTap: () async {
                var folder = await FilePicker.platform.getDirectoryPath();
                var dbDir = Directory(await AppConfig.getDatabasePath());

                var files = await dbDir
                    .list(recursive: true)
                    .where((event) => event is File)
                    .toList();

                for (var file in files) {
                  var name = p.basename(file.path);
                  var dirname = p.basename(p.dirname(file.path));

                  var newFolder = Directory(p.join(folder!, dirname));
                  if (!await newFolder.exists()) {
                    await newFolder.create(recursive: true);
                  }

                  var newFile = p.join(folder, dirname, name);
                  (file as File).copy(newFile);
                }
              }),
        ])
      ],
    );
  }
}

class ProcessOutputViewer extends StatefulWidget {
  const ProcessOutputViewer(this.process,
      {super.key, this.showStdErr = false, this.showStdOut = true});
  final Process process;
  final bool showStdErr;
  final bool showStdOut;

  @override
  State<ProcessOutputViewer> createState() => _ProcessOutputViewerState();
}

class _ProcessOutputViewerState extends State<ProcessOutputViewer> {
  String stdOut = "";
  String stdError = "";

  late List<StreamSubscription> subs;

  @override
  void initState() {
    super.initState();

    subs = [
      if (widget.showStdOut)
        widget.process.stdout.transform(utf8.decoder).listen(onStdout),
      if (widget.showStdErr)
        widget.process.stderr.transform(utf8.decoder).listen(onStderr),
    ];
  }

  @override
  void dispose() {
    for (var sub in subs) {
      sub.cancel();
    }

    widget.process.kill();
    super.dispose();
  }

  ScrollController stdoutScrollController = ScrollController();
  ScrollController stdErrScrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1000,
      child: Column(
        spacing: 4,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showStdOut)
            Expanded(
              child: tiamat.Panel(
                // Not translated: the names of a process's output streams.
                header: "stdout",
                child: SingleChildScrollView(
                  child: Scrollbar(
                    controller: stdoutScrollController,
                    child: SingleChildScrollView(
                      controller: stdoutScrollController,
                      scrollDirection: Axis.horizontal,
                      child: Codeblock(
                        text: stdOut,
                        clipboardText: stdOut,
                        language: "stdout",
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (widget.showStdErr)
            Expanded(
              child: tiamat.Panel(
                // Not translated: as stdout above.
                header: "stderr",
                child: SingleChildScrollView(
                  child: Scrollbar(
                    controller: stdErrScrollController,
                    child: SingleChildScrollView(
                      controller: stdErrScrollController,
                      scrollDirection: Axis.horizontal,
                      child: Codeblock(
                        text: stdError,
                        clipboardText: stdError,
                        language: "stderr",
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void onStderr(String event) {
    setState(() {
      stdError += event;
    });
  }

  void onStdout(String event) {
    setState(() {
      stdOut += event;
    });
  }
}
