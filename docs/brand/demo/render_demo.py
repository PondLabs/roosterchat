#!/usr/bin/env python3
"""Renders demo.html to an MP4, with music made by music.py.

Drives headless Chrome over the DevTools protocol: for every frame it calls
the page's seek(t) and takes a screenshot, and pipes the frames to ffmpeg.
Needs google-chrome, ffmpeg, and websocket-client + numpy in Python.

    python3 docs/brand/demo/render_demo.py                 # the video
    python3 docs/brand/demo/render_demo.py --stills 2,9,20  # PNGs to check
    python3 docs/brand/demo/render_demo.py --reel           # the vertical reel
"""

import argparse
import base64
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

import websocket

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
W, H = 1920, 1080


class Chrome:
    def __init__(self):
        self.profile = tempfile.mkdtemp(prefix="demo-chrome-")
        # A free port: a fixed one let a Chrome left over from an earlier
        # run answer instead, still showing the old page.
        with socket.socket() as s:
            s.bind(("127.0.0.1", 0))
            port = s.getsockname()[1]
        self.proc = subprocess.Popen(
            ["google-chrome", "--headless=new", "--disable-gpu", "--hide-scrollbars",
             "--force-device-scale-factor=1", f"--window-size={W},{H}",
             f"--remote-debugging-port={port}", f"--user-data-dir={self.profile}",
             "--allow-file-access-from-files", "--autoplay-policy=no-user-gesture-required",
             "about:blank"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        for _ in range(100):
            try:
                tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json"))
                page = next(t for t in tabs if t["type"] == "page")
                break
            except Exception:
                time.sleep(.1)
        # No Origin header: Chrome only takes DevTools connections from
        # origins it was told to allow, and this one is local and ours.
        self.ws = websocket.create_connection(page["webSocketDebuggerUrl"],
                                              suppress_origin=True)
        self.n = 0

    def call(self, method, **params):
        self.n += 1
        self.ws.send(json.dumps({"id": self.n, "method": method, "params": params}))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == self.n:
                if "error" in msg:
                    raise RuntimeError(f"{method}: {msg['error']}")
                return msg.get("result", {})

    def eval(self, expr):
        r = self.call("Runtime.evaluate", expression=expr, awaitPromise=True, returnByValue=True)
        if "exceptionDetails" in r:
            raise RuntimeError(r["exceptionDetails"])
        return r.get("result", {}).get("value")

    def open(self, path):
        self.call("Emulation.setDeviceMetricsOverride", width=W, height=H,
                  deviceScaleFactor=1, mobile=False)
        self.call("Page.enable")
        self.call("Page.navigate", url=f"file://{path}?v={time.time()}#render")
        for _ in range(200):
            if self.eval("document.readyState") == "complete":
                break
            time.sleep(.05)
        self.eval("document.fonts.ready.then(() => Promise.all([...document.images].map(i => i.decode())))")

    def frame(self, t):
        self.eval(f"seek({t}); new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))")
        shot = self.call("Page.captureScreenshot", format="png",
                         clip={"x": 0, "y": 0, "width": W, "height": H, "scale": 1})
        return base64.b64decode(shot["data"])

    def close(self):
        # Chrome's helpers are in its session; end them all.
        try:
            os.killpg(self.proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        self.proc.wait()
        shutil.rmtree(self.profile, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stills", help="comma-separated times; writes stills/t.png")
    ap.add_argument("--fps", type=int, default=60)
    ap.add_argument("--reel", action="store_true",
                    help="reel.html, 1080x1920, for Instagram")
    ap.add_argument("--out")
    args = ap.parse_args()
    global W, H
    if args.reel:
        page, cues, poster_at, W, H = "reel.html", "reel", 3.0, 1080, 1920
        out = args.out or os.path.join(ROOT, "website", "rooster-reel.mp4")
    else:
        page, cues, poster_at = "demo.html", "demo", 9.5
        out = args.out or os.path.join(ROOT, "website", "rooster-demo.mp4")

    chrome = Chrome()
    try:
        chrome.open(os.path.join(HERE, page))
        duration = chrome.eval("window.DURATION")
        if args.stills:
            out = os.path.join(tempfile.gettempdir(), "demo-stills")
            os.makedirs(out, exist_ok=True)
            for t in args.stills.split(","):
                with open(os.path.join(out, f"{t}.png"), "wb") as f:
                    f.write(chrome.frame(float(t)))
            print(out)
            return

        music = os.path.join(tempfile.gettempdir(), "rooster-demo-music.wav")
        subprocess.run([sys.executable, os.path.join(HERE, "music.py"), music,
                        str(duration), cues], check=True)
        frames = int(round(duration * args.fps))
        ff = subprocess.Popen(
            ["ffmpeg", "-y", "-loglevel", "error",
             "-f", "image2pipe", "-framerate", str(args.fps), "-c:v", "png", "-i", "-",
             "-i", music,
             "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p",
             "-tune", "animation", "-c:a", "aac", "-b:a", "192k", "-shortest",
             "-movflags", "+faststart", out],
            stdin=subprocess.PIPE)
        start = time.time()
        for i in range(frames):
            ff.stdin.write(chrome.frame(i / args.fps))
            if i % args.fps == 0:
                print(f"{i / args.fps:5.1f}s  ({time.time() - start:.0f}s elapsed)", flush=True)
        ff.stdin.close()
        ff.wait()
        poster = os.path.splitext(out)[0] + "-poster.jpg"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-ss", str(poster_at), "-i", out,
                        "-frames:v", "1", "-q:v", "3", poster], check=True)
        print(out)
    finally:
        chrome.close()


if __name__ == "__main__":
    main()
