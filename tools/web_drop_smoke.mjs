#!/usr/bin/env node
// Drags a file onto the web app in Chrome, as the browser itself delivers a
// drag from a file manager (DevTools' Input.dispatchDragEvent), and fails
// when the page does not take it: an unhandled dragover is the "forbidden"
// cursor, and an unhandled drop makes the browser open the file instead.
//
//   node tools/web_drop_smoke.mjs [--url https://pondlabs.github.io/roosterchat/app/] [--chrome <path>]
//
// Needs Node 22 or later (global WebSocket) and Chrome.
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const args = process.argv.slice(2);
const opt = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : fallback;
};
const url = opt("--url", "https://pondlabs.github.io/roosterchat/app/");
const chrome = opt("--chrome", process.env.CHROME || "google-chrome-stable");
const work = mkdtempSync(join(tmpdir(), "web-drop-"));
const dropped = join(work, "rooster-drop-smoke.txt");
writeFileSync(dropped, "dropped on Rooster\n");

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const browser = spawn(chrome, [
  "--headless=new", "--no-sandbox", "--disable-gpu", "--window-size=1280,800",
  "--remote-debugging-port=0", `--user-data-dir=${join(work, "profile")}`,
  "about:blank",
], { stdio: ["ignore", "ignore", "pipe"] });

let code = 1;
try {
  const endpoint = await new Promise((done, fail) => {
    let err = "";
    browser.stderr.on("data", (d) => {
      err += d;
      const m = err.match(/DevTools listening on (ws:\/\/\S+)/);
      if (m) done(m[1]);
    });
    setTimeout(() => fail(new Error("Chrome did not start: " + err)), 20000);
  });
  const port = new URL(endpoint).port;
  const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
  const page = targets.find((t) => t.type === "page");
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((r) => (ws.onopen = r));
  let next = 1;
  const waiting = new Map();
  ws.onmessage = (m) => {
    const msg = JSON.parse(m.data);
    if (msg.id && waiting.has(msg.id)) {
      waiting.get(msg.id)(msg);
      waiting.delete(msg.id);
    }
  };
  const send = (method, params = {}) =>
    new Promise((done, fail) => {
      const id = next++;
      waiting.set(id, (msg) =>
        msg.error ? fail(new Error(`${method}: ${msg.error.message}`)) : done(msg.result));
      ws.send(JSON.stringify({ id, method, params }));
    });
  const evaluate = async (expression) =>
    (await send("Runtime.evaluate", { expression, returnByValue: true })).result.value;

  await send("Page.enable");
  await send("Page.navigate", { url });
  // The app has started once Flutter has put its view in the page.
  let started = false;
  for (let i = 0; i < 120 && !started; i++) {
    await sleep(500);
    started = await evaluate(
      "!!document.querySelector('flutter-view, flt-glass-pane, flt-scene-host')");
  }
  if (!started) throw new Error("the app did not start at " + url);
  await sleep(5000);

  // Added after the app's own listeners, so these see what it did with
  // each event.
  await evaluate(`
    window.__drop = {};
    for (const type of ['dragenter', 'dragover', 'drop']) {
      window.addEventListener(type, (e) => {
        window.__drop[type] = {
          handled: e.defaultPrevented,
          files: e.dataTransfer ? e.dataTransfer.files.length : -1,
        };
      });
    }
    true`);

  const data = { items: [], files: [dropped], dragOperationsMask: 1 };
  for (const type of ["dragEnter", "dragOver", "dragOver", "drop"]) {
    await send("Input.dispatchDragEvent", { type, x: 500, y: 400, data });
    await sleep(300);
  }
  const seen = await evaluate("window.__drop");
  const still = await evaluate("location.href");
  console.log(JSON.stringify(seen), "page:", still);
  if (!seen.dragover?.handled) {
    console.log("FAIL: the page refuses a file dragged over it");
  } else if (!seen.drop?.handled || seen.drop.files !== 1) {
    console.log("FAIL: the page did not take the dropped file");
  } else {
    console.log("OK: the web app took the drop");
    code = 0;
  }
  ws.close();
} catch (e) {
  console.log("FAIL:", e.message);
} finally {
  browser.kill();
  await sleep(500);
  rmSync(work, { recursive: true, force: true });
}
process.exit(code);
