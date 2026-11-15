//! The model the app ships, run through the C ABI the way the app runs it.

use std::time::{Duration, Instant};

use face_tracking::ffi::*;
use face_tracking::yunet::{Detect, Model};

const MODEL: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../rooster/assets/face_tracking/face_detection_yunet_2023mar_dynamic.onnx"
);

fn model_bytes() -> Vec<u8> {
    std::fs::read(MODEL).expect("the model the app ships")
}

#[test]
fn the_shipped_model_runs_at_both_sizes_and_sees_no_face_in_grey() {
    let model = Model::new(model_bytes()).unwrap();
    for (w, h) in [(320, 256), (128, 128)] {
        let mut detector = model.detector(w, h).unwrap();
        assert_eq!(detector.size(), (w, h));
        assert_eq!(detector.detect(&vec![128.0; 3 * w * h]), None);
    }
    assert!(model.detector(100, 100).is_err(), "not a multiple of 32");
    assert!(Model::new(b"not a model".to_vec()).is_err());
}

#[test]
fn the_c_abi_tracks_frames_handed_over() {
    assert_eq!(rooster_face_abi_version(), ABI_VERSION);
    let bytes = model_bytes();
    unsafe {
        assert_eq!(rooster_face_engine_start(std::ptr::null(), 0, 1), -1);
        assert_eq!(rooster_face_engine_start(b"nope".as_ptr(), 4, 1), -2);
        assert!(rooster_face_tracker_new(0).is_null(), "no engine yet");
        assert_eq!(rooster_face_engine_start(bytes.as_ptr(), bytes.len(), 1), 0);
        assert_eq!(rooster_face_engine_start(bytes.as_ptr(), bytes.len(), 1), 1);

        let tracker = rooster_face_tracker_new(1);
        assert!(!tracker.is_null());
        let mut out = FaceObservation::default();
        rooster_face_tracker_poll(tracker, &mut out);
        assert_eq!((out.seq, out.frames_delivered), (0, 0));

        // A grey 640x480 frame, Y rows padded to 672 bytes.
        let (w, h) = (640i32, 480i32);
        let y = vec![128u8; 672 * h as usize];
        let c = vec![128u8; (w / 2 * h / 2) as usize];
        rooster_face_frame(
            tracker,
            w,
            h,
            90,
            y.as_ptr(),
            672,
            c.as_ptr(),
            w / 2,
            c.as_ptr(),
            w / 2,
        );
        // Bad frames are dropped, not delivered.
        rooster_face_frame(
            tracker,
            0,
            h,
            0,
            y.as_ptr(),
            672,
            c.as_ptr(),
            w / 2,
            c.as_ptr(),
            w / 2,
        );
        rooster_face_frame(
            tracker,
            w,
            h,
            0,
            y.as_ptr(),
            10,
            c.as_ptr(),
            w / 2,
            c.as_ptr(),
            w / 2,
        );
        rooster_face_frame(
            std::ptr::null_mut(),
            w,
            h,
            0,
            y.as_ptr(),
            672,
            c.as_ptr(),
            w / 2,
            c.as_ptr(),
            w / 2,
        );

        let start = Instant::now();
        while out.seq == 0 {
            assert!(start.elapsed() < Duration::from_secs(10));
            std::thread::sleep(Duration::from_millis(5));
            rooster_face_tracker_poll(tracker, &mut out);
        }
        assert_eq!(out.seq, 1);
        assert_eq!(out.frames_delivered, 1);
        // Turned a quarter: upright it is 480 wide.
        assert_eq!(
            (out.width, out.height, out.found, out.frame_code),
            (480, 640, 0, -1)
        );

        rooster_face_tracker_free(tracker);
        rooster_face_tracker_poll(std::ptr::null_mut(), &mut out);
        assert_eq!(out.seq, 0);
        rooster_face_tracker_poll(tracker, std::ptr::null_mut());
    }
}
