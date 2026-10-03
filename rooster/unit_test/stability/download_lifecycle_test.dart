import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/cache/file_provider.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/download_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Picker extends FilePicker {
  _Picker(this.pending);
  final Future<void> pending;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    await pending;
    return null;
  }
}

class _File implements FileProvider {
  _File(this.pending);
  final Future<void> pending;
  final progress = StreamController<DownloadProgress>.broadcast();

  @override
  Stream<DownloadProgress> get onProgressChanged => progress.stream;

  @override
  Future<Uint8List?> getFileData() async {
    await pending;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });
  tearDown(() => FilePicker.platform = _Picker(Future.value()));

  testWidgets(
      'closing a running download closes its stream and ignores completion',
      (tester) async {
    final pending = Completer<void>();
    FilePicker.platform = _Picker(pending.future);
    final file = _File(pending.future);
    final task = DownloadFileTask(file, 'photo');
    unawaited(task.run());
    await tester.pump();
    expect(file.progress.hasListener, isTrue);
    task.dispose();
    expect(file.progress.hasListener, isFalse);
    expect(task.controller.isClosed, isTrue);
    pending.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(task.shouldRemoveTask, isFalse);
    expect(tester.takeException(), isNull);
    unawaited(file.progress.close());
  });

  testWidgets('closing a finished download cancels its removal timer',
      (tester) async {
    FilePicker.platform = _Picker(Future.value());
    final file = _File(Future.value());
    final task = DownloadFileTask(file, 'photo');
    unawaited(task.run());
    await tester.pump();
    task.dispose();
    task.dispose();
    await tester.pump(const Duration(seconds: 6));
    expect(task.controller.isClosed, isTrue);
    expect(task.shouldRemoveTask, isFalse);
    expect(tester.takeException(), isNull);
    unawaited(file.progress.close());
  });
}
