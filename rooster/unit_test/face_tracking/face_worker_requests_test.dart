import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/face_tracking/face_worker_requests.dart';

void main() {
  late List<(String, int)> posted;
  late FaceWorkerRequests<String> requests;
  late int loadId;

  setUp(() {
    posted = [];
    requests = FaceWorkerRequests<String>((type, id) => posted.add((type, id)));
    requests.load((id) => loadId = id);
  });

  test('a cut is detected once the model is loaded', () async {
    final cut = requests.nextCut()!;
    final reply = requests.detect(cut);
    await pumpEventQueue();
    expect(posted, isEmpty, reason: 'the model is still loading');

    requests.answer(loadId, 'loaded');
    await pumpEventQueue();
    expect(posted, [('detect', cut)]);

    requests.answer(cut, 'two eyes');
    expect(await reply, 'two eyes');
  });

  test('when the model does not load, every cut is let go in the worker',
      () async {
    final cuts = [requests.nextCut()!, requests.nextCut()!];
    final replies = [for (final cut in cuts) requests.detect(cut)];

    requests.answer(loadId, '', error: 'model.onnx: 404');

    for (final reply in replies) {
      await expectLater(reply, throwsStateError);
    }
    expect(posted, [for (final cut in cuts) ('discard', cut)]);

    final later = requests.nextCut()!;
    await expectLater(requests.detect(later), throwsStateError);
    expect(posted.last, ('discard', later));
  });

  test('a detection the worker could not do fails', () async {
    requests.answer(loadId, 'loaded');
    final cut = requests.nextCut()!;
    final reply = requests.detect(cut);
    await pumpEventQueue();

    requests.answer(cut, '', error: 'no cut');

    await expectLater(reply, throwsStateError);
  });

  test('once the worker is gone, nothing more is handed to it', () async {
    requests.answer(loadId, 'loaded');
    final cut = requests.nextCut()!;
    final reply = requests.detect(cut);
    await pumpEventQueue();

    requests.fail(StateError('the worker crashed'));

    await expectLater(reply, throwsStateError);
    expect(requests.nextCut(), isNull);
    requests.discard(cut);
    expect(posted, [('detect', cut)]);
  });
}
