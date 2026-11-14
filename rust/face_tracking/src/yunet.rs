//! YuNet (OpenCV Zoo's `face_detection_yunet_2023mar`, MIT) on tract.
//!
//! The model finds faces at three scales (strides 8, 16 and 32), each cell
//! of each scale saying how likely a face is there and where its five
//! points are: the eyes, the nose and the corners of the mouth. Only the
//! eyes are kept: they are all `FaceAnchor.fromEyes` needs.

use std::io::Cursor;
use std::sync::Arc;

use tract_onnx::prelude::*;

use crate::frame::Point;

type Plan = SimplePlan<TypedFact, Box<dyn TypedOp>, Graph<TypedFact, Box<dyn TypedOp>>>;

/// Below this a cell is not a face. OpenCV's own default is 0.9; 0.6 keeps
/// the smaller and turned faces of the test videos and finds nothing on
/// their empty frames (docs/adr/0006-face-tracking.md).
pub const MIN_SCORE: f32 = 0.6;

/// The two eyes of a face, in pixels of whatever the input was cut from.
/// `right` is the person's right eye: the one on the left of the picture.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Eyes {
    pub right: Point,
    pub left: Point,
}

impl Eyes {
    pub fn distance(&self) -> f32 {
        let (dx, dy) = (self.left.0 - self.right.0, self.left.1 - self.right.1);
        (dx * dx + dy * dy).sqrt()
    }

    /// These eyes, from input pixels to frame pixels: the input's pixel
    /// (i, j) is the frame's `origin + (i, j) * scale`.
    pub fn to_frame(self, origin: Point, scale: f32) -> Eyes {
        let map = |p: Point| (origin.0 + p.0 * scale, origin.1 + p.1 * scale);
        Eyes {
            right: map(self.right),
            left: map(self.left),
        }
    }
}

/// Something that finds the eyes of the most likely face in an input of a
/// fixed size: YuNet, or a stand-in in a test.
pub trait Detect: Send {
    /// The input's width and height, in pixels.
    fn size(&self) -> (usize, usize);

    /// `input` is three planes, blue, green and red, from 0 to 255.
    fn detect(&mut self, input: &[f32]) -> Option<Eyes>;
}

/// The model file, parsed once and shared by every input size.
#[derive(Clone)]
pub struct Model {
    bytes: Arc<Vec<u8>>,
}

impl Model {
    /// Checks the model file by building a small detector from it.
    pub fn new(bytes: Vec<u8>) -> TractResult<Model> {
        let model = Model {
            bytes: Arc::new(bytes),
        };
        model.detector(32, 32)?;
        Ok(model)
    }

    /// A detector for inputs of `width` x `height` pixels, both multiples
    /// of 32.
    pub fn detector(&self, width: usize, height: usize) -> TractResult<YuNet> {
        if width == 0 || height == 0 || width % 32 != 0 || height % 32 != 0 {
            return Err(TractError::msg(format!(
                "YuNet takes multiples of 32, not {width}x{height}"
            )));
        }
        let plan = tract_onnx::onnx()
            .model_for_read(&mut Cursor::new(self.bytes.as_slice()))?
            .with_input_fact(0, f32::fact([1, 3, height, width]).into())?
            .into_optimized()?
            .into_runnable()?;
        let outputs = plan.model().output_outlets()?.len();
        if outputs != 12 {
            return Err(TractError::msg(format!(
                "YuNet has 12 outputs, this model {outputs}"
            )));
        }
        Ok(YuNet {
            plan,
            width,
            height,
        })
    }
}

pub struct YuNet {
    plan: Plan,
    width: usize,
    height: usize,
}

impl Detect for YuNet {
    fn size(&self) -> (usize, usize) {
        (self.width, self.height)
    }

    fn detect(&mut self, input: &[f32]) -> Option<Eyes> {
        let tensor = Tensor::from_shape(&[1, 3, self.height, self.width], input).ok()?;
        let out = self.plan.run(tvec!(tensor.into())).ok()?;
        // Outputs, in the model's order: cls_8, cls_16, cls_32, obj_8, obj_16,
        // obj_32, bbox_8, bbox_16, bbox_32, kps_8, kps_16, kps_32.
        let mut scales = Vec::with_capacity(3);
        for (i, stride) in [8usize, 16, 32].into_iter().enumerate() {
            scales.push(Scale {
                stride,
                columns: self.width / stride,
                cls: out[i].as_slice::<f32>().ok()?,
                obj: out[3 + i].as_slice::<f32>().ok()?,
                kps: out[9 + i].as_slice::<f32>().ok()?,
            });
        }
        best_eyes(&scales)
    }
}

/// One scale of YuNet's output, one value (or ten for the points) per cell.
pub struct Scale<'a> {
    pub stride: usize,
    pub columns: usize,
    pub cls: &'a [f32],
    pub obj: &'a [f32],
    pub kps: &'a [f32],
}

/// The eyes of the cell most likely to be a face, if one is likely enough.
/// A cell's score is the geometric mean of its class and object scores; its
/// points are offsets from the cell's corner, in strides.
pub fn best_eyes(scales: &[Scale]) -> Option<Eyes> {
    let mut best: Option<(f32, Eyes)> = None;
    for scale in scales {
        for (cell, (c, o)) in scale.cls.iter().zip(scale.obj).enumerate() {
            let score = (c.clamp(0.0, 1.0) * o.clamp(0.0, 1.0)).sqrt();
            if score < MIN_SCORE || best.as_ref().is_some_and(|b| b.0 >= score) {
                continue;
            }
            let Some(k) = scale.kps.get(cell * 10..cell * 10 + 4) else {
                continue;
            };
            let (column, row) = ((cell % scale.columns) as f32, (cell / scale.columns) as f32);
            let s = scale.stride as f32;
            best = Some((
                score,
                Eyes {
                    right: ((k[0] + column) * s, (k[1] + row) * s),
                    left: ((k[2] + column) * s, (k[3] + row) * s),
                },
            ));
        }
    }
    best.map(|b| b.1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keeps_the_most_likely_face_and_places_its_eyes() {
        // A 2x2 grid at stride 8: cell 3 (column 1, row 1) is the best face.
        let cls = [0.1, 0.7, 0.0, 0.95];
        let obj = [0.1, 0.7, 0.0, 0.9];
        let mut kps = [0f32; 40];
        kps[30..34].copy_from_slice(&[0.25, 0.5, 0.75, 0.5]);
        kps[10..14].copy_from_slice(&[9.0, 9.0, 9.0, 9.0]);
        let scale = Scale {
            stride: 8,
            columns: 2,
            cls: &cls,
            obj: &obj,
            kps: &kps,
        };
        let eyes = best_eyes(&[scale]).unwrap();
        assert_eq!(eyes.right, (10.0, 12.0));
        assert_eq!(eyes.left, (14.0, 12.0));
    }

    #[test]
    fn finds_nothing_below_the_score() {
        let cls = [0.5, 0.59];
        let obj = [0.5, 0.59];
        let kps = [0f32; 20];
        assert_eq!(
            best_eyes(&[Scale {
                stride: 8,
                columns: 2,
                cls: &cls,
                obj: &obj,
                kps: &kps
            }]),
            None
        );
    }

    #[test]
    fn eyes_go_back_to_the_frame() {
        let eyes = Eyes {
            right: (10.0, 20.0),
            left: (30.0, 20.0),
        };
        let moved = eyes.to_frame((100.0, 50.0), 2.0);
        assert_eq!(
            moved,
            Eyes {
                right: (120.0, 90.0),
                left: (160.0, 90.0)
            }
        );
        assert_eq!(moved.distance(), 40.0);
    }
}
