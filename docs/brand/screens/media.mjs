// The made-up crew's pictures, drawn in Chrome: an emoji animal on a palette
// colour for each person and house, the screenshot Jonas posts in #general,
// and Kart Night as a looping video for his screen share (kart.html, frame
// by frame, encoded with ffmpeg). Usage: node media.mjs (after setup.sh has
// installed Playwright).
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";

const WORK = process.env.ROOSTER_SHOTS ?? "/tmp/rooster-shots";
const HERE = path.dirname(new URL(import.meta.url).pathname);
const { chromium } = createRequire(`${WORK}/node/`)("playwright-core");

export const PICTURES = [
  ["maya", "🦊", "#E8382A"], ["theo", "🐸", "#5E8F4E"], ["priya", "🦉", "#F89B17"],
  ["jonas", "🐙", "#3F4F6E"], ["bia", "🐼", "#8D8178"], ["kenji", "🐯", "#C9452B"],
  ["lou", "🐧", "#2E3B33"], ["rafa", "🦝", "#B5653A"],
  ["space-coop", "🏡", "#E8382A"], ["space-games", "🎮", "#3F4F6E"], ["space-books", "📚", "#5E8F4E"],
  ["space-lan", "🕹️", "#F89B17"], ["space-synth", "🎛️", "#2E3B33"],
];

const out = `${WORK}/media`;
const frames = `${WORK}/kart-frames`;
fs.mkdirSync(out, { recursive: true });
fs.mkdirSync(frames, { recursive: true });

const browser = await chromium.launch({ channel: "chrome", headless: true });
const page = await browser.newPage({ viewport: { width: 512, height: 512 } });
for (const [name, emoji, color] of PICTURES) {
  await page.setContent(`<body style="margin:0;background:${color};width:512px;height:512px;display:flex;align-items:center;justify-content:center">
    <span style="font-family:'Noto Color Emoji';font-size:300px;line-height:1;transform:translateY(8px)">${emoji}</span></body>`);
  await page.waitForTimeout(100);
  await page.screenshot({ path: `${out}/${name}.png` });
}

await page.setViewportSize({ width: 1280, height: 720 });
await page.goto(`file://${HERE}/kart.html#still=4.1`);
await page.waitForTimeout(300);
await page.screenshot({ path: `${out}/kart-win.png` });
for (let i = 0; i < 360; i++) {
  await page.evaluate((t) => window.seek(t), 3 + i / 30);
  await page.screenshot({ path: `${frames}/f${String(i).padStart(4, "0")}.jpg`, type: "jpeg", quality: 85 });
}
await browser.close();

execFileSync("ffmpeg", ["-loglevel", "error", "-y", "-framerate", "30", "-i", `${frames}/f%04d.jpg`,
  "-c:v", "libvpx-vp9", "-b:v", "2M", "-deadline", "realtime", "-cpu-used", "8", "-pix_fmt", "yuv420p", `${out}/kart.webm`]);
fs.rmSync(frames, { recursive: true });
console.log("pictures and kart.webm in", out);
