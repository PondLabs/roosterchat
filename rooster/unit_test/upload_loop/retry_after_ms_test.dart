@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/ui/molecules/timeline_events/events/pending_attachment_status.dart';

import 'loop_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AttachmentSends.instance.clear());

  group('a 429 with retry_after_ms', () {
    Future<
        (
          matrix.Client,
          AttachmentSend,
          Future<String?>,
          LoopTransport,
          ManualSendClock
        )> throttled(String name, int retryAfterMs) async {
      final transport = LoopTransport();
      transport.onUpload = (body, attempt) async {
        if (attempt == 1) {
          return json(429, {
            'errcode': 'M_LIMIT_EXCEEDED',
            'error': 'Too many requests',
            'retry_after_ms': retryAfterMs,
          });
        }
        return transport.accept(body);
      };
      final clock = ManualSendClock();
      final (mx, room) = await loopClient(name, transport, clock);
      final (send, sending) = startSend(room, withThumbnail: false);
      return (mx, send, sending, transport, clock);
    }

    test('of 3 s: the upload waits for it and goes through', () async {
      final (mx, send, sending, transport, clock) =
          await throttled('loop_429_short', 3000);
      await until(() => clock.waiting);
      expect(clock.waits, [const Duration(seconds: 3)]);
      clock.advance(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(transport.uploads, hasLength(1), reason: 'still waiting at 2 s');
      clock.advance(const Duration(seconds: 1));
      expect(await sending, isNotNull);
      print('429 of 3 s: ${transport.byRoute}, waits ${clock.waits}');
      expect(transport.uploads, hasLength(2));
      expect(transport.events, hasLength(1));
      expect(send.stage, AttachmentSendStage.sent);
      await mx.dispose(closeDatabase: true);
    });

    test(
        'of 10 min: the message fails at once, says when it can be retried, '
        'and is not sent again by itself', () async {
      final (mx, send, sending, transport, clock) =
          await throttled('loop_429_long', 10 * 60 * 1000);
      expect(await sending, isNull);
      expect(clock.waits, isEmpty);
      expect(send.stage, AttachmentSendStage.failed);
      expect(send.upload.serverWaitsUntil, DateTime(2026, 11, 16, 14, 10));
      final label = PendingAttachmentStatus.describe(send).label;
      expect(label,
          PendingAttachmentStatus.labelPendingFileServerAskedToWait('14:10'));
      clock.advance(const Duration(minutes: 20));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      print('429 of 10 min: ${transport.byRoute}; shown: "$label"');
      expect(transport.uploads, hasLength(1));
      expect(transport.events, isEmpty);
      await mx.dispose(closeDatabase: true);
    });
  });
}
