#!/usr/bin/env node
// Runs the face tracking demonstration in Chrome and keeps what it showed:
// a screenshot and the anchor log that measure.py reads.
//
//   NODE_PATH=<folder with playwright-core> node tools/face_tracking/capture_web.mjs \
//     --build rooster/build/web --media <test videos> --out <folder> \
//     [--seconds 10] [--query "tracker=replay&tiles=8"] [--port 8770]
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

const types = {
  ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".json": "application/json",
  ".wasm": "application/wasm", ".mp4": "video/mp4", ".png": "image/png", ".otf": "font/otf", ".ttf": "font/ttf",
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
try {
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  page.on("pageerror", (error) => console.error("page error:", error.message));
  await page.goto(`http://127.0.0.1:${port}/?${query}`);
  await page.waitForFunction("typeof window.faceTrackingLog === 'function'", null, { timeout: 60_000 });
  await page.waitForTimeout(seconds * 1000);
  mkdirSync(out, { recursive: true });
  await page.screenshot({ path: join(out, "demo.png") });
  const log = await page.evaluate("window.faceTrackingLog()");
  writeFileSync(join(out, "anchors.jsonl"), log);
  console.log(`${join(out, "demo.png")}\n${join(out, "anchors.jsonl")} (${log.split("\n").length - 1} lines)`);
} finally {
  await browser.close();
  server.close();
}
