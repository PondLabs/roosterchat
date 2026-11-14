// The face detector of the browser's face tracking: YuNet on ONNX Runtime
// Web (wasm, one thread), off the thread that draws the app
// (docs/adr/0006-face-tracking.md). Rooster starts it when the first face
// tracker starts; `face_tracker_web.dart` talks to it.
//
// It looks where it is told to, nothing more: the app picks the part of the
// frame (the whole frame or a square around the face) and reads the faces
// out of what YuNet answers. Frames are dropped as soon as they are read,
// and nothing leaves this worker but YuNet's numbers.
//
// A frame is "cut" as soon as the app has it: WebGL shrinks the part asked
// for and the pixels come back from the GPU, with those of the other cuts
// made meanwhile, without blocking this thread, while YuNet looks at an
// earlier one. "detect" then waits for them.
//
// ONNX Runtime's files sit next to this one, fetched at a pinned version by
// rooster/scripts/prepare-web.sh.
import * as ort from "./ort.wasm.bundle.min.mjs";

ort.env.wasm.numThreads = 1;
ort.env.wasm.proxy = false;
// Only the wasm's place: the JavaScript glue is the one bundled in.
ort.env.wasm.wasmPaths = { wasm: new URL("./ort-wasm-simd-threaded.wasm", import.meta.url).href };

const STRIDES = [8, 16, 32];
const CODE_CELLS = 20;
const CODE_ROW = 1 - 1 / 32;

// The model, loading or loaded: a detection asked for meanwhile waits.
let session = null;

// Cuts on their way back from the GPU, by id: a promise of their pixels.
const cuts = new Map();

// How long the last detections took, in milliseconds, for whoever measures
// (tools/face_tracking/capture_web.mjs reads it through the browser's
// developer tools protocol). A few numbers, never sent anywhere.
self.faceDetectionTimes = [];

// The GPU's part: one texture for the frame, a picture of the detector's
// input (plus a row for the frame code), drawn by a shader that leaves
// black whatever falls outside the frame.
const gpu = (() => {
  const gl = new OffscreenCanvas(1, 1).getContext("webgl2", { antialias: false, depth: false });
  if (!gl) return null;
  const shader = (type, source) => {
    const s = gl.createShader(type);
    gl.shaderSource(s, `#version 300 es\n${source}`);
    gl.compileShader(s);
    return s;
  };
  const program = gl.createProgram();
  // `src` is the part of the frame to show, in fractions of it: x, y, width,
  // height. The picture's top row is the part's top row.
  gl.attachShader(program, shader(gl.VERTEX_SHADER, `
    in vec2 corner;
    uniform vec4 src;
    out vec2 uv;
    void main() {
      uv = src.xy + vec2(corner.x * 0.5 + 0.5, 0.5 - corner.y * 0.5) * src.zw;
      gl_Position = vec4(corner, 0.0, 1.0);
    }`));
  gl.attachShader(program, shader(gl.FRAGMENT_SHADER, `
    precision mediump float;
    in vec2 uv;
    uniform sampler2D frame;
    out vec4 colour;
    void main() {
      bool outside = any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)));
      colour = outside ? vec4(0.0, 0.0, 0.0, 1.0) : texture(frame, uv);
    }`));
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) return null;
  gl.useProgram(program);
  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
  const corner = gl.getAttribLocation(program, "corner");
  gl.enableVertexAttribArray(corner);
  gl.vertexAttribPointer(corner, 2, gl.FLOAT, false, 0, 0);
  const texture = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, texture);
  for (const [key, value] of [
    [gl.TEXTURE_MIN_FILTER, gl.LINEAR],
    [gl.TEXTURE_MAG_FILTER, gl.LINEAR],
    [gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE],
    [gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE],
  ]) {
    gl.texParameteri(gl.TEXTURE_2D, key, value);
  }
  return { gl, src: gl.getUniformLocation(program, "src"), texture };
})();

// Cuts are drawn side by side in one picture, the atlas, and read back
// together: each read is a round trip to the GPU, whatever its size. While
// one read is on its way, the cuts that arrive wait, and go in the next.
const ATLAS = 1024;
const atlas = gpu && (() => {
  const { gl } = gpu;
  const texture = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texStorage2D(gl.TEXTURE_2D, 1, gl.RGBA8, ATLAS, ATLAS);
  const framebuffer = gl.createFramebuffer();
  gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
  gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
  return { framebuffer, drawn: [], waiting: [], reading: false, x: 0, y: 0, shelf: 0 };
})();

// Where the next cut of `width` x `rows` goes, from the top left; null when
// the atlas is full.
function place(width, rows) {
  if (atlas.x + width > ATLAS) {
    atlas.y += atlas.shelf;
    atlas.x = 0;
    atlas.shelf = 0;
  }
  if (atlas.y + rows > ATLAS) return null;
  const slot = { x: atlas.x, y: atlas.y };
  atlas.x += width;
  atlas.shelf = Math.max(atlas.shelf, rows);
  return slot;
}

// Draws the part of the frame asked for, shrunk to the input's size at its
// top left, and the frame code's row below it, in a slot of the atlas.
function draw(cut) {
  const { gl, src, texture } = gpu;
  const { frame, sx, sy, sw, sh, dw, dh, width, rows, strip } = cut;
  const slot = place(width, rows);
  if (!slot) return false;
  cut.slot = slot;
  gl.bindFramebuffer(gl.FRAMEBUFFER, atlas.framebuffer);
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, frame);
  const w = frame.width;
  const h = frame.height;
  frame.close();
  // The framebuffer's rows count from the bottom.
  const bottom = ATLAS - slot.y - rows;
  gl.enable(gl.SCISSOR_TEST);
  gl.scissor(slot.x, bottom, width, rows);
  gl.clearColor(0, 0, 0, 1);
  gl.clear(gl.COLOR_BUFFER_BIT);
  gl.disable(gl.SCISSOR_TEST);
  gl.viewport(slot.x, bottom + rows - dh, dw, dh);
  gl.uniform4f(src, sx / w, sy / h, sw / w, sh / h);
  gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  if (strip) {
    gl.viewport(slot.x, bottom, width, 1);
    gl.uniform4f(src, 0, CODE_ROW, 1, 0);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }
  atlas.drawn.push(cut);
  return true;
}

// Reads back every cut drawn since the last read, in one go, without
// blocking this thread: each cut gets its pixels, RGBA, top row first.
function read() {
  const { gl } = gpu;
  const cuts = atlas.drawn;
  atlas.drawn = [];
  atlas.reading = true;
  const band = atlas.y + atlas.shelf;
  const buffer = gl.createBuffer();
  gl.bindFramebuffer(gl.FRAMEBUFFER, atlas.framebuffer);
  gl.bindBuffer(gl.PIXEL_PACK_BUFFER, buffer);
  gl.bufferData(gl.PIXEL_PACK_BUFFER, ATLAS * band * 4, gl.STREAM_READ);
  gl.readPixels(0, ATLAS - band, ATLAS, band, gl.RGBA, gl.UNSIGNED_BYTE, 0);
  gl.bindBuffer(gl.PIXEL_PACK_BUFFER, null);
  const fence = gl.fenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0);
  gl.flush();
  const poll = () => {
    if (gl.clientWaitSync(fence, 0, 0) === gl.TIMEOUT_EXPIRED) {
      setTimeout(poll, 1);
      return;
    }
    gl.deleteSync(fence);
    const pixels = new Uint8Array(ATLAS * band * 4);
    gl.bindBuffer(gl.PIXEL_PACK_BUFFER, buffer);
    gl.getBufferSubData(gl.PIXEL_PACK_BUFFER, 0, pixels);
    gl.bindBuffer(gl.PIXEL_PACK_BUFFER, null);
    gl.deleteBuffer(buffer);
    for (const { slot, width, rows, done } of cuts) {
      const rgba = new Uint8Array(width * rows * 4);
      for (let y = 0; y < rows; y++) {
        // The band's first row is the atlas's lowest.
        const from = ((band - 1 - slot.y - y) * ATLAS + slot.x) * 4;
        rgba.set(pixels.subarray(from, from + width * 4), y * width * 4);
      }
      done(rgba);
    }
    atlas.reading = false;
    atlas.x = atlas.y = atlas.shelf = 0;
    const waiting = atlas.waiting;
    atlas.waiting = [];
    for (const cut of waiting) if (!draw(cut)) atlas.waiting.push(cut);
    if (atlas.drawn.length) read();
  };
  poll();
}

function cutOnGpu(cut) {
  if (atlas.reading) {
    atlas.waiting.push(cut);
    return;
  }
  draw(cut);
  read();
}

// Without WebGL 2: the same picture on a 2D canvas, read back at once.
const canvas = gpu ? null : new OffscreenCanvas(1, 1).getContext("2d", { willReadFrequently: true });
function cutOnCanvas({ frame, sx, sy, sw, sh, dw, dh, width, height, rows, strip, done }) {
  canvas.canvas.width = width;
  canvas.canvas.height = rows;
  canvas.fillStyle = "#000";
  canvas.fillRect(0, 0, width, rows);
  canvas.drawImage(frame, sx, sy, sw, sh, 0, 0, dw, dh);
  if (strip) canvas.drawImage(frame, 0, Math.floor(frame.height * CODE_ROW), frame.width, 1, 0, height, width, 1);
  frame.close();
  done(new Uint8Array(canvas.getImageData(0, 0, width, rows).data.buffer));
}

// Detections asked for while one runs wait their turn, in order.
let turn = Promise.resolve();

function detect({ id }) {
  const cut = cuts.get(id);
  cuts.delete(id);
  if (!cut) return Promise.reject(new Error(`no cut ${id}`));
  const result = turn.then(() => run(cut));
  turn = result.catch(() => {});
  return result;
}

async function run({ width, height, strip, pixels, started }) {
  const rgba = await pixels;
  let cells = null;
  if (strip) {
    cells = [];
    for (let i = 0; i < CODE_CELLS; i++) {
      const x = (height * width + Math.floor(((i + 0.5) / CODE_CELLS) * width)) * 4;
      cells.push((rgba[x] + rgba[x + 1] + rgba[x + 2]) / 3);
    }
  }
  // YuNet's input: planar BGR, 0 to 255, as it was trained.
  const n = width * height;
  const data = new Float32Array(3 * n);
  for (let i = 0; i < n; i++) {
    data[i] = rgba[i * 4 + 2];
    data[n + i] = rgba[i * 4 + 1];
    data[2 * n + i] = rgba[i * 4];
  }
  const prepared = performance.now();
  const outputs = await (await session).run({ input: new ort.Tensor("float32", data, [1, 3, height, width]) });
  const layers = STRIDES.map((stride) => ({
    stride,
    cls: outputs[`cls_${stride}`].data,
    obj: outputs[`obj_${stride}`].data,
    kps: outputs[`kps_${stride}`].data,
  }));
  const done = performance.now();
  const times = self.faceDetectionTimes;
  times.push({ width, height, model: done - prepared, sinceCut: done - started });
  if (times.length > 2000) times.splice(0, times.length - 2000);
  return { layers, cells };
}

self.onmessage = async ({ data }) => {
  const { id, type } = data;
  try {
    if (type === "load") {
      session = ort.InferenceSession.create(data.model, { executionProviders: ["wasm"] });
      await session;
      self.postMessage({ id });
    } else if (type === "cut") {
      const cut = { ...data, rows: data.strip ? data.height + 1 : data.height, started: performance.now() };
      cut.pixels = new Promise((done) => (cut.done = done));
      cuts.set(id, cut);
      (gpu ? cutOnGpu : cutOnCanvas)(cut);
    } else if (type === "discard") {
      cuts.delete(id);
    } else {
      self.postMessage({ id, ...(await detect(data)) });
    }
  } catch (error) {
    data.frame?.close?.();
    cuts.delete(id);
    self.postMessage({ id, error: String(error?.message ?? error) });
  }
};
