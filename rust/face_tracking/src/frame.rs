//! A video frame as the WebRTC plugin hands it over (I420), and the two
//! things read from it: a detector's input, and the frame code of the test
//! videos.
//!
//! Everything here works in the *upright* frame: the frame turned by its
//! rotation, as it is shown. A phone's camera sends its frames sideways with
//! a rotation, and a face detector only finds faces the right way up.

/// A copy of one I420 frame, kept until the engine gets to it.
#[derive(Clone, Debug, Default)]
pub struct Frame {
    pub width: usize,
    pub height: usize,
    /// The degrees (0, 90, 180 or 270) the frame is to be turned clockwise to
    /// be shown upright, as WebRTC says.
    pub rotation: u32,
    y: Vec<u8>,
    u: Vec<u8>,
    v: Vec<u8>,
}

/// A point of the upright frame, in pixels.
pub type Point = (f32, f32);

impl Frame {
    /// Copies an I420 frame, reusing this frame's memory. Plane `p` has
    /// rows `stride_p` bytes apart; U and V are half the width and height,
    /// rounded up.
    ///
    /// # Safety
    /// Each plane pointer must be valid for `stride * rows` bytes, rows being
    /// the plane's height.
    #[allow(clippy::too_many_arguments)]
    pub unsafe fn copy_from_i420(
        &mut self,
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
        let (cw, ch) = (width.div_ceil(2), height.div_ceil(2));
        self.width = width;
        self.height = height;
        self.rotation = rotation % 360;
        copy_plane(&mut self.y, y, stride_y, width, height);
        copy_plane(&mut self.u, u, stride_u, cw, ch);
        copy_plane(&mut self.v, v, stride_v, cw, ch);
    }

    /// A frame from tightly packed planes, for tests.
    pub fn from_planes(
        width: usize,
        height: usize,
        rotation: u32,
        y: Vec<u8>,
        u: Vec<u8>,
        v: Vec<u8>,
    ) -> Self {
        let (cw, ch) = (width.div_ceil(2), height.div_ceil(2));
        assert_eq!(y.len(), width * height);
        assert_eq!(u.len(), cw * ch);
        assert_eq!(v.len(), cw * ch);
        Frame {
            width,
            height,
            rotation: rotation % 360,
            y,
            u,
            v,
        }
    }

    pub fn is_empty(&self) -> bool {
        self.width == 0 || self.height == 0
    }

    /// The size of the upright frame.
    pub fn upright_size(&self) -> (usize, usize) {
        if self.rotation % 180 == 90 {
            (self.height, self.width)
        } else {
            (self.width, self.height)
        }
    }

    /// The pixel of the frame as delivered under a pixel of the upright
    /// frame, or None outside it. The inverse of `FaceAnchor.uprightPoint`
    /// (rooster/lib/client/components/face_tracking/face_anchor.dart).
    fn delivered(&self, ux: f32, uy: f32) -> Option<(usize, usize)> {
        let (w, h) = (self.width as f32, self.height as f32);
        let (x, y) = match self.rotation {
            90 => (uy, h - ux),
            180 => (w - ux, h - uy),
            270 => (w - uy, ux),
            _ => (ux, uy),
        };
        if x < 0.0 || y < 0.0 || x >= w || y >= h {
            return None;
        }
        Some((x as usize, y as usize))
    }

    fn yuv(&self, x: usize, y: usize) -> (f32, f32, f32) {
        let c = (y / 2) * self.width.div_ceil(2) + x / 2;
        (
            self.y[y * self.width + x] as f32,
            self.u[c] as f32,
            self.v[c] as f32,
        )
    }

    /// The brightness (0 to 255) at a point of the upright frame, as an
    /// average of the 3x3 pixels around it.
    pub fn luma(&self, ux: f32, uy: f32) -> Option<f32> {
        let mut sum = 0.0;
        let mut count = 0.0;
        for dy in -1..=1 {
            for dx in -1..=1 {
                if let Some((x, y)) = self.delivered(ux + dx as f32, uy + dy as f32) {
                    sum += self.y[y * self.width + x] as f32;
                    count += 1.0;
                }
            }
        }
        (count > 0.0).then(|| sum / count)
    }

    /// Fills a detector's input: `out_w` x `out_h` pixels, as three planes
    /// of blue, green and red from 0 to 255 (YuNet's input). Input pixel
    /// (i, j) is the upright frame's square from `origin + (i, j) * scale`,
    /// `scale` pixels wide: averaged when it covers several pixels, sampled
    /// at its middle when less. Outside the frame is black.
    pub fn sample_bgr(
        &self,
        origin: Point,
        scale: f32,
        out_w: usize,
        out_h: usize,
        out: &mut [f32],
    ) {
        assert_eq!(out.len(), 3 * out_w * out_h);
        let plane = out_w * out_h;
        // Point samples per side of a square: enough to see every pixel it
        // covers, at most 4 (a 1280 wide camera into 320).
        let n = (scale.ceil() as usize).clamp(1, 4);
        let step = scale / n as f32;
        for j in 0..out_h {
            for i in 0..out_w {
                let left = origin.0 + i as f32 * scale;
                let top = origin.1 + j as f32 * scale;
                let (mut ys, mut us, mut vs, mut count) = (0.0, 0.0, 0.0, 0usize);
                for sy in 0..n {
                    for sx in 0..n {
                        let ux = left + (sx as f32 + 0.5) * step;
                        let uy = top + (sy as f32 + 0.5) * step;
                        if let Some((x, y)) = self.delivered(ux, uy) {
                            let (py, pu, pv) = self.yuv(x, y);
                            ys += py;
                            us += pu;
                            vs += pv;
                            count += 1;
                        }
                    }
                }
                let at = j * out_w + i;
                if count == 0 {
                    out[at] = 0.0;
                    out[plane + at] = 0.0;
                    out[2 * plane + at] = 0.0;
                    continue;
                }
                let c = count as f32;
                let (b, g, r) = bgr(ys / c, us / c, vs / c);
                out[at] = b;
                out[plane + at] = g;
                out[2 * plane + at] = r;
            }
        }
    }
}

/// BT.601, limited range: what WebRTC's cameras and decoders give.
fn bgr(y: f32, u: f32, v: f32) -> (f32, f32, f32) {
    let y = 1.164 * (y - 16.0);
    let (u, v) = (u - 128.0, v - 128.0);
    let r = y + 1.596 * v;
    let g = y - 0.392 * u - 0.813 * v;
    let b = y + 2.017 * u;
    (
        b.clamp(0.0, 255.0),
        g.clamp(0.0, 255.0),
        r.clamp(0.0, 255.0),
    )
}

unsafe fn copy_plane(to: &mut Vec<u8>, from: *const u8, stride: usize, width: usize, rows: usize) {
    to.resize(width * rows, 0);
    if from.is_null() || stride < width {
        to.fill(0);
        return;
    }
    for row in 0..rows {
        let src = std::slice::from_raw_parts(from.add(row * stride), width);
        to[row * width..(row + 1) * width].copy_from_slice(src);
    }
}

/// The frame code burned into the test videos (tools/face_tracking/frame_code.py):
/// a strip across the bottom sixteenth of the upright frame, 20 cells
/// read left to right: white, black, the 16 bits of the frame number (most
/// significant first, white is 1), an even parity bit, black. None when the
/// frame has none, or it does not hold together.
pub fn read_frame_code(frame: &Frame) -> Option<u16> {
    const CELLS: usize = 20;
    const CENTRE_Y: f32 = 1.0 - 1.0 / 32.0;
    const MIN_CONTRAST: f32 = 64.0;
    let (w, h) = frame.upright_size();
    let mut seen = [0f32; CELLS];
    for (i, value) in seen.iter_mut().enumerate() {
        *value = frame.luma(
            (i as f32 + 0.5) / CELLS as f32 * w as f32,
            CENTRE_Y * h as f32,
        )?;
    }
    if seen[0] - seen[1] < MIN_CONTRAST {
        return None;
    }
    let threshold = (seen[0] + seen[1]) / 2.0;
    let bits: Vec<u8> = seen.iter().map(|&v| u8::from(v > threshold)).collect();
    let code = bits[2..18]
        .iter()
        .fold(0u16, |code, &bit| code << 1 | bit as u16);
    let parity = bits[2..18].iter().map(|&b| b as u32).sum::<u32>() as u8 & 1;
    (bits[0] == 1 && bits[1] == 0 && bits[18] == parity && bits[19] == 0).then_some(code)
}

#[cfg(test)]
pub(crate) mod tests_support {
    use super::*;

    /// A grey frame with the frame code burned in, as frame_code.py draws it.
    pub fn coded(width: usize, height: usize, code: u16) -> Frame {
        let mut y = vec![128u8; width * height];
        let bits: Vec<u8> = (0..16).rev().map(|s| ((code >> s) & 1) as u8).collect();
        let parity = bits.iter().sum::<u8>() & 1;
        let mut cells = vec![1u8, 0];
        cells.extend(&bits);
        cells.extend([parity, 0]);
        let top = height - (height as f32 / 16.0).round() as usize;
        for (i, bit) in cells.iter().enumerate() {
            let left = (i as f32 * width as f32 / 20.0).round() as usize;
            let right = ((i + 1) as f32 * width as f32 / 20.0).round() as usize;
            for row in top..height {
                for x in left..right {
                    y[row * width + x] = if *bit == 1 { 235 } else { 16 };
                }
            }
        }
        let c = width.div_ceil(2) * height.div_ceil(2);
        Frame::from_planes(width, height, 0, y, vec![128; c], vec![128; c])
    }
}

#[cfg(test)]
mod tests {
    use super::tests_support::coded;
    use super::*;

    /// The same frame as a camera turned by `rotation` would deliver it.
    fn turned(frame: &Frame, rotation: u32) -> Frame {
        let (w, h) = (frame.width, frame.height);
        let (dw, dh) = if rotation % 180 == 90 { (h, w) } else { (w, h) };
        let mut out = Frame::from_planes(
            dw,
            dh,
            rotation,
            vec![0; dw * dh],
            vec![128; dw.div_ceil(2) * dh.div_ceil(2)],
            vec![128; dw.div_ceil(2) * dh.div_ceil(2)],
        );
        for y in 0..dh {
            for x in 0..dw {
                // Where this delivered pixel lands upright.
                let (ux, uy) = match rotation {
                    90 => (dh - 1 - y, x),
                    180 => (dw - 1 - x, dh - 1 - y),
                    270 => (y, dw - 1 - x),
                    _ => (x, y),
                };
                out.y[y * dw + x] = frame.y[uy * w + ux];
            }
        }
        out
    }

    #[test]
    fn reads_the_frame_code_of_the_test_videos() {
        for code in [0u16, 1, 57, 1145, 0xffff] {
            assert_eq!(
                read_frame_code(&coded(640, 480, code)),
                Some(code),
                "code {code}"
            );
        }
        assert_eq!(read_frame_code(&coded(1280, 720, 300)), Some(300));
    }

    #[test]
    fn reads_the_frame_code_of_a_turned_frame_upright() {
        let upright = coded(640, 480, 777);
        for rotation in [90, 180, 270] {
            assert_eq!(
                read_frame_code(&turned(&upright, rotation)),
                Some(777),
                "rotation {rotation}"
            );
        }
    }

    #[test]
    fn a_frame_without_a_code_has_none() {
        let c = 320 * 240;
        let grey = Frame::from_planes(
            640,
            480,
            0,
            vec![128; 640 * 480],
            vec![128; c],
            vec![128; c],
        );
        assert_eq!(read_frame_code(&grey), None);
        let mut broken = coded(640, 480, 5);
        // Flip one bit: the parity no longer holds.
        let x = (2.5 / 20.0 * 640.0) as usize;
        for row in 452..480 {
            broken.y[row * 640 + x - 3..row * 640 + x + 3].fill(235);
        }
        assert_eq!(read_frame_code(&broken), None);
    }

    #[test]
    fn converts_limited_range_colours() {
        let (b, g, r) = bgr(235.0, 128.0, 128.0);
        assert!((b - 255.0).abs() < 1.0 && (g - 255.0).abs() < 1.0 && (r - 255.0).abs() < 1.0);
        let (b, g, r) = bgr(16.0, 128.0, 128.0);
        assert!(b < 1.0 && g < 1.0 && r < 1.0);
        // BT.601 red: Y 81, U 90, V 240.
        let (b, g, r) = bgr(81.0, 90.0, 240.0);
        assert!(r > 250.0 && g < 5.0 && b < 5.0, "{b} {g} {r}");
    }

    #[test]
    fn samples_the_upright_frame_and_leaves_the_outside_black() {
        // Left half dark, right half bright.
        let (w, h) = (8, 4);
        let y: Vec<u8> = (0..w * h)
            .map(|i| if i % w < w / 2 { 16 } else { 235 })
            .collect();
        let frame = Frame::from_planes(w, h, 0, y, vec![128; 4 * 2], vec![128; 4 * 2]);
        let mut out = vec![0f32; 3 * 4 * 3];
        // Every input pixel averages 2x2 frame pixels; the last row is below the frame.
        frame.sample_bgr((0.0, 0.0), 2.0, 4, 3, &mut out);
        let blue = &out[..12];
        assert_eq!(
            &blue[0..4]
                .iter()
                .map(|v| v.round() as i32)
                .collect::<Vec<_>>(),
            &[0, 0, 255, 255]
        );
        assert!(blue[8..12].iter().all(|&v| v == 0.0));

        // Turned a quarter: what was the top of the picture is on its right.
        let turned = turned(
            &Frame::from_planes(
                w,
                h,
                0,
                (0..w * h)
                    .map(|i| if i / w == 0 { 235 } else { 16 })
                    .collect(),
                vec![128; 8],
                vec![128; 8],
            ),
            90,
        );
        let mut out = vec![0f32; 3 * 8 * 4];
        turned.sample_bgr((0.0, 0.0), 1.0, 8, 4, &mut out);
        assert!(
            out[0] > 250.0 && out[8] < 5.0,
            "the upright top row is bright, the next dark"
        );
    }

    #[test]
    fn copies_strided_planes() {
        let (w, h) = (4usize, 2usize);
        // Rows of 6 bytes, of which 4 are pixels.
        let y: Vec<u8> = vec![1, 2, 3, 4, 99, 99, 5, 6, 7, 8, 99, 99];
        let u: Vec<u8> = vec![10, 11, 99, 99];
        let v: Vec<u8> = vec![20, 21, 99, 99];
        let mut frame = Frame::default();
        unsafe { frame.copy_from_i420(w, h, 450, y.as_ptr(), 6, u.as_ptr(), 4, v.as_ptr(), 4) };
        assert_eq!(frame.y, vec![1, 2, 3, 4, 5, 6, 7, 8]);
        assert_eq!(frame.u, vec![10, 11]);
        assert_eq!(frame.v, vec![20, 21]);
        assert_eq!(frame.rotation, 90);
        assert_eq!(frame.upright_size(), (2, 4));
    }
}
