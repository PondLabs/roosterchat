//! Following one face in one video: search the whole frame, shrunk, until
//! a face is found; then look only at a square around it, which keeps a
//! small face big enough to place its eyes (docs/adr/0006-face-tracking.md,
//! "Find the face in the whole frame, then follow it with a square").

use crate::frame::{read_frame_code, Frame, Point};
use crate::yunet::{Detect, Eyes};

/// The square followed: this many eye distances wide...
pub const SQUARE_IN_EYE_DISTANCES: f32 = 5.0;
/// ...centred this many eye distances below the middle of the eyes.
pub const SQUARE_BELOW_EYES: f32 = 0.35;
/// A square narrower than this, in frame pixels, is widened: below it the
/// detector's input would be blown up from a handful of pixels.
pub const MIN_SQUARE: f32 = 48.0;

/// What one analysed frame gave.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Observation {
    /// The upright frame's size, in pixels: what `eyes` are in.
    pub width: usize,
    pub height: usize,
    /// None when the frame has no face.
    pub eyes: Option<Eyes>,
    /// The test videos' frame code of this frame, when asked for and found.
    pub frame_code: Option<u16>,
}

/// The two detectors a tracker uses: one for the whole frame, one for the
/// square. One pair serves every tracker, in turn.
pub struct Detectors {
    pub search: Box<dyn Detect>,
    pub follow: Box<dyn Detect>,
    search_input: Vec<f32>,
    follow_input: Vec<f32>,
}

impl Detectors {
    pub fn new(search: Box<dyn Detect>, follow: Box<dyn Detect>) -> Self {
        let (sw, sh) = search.size();
        let (fw, fh) = follow.size();
        Detectors {
            search,
            follow,
            search_input: vec![0.0; 3 * sw * sh],
            follow_input: vec![0.0; 3 * fw * fh],
        }
    }
}

/// The state of one tracker between frames: where the face was.
#[derive(Default)]
pub struct Tracker {
    last: Option<Eyes>,
    read_frame_code: bool,
}

impl Tracker {
    pub fn new(read_frame_code: bool) -> Self {
        Tracker {
            last: None,
            read_frame_code,
        }
    }

    /// Looks at one frame. A square that comes back empty means "no face"
    /// at once, and a search on the next frame.
    pub fn step(&mut self, frame: &Frame, detectors: &mut Detectors) -> Observation {
        let (width, height) = frame.upright_size();
        let eyes = match self.last {
            None => search(frame, detectors),
            Some(last) => follow(frame, last, detectors),
        };
        self.last = eyes;
        Observation {
            width,
            height,
            eyes,
            frame_code: if self.read_frame_code {
                read_frame_code(frame)
            } else {
                None
            },
        }
    }
}

/// The whole upright frame, shrunk to fit the input from its top left
/// corner; what the input has left over stays black.
fn search(frame: &Frame, detectors: &mut Detectors) -> Option<Eyes> {
    let (w, h) = frame.upright_size();
    let (iw, ih) = detectors.search.size();
    let scale = (w as f32 / iw as f32).max(h as f32 / ih as f32);
    frame.sample_bgr((0.0, 0.0), scale, iw, ih, &mut detectors.search_input);
    detectors
        .search
        .detect(&detectors.search_input)
        .map(|eyes| eyes.to_frame((0.0, 0.0), scale))
}

/// The square around where the eyes were.
pub fn square(last: Eyes) -> (Point, f32) {
    let (ex, ey) = (last.left.0 - last.right.0, last.left.1 - last.right.1);
    let side = (SQUARE_IN_EYE_DISTANCES * last.distance()).max(MIN_SQUARE);
    // Below the eyes is (-ey, ex) on screen, y growing downwards.
    let middle = (
        (last.right.0 + last.left.0) / 2.0,
        (last.right.1 + last.left.1) / 2.0,
    );
    let centre = (
        middle.0 - SQUARE_BELOW_EYES * ey,
        middle.1 + SQUARE_BELOW_EYES * ex,
    );
    ((centre.0 - side / 2.0, centre.1 - side / 2.0), side)
}

fn follow(frame: &Frame, last: Eyes, detectors: &mut Detectors) -> Option<Eyes> {
    let (origin, side) = square(last);
    let (iw, ih) = detectors.follow.size();
    let scale = side / iw.max(ih) as f32;
    frame.sample_bgr(origin, scale, iw, ih, &mut detectors.follow_input);
    detectors
        .follow
        .detect(&detectors.follow_input)
        .map(|eyes| eyes.to_frame(origin, scale))
}

#[cfg(test)]
pub mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    /// A detector that answers from a script, and remembers what it saw.
    pub struct Scripted {
        pub size: (usize, usize),
        pub answers: Arc<Mutex<Vec<Option<Eyes>>>>,
        pub calls: Arc<Mutex<usize>>,
    }

    impl Scripted {
        pub fn new(size: (usize, usize), answers: Vec<Option<Eyes>>) -> Self {
            Scripted {
                size,
                answers: Arc::new(Mutex::new(answers)),
                calls: Arc::new(Mutex::new(0)),
            }
        }
    }

    impl Detect for Scripted {
        fn size(&self) -> (usize, usize) {
            self.size
        }
        fn detect(&mut self, input: &[f32]) -> Option<Eyes> {
            assert_eq!(input.len(), 3 * self.size.0 * self.size.1);
            *self.calls.lock().unwrap() += 1;
            let mut answers = self.answers.lock().unwrap();
            if answers.is_empty() {
                None
            } else {
                answers.remove(0)
            }
        }
    }

    fn grey(w: usize, h: usize) -> Frame {
        let c = w.div_ceil(2) * h.div_ceil(2);
        Frame::from_planes(w, h, 0, vec![128; w * h], vec![128; c], vec![128; c])
    }

    #[test]
    fn searches_then_follows_then_searches_again_once_lost() {
        let eyes_in_input = Eyes {
            right: (100.0, 80.0),
            left: (140.0, 80.0),
        };
        let search = Scripted::new((320, 256), vec![Some(eyes_in_input), None]);
        let follow = Scripted::new(
            (128, 128),
            vec![
                Some(Eyes {
                    right: (44.0, 50.0),
                    left: (84.0, 50.0),
                }),
                None,
            ],
        );
        let (search_calls, follow_calls) = (search.calls.clone(), follow.calls.clone());
        let mut detectors = Detectors::new(Box::new(search), Box::new(follow));
        let mut tracker = Tracker::new(false);
        let frame = grey(640, 480);

        // Search: 640x480 into 320x256 is half size.
        let first = tracker.step(&frame, &mut detectors);
        assert_eq!(
            first.eyes,
            Some(Eyes {
                right: (200.0, 160.0),
                left: (280.0, 160.0)
            })
        );
        assert_eq!((first.width, first.height), (640, 480));

        // Follow: a square 5 eye distances (400 px) wide, 0.35 below the eyes.
        let second = tracker.step(&frame, &mut detectors);
        let ((x0, y0), side) = square(first.eyes.unwrap());
        assert_eq!(side, 400.0);
        assert_eq!((x0, y0), (40.0, 188.0 - 200.0));
        let k = 400.0 / 128.0;
        assert_eq!(
            second.eyes,
            Some(Eyes {
                right: (x0 + 44.0 * k, y0 + 50.0 * k),
                left: (x0 + 84.0 * k, y0 + 50.0 * k)
            })
        );

        // The square comes back empty: no face at once...
        assert_eq!(tracker.step(&frame, &mut detectors).eyes, None);
        // ...and the next frame is a search.
        assert_eq!(tracker.step(&frame, &mut detectors).eyes, None);
        assert_eq!(*search_calls.lock().unwrap(), 2);
        assert_eq!(*follow_calls.lock().unwrap(), 2);
    }

    #[test]
    fn a_tilted_face_gets_a_square_below_its_eyes() {
        // Eyes on a vertical line, the right one on top: the head lies on its
        // right side, and "below the eyes" is towards smaller x.
        let eyes = Eyes {
            right: (100.0, 100.0),
            left: (100.0, 120.0),
        };
        let ((x0, y0), side) = square(eyes);
        assert_eq!(side, MIN_SQUARE.max(100.0));
        let centre = (x0 + side / 2.0, y0 + side / 2.0);
        assert!((centre.0 - (100.0 - 0.35 * 20.0)).abs() < 1e-4);
        assert!((centre.1 - 110.0).abs() < 1e-4);
    }

    #[test]
    fn a_tiny_face_gets_the_smallest_square() {
        let (_, side) = square(Eyes {
            right: (10.0, 10.0),
            left: (12.0, 10.0),
        });
        assert_eq!(side, MIN_SQUARE);
    }

    #[test]
    fn reads_the_frame_code_only_when_asked() {
        let frame = crate::frame::tests_support::coded(640, 480, 42);
        let mut detectors = Detectors::new(
            Box::new(Scripted::new((320, 256), vec![])),
            Box::new(Scripted::new((128, 128), vec![])),
        );
        assert_eq!(
            Tracker::new(true).step(&frame, &mut detectors).frame_code,
            Some(42)
        );
        assert_eq!(
            Tracker::new(false).step(&frame, &mut detectors).frame_code,
            None
        );
    }
}
