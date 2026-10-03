#!/usr/bin/env python3
"""Drags a file onto the built Rooster, for real.

A small GTK window offers a file the way a file manager does (text/uri-list),
xdotool presses on it, moves over Rooster with the button held and lets go.
Fails when Rooster does not ask for the file, which is what someone dragging
from a file manager would see as a refused drop.

    xvfb-run -s '-screen 0 1920x1080x24' \
        python3 tools/linux_drop_smoke.py --bundle rooster/build/linux/x64/release/bundle

Needs python3-gi, gir1.2-gtk-3.0 and xdotool, and an X display.
"""
import argparse
import os
import pathlib
import subprocess
import sys
import tempfile
import threading
import time

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402


def xdotool(*args: str) -> str:
    return subprocess.run(
        ["xdotool", *args], check=False, capture_output=True, text=True
    ).stdout.strip()


def wait_for_window(pid: int, seconds: float) -> str | None:
    """Rooster's window, once it is shown: the largest visible one it has."""
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        best, area = None, 0
        for window in xdotool("search", "--onlyvisible", "--pid", str(pid)).split():
            geometry = dict(
                line.split("=", 1)
                for line in xdotool("getwindowgeometry", "--shell", window).splitlines()
                if "=" in line
            )
            size = int(geometry.get("WIDTH", 0)) * int(geometry.get("HEIGHT", 0))
            if size > area:
                best, area = window, size
        if best and area > 200 * 200:
            return best
        time.sleep(0.5)
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", required=True)
    parser.add_argument("--startup-seconds", type=float, default=90)
    args = parser.parse_args()

    exe = pathlib.Path(args.bundle).resolve() / "rooster"
    if not exe.exists():
        print(f"no rooster in {args.bundle}")
        return 1

    dropped = pathlib.Path(tempfile.gettempdir()) / "rooster-drop-smoke.txt"
    dropped.write_text("dropped on Rooster\n")

    # X, not Wayland: xdotool moves the pointer of an X display.
    env = dict(os.environ, GDK_BACKEND="x11")
    Gdk.set_allowed_backends("x11")
    app = subprocess.Popen([str(exe)], cwd=exe.parent, env=env)
    try:
        window = wait_for_window(app.pid, args.startup_seconds)
        if window is None:
            print(f"FAIL: Rooster showed no window (exit code {app.poll()})")
            return 1
        time.sleep(5)  # the first screen settles
        xdotool("windowmove", window, "0", "0")
        xdotool("windowsize", window, "1000", "700")
        time.sleep(1)

        asked, failed = [], []
        source = Gtk.Window(type=Gtk.WindowType.POPUP)
        source.set_default_size(120, 120)
        source.move(1200, 200)
        box = Gtk.EventBox()
        source.add(box)
        box.drag_source_set(
            Gdk.ModifierType.BUTTON1_MASK,
            [],
            Gdk.DragAction.COPY | Gdk.DragAction.MOVE | Gdk.DragAction.LINK,
        )
        box.drag_source_add_uri_targets()

        def on_data_get(_widget, _context, selection, _info, _time):
            selection.set_uris([dropped.as_uri()])
            asked.append(True)

        box.connect("drag-data-get", on_data_get)
        box.connect("drag-failed", lambda *_: failed.append(True) or False)
        box.connect("drag-end", lambda *_: GLib.timeout_add(500, Gtk.main_quit))
        source.show_all()

        def drag() -> None:
            xdotool("mousemove", "1260", "260")
            time.sleep(0.3)
            xdotool("mousedown", "1")
            for step in range(1, 41):
                x = 1260 + (400 - 1260) * step // 40
                y = 260 + (350 - 260) * step // 40
                xdotool("mousemove", str(x), str(y))
                time.sleep(0.03)
            # Hover, as a person does.
            for step in range(10):
                xdotool("mousemove", str(400 + step % 2), "350")
                time.sleep(0.1)
            xdotool("mouseup", "1")

        # Off the main loop: GTK has to answer the drag while the mouse moves.
        mouse = threading.Timer(1.0, drag)
        mouse.daemon = True
        mouse.start()
        # Never hang the build.
        GLib.timeout_add_seconds(30, Gtk.main_quit)
        Gtk.main()

        if asked and not failed:
            print("OK: Rooster took the drop")
            return 0
        print(f"FAIL: Rooster refused the drop (asked for the file: {bool(asked)},"
              f" drag failed: {bool(failed)})")
        return 1
    finally:
        app.terminate()
        try:
            app.wait(timeout=10)
        except subprocess.TimeoutExpired:
            app.kill()


if __name__ == "__main__":
    sys.exit(main())
