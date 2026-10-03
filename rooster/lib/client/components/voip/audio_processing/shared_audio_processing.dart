// Desktop WebRTC runs one audio processing module (APM) for the whole
// process: WebRTC's echo canceller, gain control and noise suppressor, for
// every microphone capture. Each audio sender writes its source's options
// into it when it starts sending (WebRtcVoiceSendChannel::SetAudioSend →
// SetOptions → ApplyAudioProcessingOptions, in libwebrtc) and again every
// time its connection negotiates (SetSenderParameters), in the order of the
// connection's media sections, and the last one to write wins.
//
// Screen-share system audio and the DJ booth's music are custom sources.
// They do not go through the APM, so their options only matter for what
// they write over the microphone's. Created with everything off, as they
// used to be, they switched echo cancellation, gain control and noise
// suppression off for the microphone: echo for everyone listening to
// someone on loudspeakers. So the vendored flutter-webrtc creates them with
// the microphone's echo cancellation and gain control (on), and the music
// with the microphone's noise suppression too (`noiseSuppression` of
// roosterCreateMusicTrack): whenever they write, nothing changes.
//
// What is left is noise suppression where it differs: screen audio always
// writes it off, and the music what the microphone had when the booth
// opened. restoreMicrophoneProcessing writes the microphone's options back
// after a custom source has written its own, by turning the microphone's
// capture track off and on: re-enabling a track makes its sender apply its
// options again. It holds until the connection negotiates again. That is a libwebrtc internal, not an API. If an update changes it,
// integration_test/voice_dsp/native_noise_test.dart ("a custom audio source
// leaves the microphone's processing alone") fails; see
// docs/voice-audio-processing.md, "Known gaps".
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/debug/log.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

/// Whether this platform's WebRTC shares one audio processing module that
/// custom audio sources overwrite (the vendored flutter-webrtc's C++ on
/// Linux and Windows). The browser processes each track on its own.
bool get customAudioSourcesOverrideMicrophone =>
    PlatformUtils.isLinux || PlatformUtils.isWindows;

/// Puts [microphone]'s processing options back on the shared audio
/// processing module, after a custom audio source wrote its own there. A
/// disabled (muted) microphone is left as it is: enabling it writes them.
/// Returns whether it did anything.
bool restoreMicrophoneProcessing(rtc.MediaStreamTrack microphone,
    {bool? overridden}) {
  if (!(overridden ?? customAudioSourcesOverrideMicrophone)) return false;
  if (!microphone.enabled) return false;
  // Two platform calls, handled in order. The microphone is disabled for
  // the time between them, about one 10 ms block.
  microphone.enabled = false;
  microphone.enabled = true;
  Log.i("Voice: put the microphone's echo cancellation, gain control and "
      "noise suppression back after a custom audio source");
  return true;
}
