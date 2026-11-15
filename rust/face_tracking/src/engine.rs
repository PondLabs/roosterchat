//! One engine serves every tracker of the app, in turn: each tracker keeps
//! only the newest frame it was handed, and is looked at no more often than
//! `min_interval`. Eight videos cost eight times one detection, not eight
//! engines (docs/adr/0006-face-tracking.md).
//!
//! Frames come in on the WebRTC plugin's threads ([`Slot::deliver_i420`]),
//! which only copy the frame and never wait on a detection. The engine's
//! threads take the frames, detect, and leave the result for Dart to read
//! ([`Slot::latest`]).

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex, MutexGuard, PoisonError};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use crate::frame::Frame;
use crate::tracker::{Detectors, Observation, Tracker};

/// How often a tracker is looked at, at most: fifteen times a second.
pub const MIN_INTERVAL: Duration = Duration::from_micros(66_667);

struct Shared {
    sched: Mutex<Sched>,
    wake: Condvar,
    min_interval: Duration,
}

#[derive(Default)]
struct Sched {
    stop: bool,
    entries: Vec<Entry>,
    next_id: u64,
}

struct Entry {
    slot: Arc<Slot>,
    busy: bool,
    last_start: Option<Instant>,
}

struct Pending {
    frame: Frame,
    fresh: bool,
}

/// One tracker's place in the engine.
pub struct Slot {
    id: u64,
    shared: Arc<Shared>,
    pending: Mutex<Pending>,
    tracker: Mutex<Tracker>,
    result: Mutex<(u64, Option<Observation>)>,
    delivered: AtomicU64,
}

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    // A panic in a detection must not stop every other tracker.
    mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

impl Slot {
    /// Keeps a copy of an I420 frame as this tracker's newest.
    ///
    /// # Safety
    /// As [`Frame::copy_from_i420`].
    #[allow(clippy::too_many_arguments)]
    pub unsafe fn deliver_i420(
        &self,
        width: usize,
        height: usize,
        rotation: u32,
        y: *const u8,
        stride_y: usize,
        u: *const u8,
        stride_u: usize,
        v: *const u8,
        stride_v: usize,
    ) {
        {
            let mut pending = lock(&self.pending);
            pending.frame.copy_from_i420(
                width, height, rotation, y, stride_y, u, stride_u, v, stride_v,
            );
            pending.fresh = !pending.frame.is_empty();
        }
        self.delivered();
    }

    /// Keeps a copy of `frame` as this tracker's newest.
    pub fn deliver(&self, frame: &Frame) {
        {
            let mut pending = lock(&self.pending);
            pending.frame.clone_from(frame);
            pending.fresh = !frame.is_empty();
        }
        self.delivered();
    }

    fn delivered(&self) {
        self.delivered.fetch_add(1, Ordering::Relaxed);
        // A worker checks for fresh frames holding the schedule's lock and
        // waits by releasing it: taking it here before waking them means
        // none of them is between the two.
        drop(lock(&self.shared.sched));
        self.shared.wake.notify_all();
    }

    /// How many observations this tracker has made, and the newest.
    pub fn latest(&self) -> (u64, Option<Observation>) {
        *lock(&self.result)
    }

    /// How many frames were handed to this tracker.
    pub fn frames_delivered(&self) -> u64 {
        self.delivered.load(Ordering::Relaxed)
    }
}

pub struct Engine {
    shared: Arc<Shared>,
    workers: Vec<JoinHandle<()>>,
}

impl Engine {
    /// Starts `workers` threads, each with its own detectors from `make`.
    pub fn new(
        workers: usize,
        min_interval: Duration,
        make: impl Fn() -> Detectors + Send + Sync + 'static,
    ) -> Engine {
        let shared = Arc::new(Shared {
            sched: Mutex::default(),
            wake: Condvar::new(),
            min_interval,
        });
        let make = Arc::new(make);
        let workers = (0..workers.max(1))
            .map(|i| {
                let shared = shared.clone();
                let make = make.clone();
                std::thread::Builder::new()
                    .name(format!("face-tracking-{i}"))
                    .spawn(move || work(&shared, make()))
                    .expect("a face tracking thread")
            })
            .collect();
        Engine { shared, workers }
    }

    /// A new tracker, looked at from its first frame on.
    pub fn add(&self, read_frame_code: bool) -> Arc<Slot> {
        let mut sched = lock(&self.shared.sched);
        sched.next_id += 1;
        let slot = Arc::new(Slot {
            id: sched.next_id,
            shared: self.shared.clone(),
            pending: Mutex::new(Pending {
                frame: Frame::default(),
                fresh: false,
            }),
            tracker: Mutex::new(Tracker::new(read_frame_code)),
            result: Mutex::new((0, None)),
            delivered: AtomicU64::new(0),
        });
        sched.entries.push(Entry {
            slot: slot.clone(),
            busy: false,
            last_start: None,
        });
        slot
    }

    /// Stops looking at a tracker. A detection already running on it ends
    /// on its own; its result is not read by anyone.
    pub fn remove(&self, slot: &Slot) {
        lock(&self.shared.sched)
            .entries
            .retain(|entry| entry.slot.id != slot.id);
    }

    /// How many trackers there are.
    pub fn trackers(&self) -> usize {
        lock(&self.shared.sched).entries.len()
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        lock(&self.shared.sched).stop = true;
        self.shared.wake.notify_all();
        for worker in self.workers.drain(..) {
            let _ = worker.join();
        }
    }
}

fn work(shared: &Shared, mut detectors: Detectors) {
    let mut frame = Frame::default();
    loop {
        let Some(slot) = next(shared, &mut frame) else {
            return;
        };
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            lock(&slot.tracker).step(&frame, &mut detectors)
        }));
        if let Ok(observation) = result {
            let mut latest = lock(&slot.result);
            *latest = (latest.0 + 1, Some(observation));
        }
        let mut sched = lock(&shared.sched);
        if let Some(entry) = sched
            .entries
            .iter_mut()
            .find(|entry| entry.slot.id == slot.id)
        {
            entry.busy = false;
        }
    }
}

/// Waits for the tracker due first, takes its newest frame into `frame`, and
/// returns it. None once the engine stops.
fn next(shared: &Shared, frame: &mut Frame) -> Option<Arc<Slot>> {
    let mut sched = lock(&shared.sched);
    loop {
        if sched.stop {
            return None;
        }
        let now = Instant::now();
        let mut pick: Option<usize> = None;
        let mut wait: Option<Duration> = None;
        for (i, entry) in sched.entries.iter().enumerate() {
            if entry.busy || !lock(&entry.slot.pending).fresh {
                continue;
            }
            let due = entry.last_start.map_or(now, |t| t + shared.min_interval);
            if due > now {
                wait = Some(wait.map_or(due - now, |w: Duration| w.min(due - now)));
                continue;
            }
            // The one that waited longest goes first.
            let older = match pick {
                None => true,
                Some(p) => match (entry.last_start, sched.entries[p].last_start) {
                    (None, Some(_)) => true,
                    (Some(a), Some(b)) => a < b,
                    _ => false,
                },
            };
            if older {
                pick = Some(i);
            }
        }
        if let Some(i) = pick {
            let entry = &mut sched.entries[i];
            entry.busy = true;
            entry.last_start = Some(now);
            let mut pending = lock(&entry.slot.pending);
            std::mem::swap(&mut pending.frame, frame);
            pending.fresh = false;
            return Some(entry.slot.clone());
        }
        sched = match wait {
            Some(wait) => {
                shared
                    .wake
                    .wait_timeout(sched, wait)
                    .unwrap_or_else(PoisonError::into_inner)
                    .0
            }
            None => shared
                .wake
                .wait(sched)
                .unwrap_or_else(PoisonError::into_inner),
        };
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tracker::tests::Scripted;
    use crate::yunet::{Detect, Eyes};

    /// A detector that takes `cost` and always finds the same eyes.
    struct Slow(Duration);

    impl Detect for Slow {
        fn size(&self) -> (usize, usize) {
            (32, 32)
        }
        fn detect(&mut self, _: &[f32]) -> Option<Eyes> {
            std::thread::sleep(self.0);
            Some(Eyes {
                right: (10.0, 10.0),
                left: (20.0, 10.0),
            })
        }
    }

    fn grey(w: usize, h: usize, value: u8) -> Frame {
        let c = w.div_ceil(2) * h.div_ceil(2);
        Frame::from_planes(w, h, 0, vec![value; w * h], vec![128; c], vec![128; c])
    }

    fn wait_for(slot: &Slot, seq: u64) -> Observation {
        let start = Instant::now();
        loop {
            let (s, observation) = slot.latest();
            if s >= seq {
                return observation.unwrap();
            }
            assert!(
                start.elapsed() < Duration::from_secs(5),
                "no observation {seq}"
            );
            std::thread::sleep(Duration::from_millis(1));
        }
    }

    #[test]
    fn a_frame_handed_over_is_observed() {
        let engine = Engine::new(1, Duration::ZERO, || {
            Detectors::new(
                Box::new(Scripted::new((32, 32), vec![])),
                Box::new(Scripted::new((32, 32), vec![])),
            )
        });
        let slot = engine.add(false);
        assert_eq!(slot.latest(), (0, None));
        slot.deliver(&grey(64, 48, 128));
        let observation = wait_for(&slot, 1);
        assert_eq!(
            (observation.width, observation.height, observation.eyes),
            (64, 48, None)
        );
        assert_eq!(slot.frames_delivered(), 1);
    }

    #[test]
    fn only_the_newest_frame_is_looked_at() {
        // A slow detector: while it works, three frames come; only the last is analysed.
        let engine = Engine::new(1, Duration::ZERO, || {
            Detectors::new(
                Box::new(Slow(Duration::from_millis(50))),
                Box::new(Slow(Duration::from_millis(50))),
            )
        });
        let slot = engine.add(true);
        slot.deliver(&crate::frame::tests_support::coded(64, 48, 1));
        std::thread::sleep(Duration::from_millis(10));
        for code in 2..=4 {
            slot.deliver(&crate::frame::tests_support::coded(64, 48, code));
        }
        assert_eq!(wait_for(&slot, 1).frame_code, Some(1));
        assert_eq!(wait_for(&slot, 2).frame_code, Some(4));
        std::thread::sleep(Duration::from_millis(120));
        assert_eq!(slot.latest().0, 2, "nothing new to look at");
        assert_eq!(slot.frames_delivered(), 4);
    }

    #[test]
    fn each_tracker_is_looked_at_at_most_at_its_rate() {
        let engine = Engine::new(2, Duration::from_millis(100), || {
            Detectors::new(
                Box::new(Slow(Duration::ZERO)),
                Box::new(Slow(Duration::ZERO)),
            )
        });
        let slot = engine.add(false);
        let start = Instant::now();
        // 30 frames a second for half a second.
        while start.elapsed() < Duration::from_millis(500) {
            slot.deliver(&grey(64, 48, 128));
            std::thread::sleep(Duration::from_millis(33));
        }
        let seen = slot.latest().0;
        assert!(
            (5..=6).contains(&seen),
            "{seen} observations in 0.5 s at 10 a second"
        );
    }

    #[test]
    fn trackers_take_turns() {
        // One thread, 10 ms a detection, eight trackers fed at 30 a second:
        // each one gets about an eighth of 100 detections a second.
        let engine = Engine::new(1, MIN_INTERVAL, || {
            Detectors::new(
                Box::new(Slow(Duration::from_millis(10))),
                Box::new(Slow(Duration::from_millis(10))),
            )
        });
        let slots: Vec<_> = (0..8).map(|_| engine.add(false)).collect();
        let start = Instant::now();
        while start.elapsed() < Duration::from_secs(1) {
            for slot in &slots {
                slot.deliver(&grey(64, 48, 128));
            }
            std::thread::sleep(Duration::from_millis(33));
        }
        let counts: Vec<u64> = slots.iter().map(|slot| slot.latest().0).collect();
        let (min, max) = (*counts.iter().min().unwrap(), *counts.iter().max().unwrap());
        assert!(min >= 8 && max - min <= 3, "{counts:?}");
    }

    #[test]
    fn a_removed_tracker_is_left_alone() {
        let engine = Engine::new(1, Duration::ZERO, || {
            Detectors::new(
                Box::new(Slow(Duration::ZERO)),
                Box::new(Slow(Duration::ZERO)),
            )
        });
        let slot = engine.add(false);
        let other = engine.add(false);
        assert_eq!(engine.trackers(), 2);
        engine.remove(&slot);
        assert_eq!(engine.trackers(), 1);
        slot.deliver(&grey(64, 48, 128));
        other.deliver(&grey(64, 48, 128));
        wait_for(&other, 1);
        std::thread::sleep(Duration::from_millis(20));
        assert_eq!(slot.latest().0, 0);
    }
}
