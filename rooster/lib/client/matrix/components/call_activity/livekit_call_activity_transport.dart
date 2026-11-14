// The call-activity session's messages over LiveKit's data channel
// (reliable, topic CallActivityProtocol.topic), like the DJ booth's. The
// sender is the LiveKit participant the SFU delivered the packet from, not
// anything the packet says.
import 'dart:async';
import 'dart:typed_data';

import 'package:rooster/client/components/call_activity/call_activity_protocol.dart';
import 'package:rooster/client/components/call_activity/call_activity_transport.dart';
import 'package:rooster/debug/log.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

class LivekitCallActivityTransport implements CallActivityTransport {
  final lk.Room room;

  final StreamController<CallActivityIncoming> _incoming =
      StreamController.broadcast();
  final StreamController<String> _joined = StreamController.broadcast();
  final StreamController<String> _left = StreamController.broadcast();
  final StreamController<void> _reconnected = StreamController.broadcast();
  late final lk.EventsListener<lk.RoomEvent> _listener;

  LivekitCallActivityTransport(this.room) {
    _listener = room.createListener()
      ..on<lk.DataReceivedEvent>((e) {
        if (e.topic != CallActivityProtocol.topic) return;
        final sender = e.participant?.identity;
        if (sender == null) return;
        final message =
            CallActivityProtocol.decodePacket(Uint8List.fromList(e.data));
        if (message == null) return;
        _incoming.add(CallActivityIncoming(sender, message));
      })
      ..on<lk.ParticipantConnectedEvent>(
          (e) => _joined.add(e.participant.identity))
      ..on<lk.ParticipantDisconnectedEvent>(
          (e) => _left.add(e.participant.identity))
      ..on<lk.RoomReconnectedEvent>((_) => _reconnected.add(null));
  }

  @override
  String get selfIdentity => room.localParticipant?.identity ?? '';

  @override
  Future<void> send(Map<String, Object?> message, {List<String>? to}) async {
    final participant = room.localParticipant;
    if (participant == null) return;
    // LiveKit reads an empty destination list as everyone in the room: a
    // message addressed to people who have all left goes to nobody.
    if (to != null && to.isEmpty) return;
    try {
      await participant.publishData(
        CallActivityProtocol.encodePacket(message),
        reliable: true,
        topic: CallActivityProtocol.topic,
        destinationIdentities: to,
      );
    } catch (e, s) {
      Log.onError(e, s,
          content: 'call activity: could not send ${message['t']}');
      rethrow;
    }
  }

  @override
  Stream<CallActivityIncoming> get incoming => _incoming.stream;

  @override
  Stream<String> get participantJoined => _joined.stream;

  @override
  Stream<String> get participantLeft => _left.stream;

  @override
  Stream<void> get reconnected => _reconnected.stream;

  @override
  bool isPresent(String identity) =>
      identity == selfIdentity || room.remoteParticipants.containsKey(identity);

  @override
  Future<void> dispose() async {
    await _listener.dispose();
    await _incoming.close();
    await _joined.close();
    await _left.close();
    await _reconnected.close();
  }
}
