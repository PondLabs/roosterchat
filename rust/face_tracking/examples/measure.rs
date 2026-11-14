//! The tracker alone, on every frame of the test videos, outside the app:
//! how well it places the plaque and how long a detection takes.
//!
//!     cargo run --release -p face_tracking --example measure -- MEDIA OUT.jsonl
//!
//! MEDIA holds `<video>.y4m` (tools/face_tracking/README.md says how to make
//! them); OUT.jsonl is a log `python3 -m tools.face_tracking.measure` reads.
//! The model is the one the app ships.

use std::io::{BufRead, BufReader, Read, Write};
use std::time::Instant;

use face_tracking::ffi::{FOLLOW_SIZE, SEARCH_SIZE};
use face_tracking::frame::Frame;
use face_tracking::tracker::{Detectors, Tracker};
use face_tracking::yunet::Model;

const VIDEOS: [&str; 5] = ["front", "glasses", "turn", "near_far", "leave"];
const MODEL: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../rooster/assets/face_tracking/face_detection_yunet_2023mar_dynamic.onnx"
);

/// The frames of a `.y4m` file (4:2:0 only).
fn frames(path: &str) -> (usize, usize, Vec<Frame>) {
    let mut file =
        BufReader::new(std::fs::File::open(path).unwrap_or_else(|e| panic!("{path}: {e}")));
    let mut header = String::new();
    file.read_line(&mut header).unwrap();
    let field = |tag: char| -> usize {
        header
            .split_whitespace()
            .find_map(|f| f.strip_prefix(tag))
            .and_then(|v| v.parse().ok())
            .unwrap()
    };
    let (w, h) = (field('W'), field('H'));
    let (cw, ch) = (w.div_ceil(2), h.div_ceil(2));
    let mut out = vec![];
    loop {
        let mut line = String::new();
        if file.read_line(&mut line).unwrap() == 0 {
            break;
        }
        let mut planes = [vec![0u8; w * h], vec![0u8; cw * ch], vec![0u8; cw * ch]];
        for plane in &mut planes {
            file.read_exact(plane).unwrap();
        }
        let [y, u, v] = planes;
        out.push(Frame::from_planes(w, h, 0, y, u, v));
    }
    (w, h, out)
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let (media, out) = (&args[1], &args[2]);
    let model = Model::new(std::fs::read(MODEL).unwrap()).unwrap();
    let mut detectors = Detectors::new(
        Box::new(model.detector(SEARCH_SIZE.0, SEARCH_SIZE.1).unwrap()),
        Box::new(model.detector(FOLLOW_SIZE, FOLLOW_SIZE).unwrap()),
    );
    let mut log = std::fs::File::create(out).unwrap();
    let (mut searches, mut follows) = (vec![], vec![]);
    for video in VIDEOS {
        let (w, h, frames) = frames(&format!("{media}/{video}.y4m"));
        let mut tracker = Tracker::new(true);
        let mut following = false;
        for frame in &frames {
            let start = Instant::now();
            let observation = tracker.step(frame, &mut detectors);
            let ms = start.elapsed().as_secs_f64() * 1e3;
            if following {
                follows.push(ms)
            } else {
                searches.push(ms)
            }
            following = observation.eyes.is_some();
            let face = match observation.eyes {
                None => "null".to_string(),
                Some(eyes) => {
                    // FaceAnchor.fromEyes.
                    let (ex, ey) = (eyes.left.0 - eyes.right.0, eyes.left.1 - eyes.right.1);
                    let middle = (
                        (eyes.right.0 + eyes.left.0) / 2.0,
                        (eyes.right.1 + eyes.left.1) / 2.0,
                    );
                    format!(
                        "{{\"x\":{},\"y\":{},\"width\":{},\"angle\":{}}}",
                        (middle.0 + 0.58 * ey) / w as f32,
                        (middle.1 - 0.58 * ex) / h as f32,
                        2.2 * eyes.distance() / w as f32,
                        ey.atan2(ex)
                    )
                }
            };
            let code = observation.frame_code.map_or(-1, i32::from);
            writeln!(log, "{{\"type\":\"anchor\",\"video\":\"{video}\",\"tile\":0,\"code\":{code},\"t\":{},\"face\":{face}}}", code as f64 * 1000.0 / 30.0).unwrap();
        }
    }
    let median = |v: &mut Vec<f64>| {
        v.sort_by(|a, b| a.total_cmp(b));
        if v.is_empty() {
            f64::NAN
        } else {
            v[v.len() / 2]
        }
    };
    println!(
        "search {}x{}: {} frames, median {:.2} ms; follow {s}x{s}: {} frames, median {:.2} ms (the whole step: cutting the input, the model, the eyes, the frame code)",
        SEARCH_SIZE.0,
        SEARCH_SIZE.1,
        searches.len(),
        median(&mut searches),
        follows.len(),
        median(&mut follows),
        s = FOLLOW_SIZE,
    );
}
