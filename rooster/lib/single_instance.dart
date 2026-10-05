import 'dart:io';

import 'dart:typed_data';
import 'package:rooster/config/app_config.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/debug/log.dart';
import 'package:dart_ipc/dart_ipc.dart';
import 'dart:convert';

import 'package:rooster/utils/window_management.dart';

class SingleInstance {
  /// Set by the Windows runner when another Rooster already holds its
  /// instance lock (windows/runner/main.cpp). Such a launch never runs as a
  /// second copy, whether or not it reaches the running one.
  static const secondaryFlag = '--rooster-secondary';

  /// How long a launch the runner knows is not the first keeps trying to
  /// reach the running one: it can be busy, or between two connections.
  static const secondaryRetryFor = Duration(seconds: 15);

  static Future<bool> tryConnectToMainInstance(List<String> args,
      {Duration retryFor = Duration.zero}) {
    return retry(() => _tryConnect(args), retryFor: retryFor);
  }

  /// Runs [attempt] until it succeeds or [retryFor] has passed, [every]
  /// apart. Once at least.
  static Future<bool> retry(Future<bool> Function() attempt,
      {required Duration retryFor,
      Duration every = const Duration(milliseconds: 500)}) async {
    final deadline = DateTime.now().add(retryFor);
    while (true) {
      if (await attempt()) return true;
      if (!DateTime.now().isBefore(deadline)) return false;
      await Future<void>.delayed(every);
    }
  }

  static Future<bool> _tryConnect(List<String> args) async {
    var path = await AppConfig.getSocketPath();

    print("Connecting to socket... $path");
    try {
      var socket = await connect(path).timeout(Duration(seconds: 3));
      print("Connected to socket: $socket");

      var msg = await socket.first;

      var data = jsonDecode(utf8.decode(msg));

      if (data["type"] == "hello") {
        socket.write(jsonEncode({"type": "new_instance_started"}));
      }

      return true;
    } catch (e, s) {
      Log.onError(e, s);

      if (e is SocketException) {
        if (PlatformUtils.isLinux) {
          if (e.osError?.errorCode == 111) {
            Log.i(
                "Socket exists but did not respond, the main instance either closed or crashed, so it should be fine to remove the socket");
            await File(path).delete();
            return false;
          }

          if (e.osError?.errorCode == 2) {
            Log.i("Socket does not exist!");

            return false;
          }
        }
      }

      return false;
    }
  }

  static void becomeMainInstance() async {
    var path = await AppConfig.getSocketPath();

    print("Connecting to socket... $path");

    var serverSocket = await bind(path);

    serverSocket.listen((socket) {
      handleSocket(socket, serverSocket);
    });
  }

  static void handleSocket(Socket socket, ServerSocket serverSocket) {
    socket.write(jsonEncode({"type": "hello"}));

    socket.listen((data) {
      try {
        handleSocketMessageReceived(data);
      } catch (e, s) {
        Log.onError(e, s);
      }
    }, onDone: () {
      print("Client Done");
    }, onError: (e) {
      print("Client Error: $e");
    });
  }

  static void handleSocketMessageReceived(Uint8List data) {
    var message = jsonDecode(utf8.decode(data));

    if (message["type"] == "new_instance_started") {
      Log.i("Bringing to front");
      // ROOSTER: show() alone left a minimized window minimized.
      WindowManagement.bringToFront();
    }
  }
}
