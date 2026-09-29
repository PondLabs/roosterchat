import 'package:cockhouse/client/client.dart';
import 'package:cockhouse/client/components/component.dart';
import 'package:cockhouse/client/components/voip/voip_session.dart';

abstract class RTCScreenShareAnnotationComponent<T extends Client>
    implements Component<T> {
  Future<RTCScreenShareAnnotationSession> createSession(VoipSession session);

  Future<RTCScreenShareAnnotationSession> getOrCreateSession(
      VoipSession session);

  RTCScreenShareAnnotationSession? getExistingSession(VoipSession session);
}

abstract class RTCScreenShareAnnotationSession {
  void setCursorPosition(
      {required String streamId, required double x, required double y});
}
