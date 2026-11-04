// The seam between a session and the call's transport: the shape the DJ
// booth's seam has, so the session logic runs against LiveKit, an in-memory
// fake, or anything else that moves envelopes between participants.
// Adapters for real calls live in the Matrix layer
// (../matrix/components/call_activity/). Identity note: like the DJ booth,
// receivers MUST prefer the authenticated sender a transport stamps on
// [CallActivityIncoming.sender] over anything the message body says.

import 'dart:async';

/// One message that arrived, from an authenticated [sender] (the LiveKit
/// participant identity the transport received the packet from, never
/// anything the packet body says).
class CallActivityIncoming {
  final String sender;
  final Map<String, Object?> message;

  const CallActivityIncoming(this.sender, this.message);
}

/// The transport of a call's activity session.
abstract class CallActivityTransport {
  /// Our own LiveKit identity.
  String get selfIdentity;

  /// Sends [message] to everyone in the call, or to [to] alone
  /// (identities, as in [CallActivityIncoming.sender]).
  Future<void> send(Map<String, Object?> message, {List<String>? to});

  /// Messages from the others.
  Stream<CallActivityIncoming> get incoming;

  /// A participant joined the call. A reconnecting client fires this too;
  /// sessions treat reconnecting participants as arriving: they ask for the
  /// current state with a hello.
  Stream<String> get participantJoined;

  /// A participant left the call (or LiveKit lost them).
  Stream<String> get participantLeft;

  /// Our own connection was cut and came back. Messages sent meanwhile may
  /// be lost, and everyone is reported as having left and returned.
  Stream<void> get reconnected;

  /// Whether [identity] is in the call right now.
  bool isPresent(String identity);

  Future<void> dispose();
}

/// One call in memory: every transport joined to it hears the others, one
/// microtask later, exactly as if the packets went over the wire. For unit
/// and integration tests (the soundboard's in-memory transport precedent);
/// production paths use the LiveKit adapter.
class InMemoryActivityCall {
  final Map<String, InMemoryActivityTransport> _members = {};
  final List<(String, Map<String, Object?>, List<String>)> _sent = [];

  /// Every message sent on this call, in order: (from, message, to).
  List<(String, Map<String, Object?>, List<String>)> get log =>
      List.unmodifiable(_sent);

  int get memberCount => _members.length;

  CallActivityTransport join(String identity) {
    final InMemoryActivityTransport transport =
        InMemoryActivityTransport._(this, identity);
    _members[identity] = transport;
    for (final member in _members.values) {
      if (identical(member, transport)) continue;
      member._joined.add(identity);
    }
    return transport;
  }

  void leave(String identity) {
    if (_members.remove(identity) == null) return;
    for (final member in _members.values) {
      member._left.add(identity);
    }
  }

  bool isPresent(String identity) => _members.containsKey(identity);

  Future<void> close() async {
    for (final member in List.of(_members.values)) {
      await member.dispose();
    }
  }
}

class InMemoryActivityTransport implements CallActivityTransport {
  final InMemoryActivityCall _call;
  @override
  final String selfIdentity;
  bool _disposed = false;

  final _incoming = StreamController<CallActivityIncoming>.broadcast();
  final _joined = StreamController<String>.broadcast();
  final _left = StreamController<String>.broadcast();
  final _reconnected = StreamController<void>.broadcast();

  InMemoryActivityTransport._(this._call, this.selfIdentity);

  @override
  Future<void> send(Map<String, Object?> message, {List<String>? to}) async {
    if (_disposed) return;
    _call._sent.add((selfIdentity, message, to ?? const []));
    await Future<void>.delayed(Duration.zero);
    for (final member in _call._members.values.toList()) {
      if (identical(member, this)) continue;
      if (to != null && !to.contains(member.selfIdentity)) continue;
      if (member._disposed || member._incoming.isClosed) continue;
      member._incoming.add(CallActivityIncoming(selfIdentity, message));
    }
  }

  @override
  Stream<CallActivityIncoming> get incoming => _incoming.stream;

  @override
  Stream<String> get participantJoined => _joined.stream;

  @override
  Stream<String> get participantLeft => _left.stream;

  Stream<void> get reconnected => _reconnected.stream;

  /// Reports our own connection as torn down and back, like LiveKit does.
  void reconnect() {
    _reconnected.add(null);
  }

  @override
  bool isPresent(String identity) => !_disposed && _call.isPresent(identity);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _call._members.remove(selfIdentity);
    await _incoming.close();
    await _joined.close();
    await _left.close();
    await _reconnected.close();
  }
}
