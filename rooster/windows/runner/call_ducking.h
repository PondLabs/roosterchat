#ifndef RUNNER_CALL_DUCKING_H_
#define RUNNER_CALL_DUCKING_H_

// ROOSTER: in a call, Windows turned every other sound down (by 80% with the
// default "When Windows detects communications activity" setting), because
// WebRTC plays and records on the communications device. A game or music
// under the call went nearly silent. This opts Rooster's audio sessions out
// of that, on every active speaker and microphone. Call it on the UI thread
// with COM up, at start and again when devices change; it is cheap to repeat.
void OptOutOfCallDucking();

#endif  // RUNNER_CALL_DUCKING_H_
