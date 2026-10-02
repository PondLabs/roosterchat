import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/voip/voip_session.dart';

enum CallType { voice, video }

abstract class VoipComponent<T extends Client> implements Component<T> {
  Stream<VoipSession> get onSessionStarted;
  Stream<VoipSession> get onSessionEnded;

  List<VoipSession> getSessionsInRoom(String roomId);

  Future<void> startCall(String roomId, CallType type, {String? userId});

  bool canCallRoom(String roomId);
}
