#ifndef RUNNER_INSTANCE_LOCK_H_
#define RUNNER_INSTANCE_LOCK_H_

// ROOSTER: one Rooster at a time. The named pipe single_instance.dart checks
// has gaps (between two connections, and while the running one is too busy
// to answer), and a launch that fell into one ran as a second full copy: two
// syncs of the same account, two toasts per message. Windows makes this
// check atomically. A launch that is not the first only hands over to the
// running one and quits (main.dart).
//
// The lock is held by a Rooster that is running, not by one that is closing.
// Closing takes a while after the window has gone (leaving a call, closing
// the accounts, the engine), and while the lock lasted until the process
// ended, a Rooster opened in that time was a second copy: it showed nothing,
// handed the click to the one closing or tried to for 15 s, and quit. Now
// the one closing gives the lock up, and the next one takes it, shows its
// loading square and waits for the other to go before it starts.

// Takes the lock. False when another Rooster holds it.
bool TakeInstanceLock();

// This Rooster is closing: gives the lock up, and says so until the process
// ends. Nothing happens in a Rooster that never held it.
void LeaveInstanceLock();

// Waits for a Rooster that gave the lock up to end, handling this thread's
// window messages meanwhile so the loading square stays alive. False when
// the loading square was closed while waiting, which is a quit.
bool WaitForLeavingInstance();

#endif  // RUNNER_INSTANCE_LOCK_H_
