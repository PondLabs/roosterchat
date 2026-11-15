#!/usr/bin/env node
// Runs the face tracking demonstration in Chrome and keeps what it showed:
// a screenshot, the anchor log that measure.py reads, every request the
// page made (requests.txt) and how long the browser's detector took
// (detections.json).
//
//   NODE_PATH=<folder with playwright-core> node tools/face_tracking/capture_web.mjs \
//     --build rooster/build/web --media <test videos> --out <folder> \
//     [--seconds 10] [--query "tracker=replay&tiles=8"] [--port 8770] [--record]
//
// `--record` also films the page (a .webm in the folder). With
// `start=manual` in the query the videos play for a few seconds before the
// tracking starts, and requests.txt marks the moment: what was downloaded
// before tracking, and what after.
//
// The build is `flutter build web --release -t lib/face_tracking_demo_main.dart`.
// It and the test videos are served from 127.0.0.1 only, and the server
// stops with the script.
import { createServer } from "node:http";
import { createReadStream, existsSync, mkdirSync, statSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { extname, join, normalize, resolve } from "node:path";

const { chromium } = createRequire(import.meta.url)("playwright-core");

const args = process.argv.slice(2);
const opt = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : fallback;
};
const build = resolve(opt("--build", "rooster/build/web"));
const media = resolve(opt("--media"));
const out = resolve(opt("--out"));
const port = Number(opt("--port", "8770"));
const seconds = Number(opt("--seconds", "10"));
const query = opt("--query", "tracker=replay");
const record = args.includes("--record");

const types = {
  ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".json": "application/json",
  ".wasm": "application/wasm", ".mp4": "video/mp4", ".onnx": "application/octet-stream", ".png": "image/png", ".otf": "font/otf", ".ttf": "font/ttf",
};
const server = createServer((request, response) => {
  const path = normalize(decodeURIComponent(new URL(request.url, "http://x").pathname));
  let file = path.startsWith("/media/") ? join(media, path.slice(7)) : join(build, path);
  if (existsSync(file) && statSync(file).isDirectory()) file = join(file, "index.html");
  if (!existsSync(file)) {
    response.writeHead(404).end();
    return;
  }
  response.writeHead(200, { "content-type": types[extname(file)] ?? "application/octet-stream" });
  createReadStream(file).pipe(response);
});
await new Promise((ready) => server.listen(port, "127.0.0.1", ready));

const browser = await chromium.launch({
  channel: "chrome",
  headless: true,
  // The GPU the app would have in a real Chrome, and videos that play
  // without a click.
  args: ["--headless=new", "--enable-gpu", "--ignore-gpu-blocklist", "--use-angle=gl", "--autoplay-policy=no-user-gesture-required"],
});
mkdirSync(out, { recursive: true });
const viewport = { width: 1280, height: 720 };
const context = await browser.newContext({ viewport, ...(record ? { recordVideo: { dir: out, size: viewport } } : {}) });
const opened = Date.now();
const requests = [];
const note = (line) => requests.push(`${String(Date.now() - opened).padStart(6)} ms  ${line}`);
try {
  const page = await context.newPage();
  page.on("pageerror", (error) => console.error("page error:", error.message));
  page.on("request", (request) => note(request.url()));
  await page.goto(`http://127.0.0.1:${port}/?${query}`);
  await page.waitForFunction("typeof window.faceTrackingLog === 'function'", null, { timeout: 60_000 });
  if (query.includes("start=manual")) {
    await page.waitForFunction("typeof window.faceTrackingStart === 'function'", null, { timeout: 60_000 });
    await page.waitForTimeout(3000);
    note("--- tracking starts ---");
    await page.evaluate("window.faceTrackingStart()");
  }
  await page.waitForTimeout(seconds * 1000);
  await page.screenshot({ path: join(out, "demo.png") });
  const log = await page.evaluate("window.faceTrackingLog()");
  writeFileSync(join(out, "anchors.jsonl"), log);
  writeFileSync(join(out, "requests.txt"), requests.join("\n") + "\n");
  const elsewhere = requests.filter((line) => /https?:\/\//.test(line) && !line.includes(`//127.0.0.1:${port}/`));
  // The face tracking worker keeps the time of its last detections.
  const times = [];
  for (const worker of page.workers()) {
    times.push(...((await worker.evaluate("self.faceDetectionTimes ?? []").catch(() => [])) ?? []));
  }
  writeFileSync(join(out, "detections.json"), JSON.stringify(times));
  // Per input size: how long YuNet took, and how long from the frame
  // being handed over to its detection's end (the cut on the GPU, the
  // wait for its turn, YuNet).
  const bySize = {};
  for (const time of times) (bySize[`${time.width}x${time.height}`] ??= []).push(time);
  const median = (all, key) => {
    const sorted = all.map((time) => time[key]).sort((a, b) => a - b);
    return sorted[sorted.length >> 1].toFixed(1);
  };
  for (const [size, all] of Object.entries(bySize)) {
    console.log(`detections at ${size}: ${all.length}, YuNet ${median(all, "model")} ms, ` +
      `from the frame handed over ${median(all, "sinceCut")} ms (medians)`);
  }
  console.log(`${join(out, "demo.png")}\n${join(out, "anchors.jsonl")} (${log.split("\n").length - 1} lines)`);
  console.log(`${join(out, "requests.txt")} (${requests.length} requests, ${elsewhere.length} not to this server)`);
} finally {
  await context.close();
  await browser.close();
  server.close();
}
