#!/usr/bin/env bash
# Runs a Flutter Linux build in a display of its own, off the user's screen,
# and takes screenshots and videos of it.
#
#   headless-linux.sh run [--size WxH] [--keep-home] [--offline] BUNDLE|EXE [ARGS...]
#       Starts a headless mutter (no screen, no input devices) on a private
#       D-Bus session, a rootful Xwayland inside it, and the app on that X
#       display. Stays in the foreground until the app exits or the run is
#       stopped (Ctrl+C, SIGTERM, `stop`), then tears everything down and
#       exits with the app's code. BUNDLE is a `build/linux/x64/<mode>/bundle`
#       folder; its executable is found by itself.
#       --size        the display size, 1280x720 by default (even numbers).
#       --keep-home   let the app use the real XDG data, config and cache
#                     folders. By default it gets empty ones, so it does not
#                     open the user's accounts or touch their settings, and
#                     a running Rooster of the user's is not found and joined.
#       --offline     no network for the app: it runs in a network namespace
#                     of its own (`unshare`, no root), loopback only.
#   headless-linux.sh shot FILE.png             a screenshot of the display.
#   headless-linux.sh record SECONDS FILE.mp4   an H.264 video of the display.
#   headless-linux.sh env                       the display variables the app
#                                               process runs with, read from
#                                               /proc, next to this shell's.
#   headless-linux.sh stop                      ends the run.
#
# Several runs can live side by side: set HEADLESS_NAME (default "default")
# to the same value for `run` and the commands that talk to it. A run's state
# (display number, X cookie, logs, the app's empty home) is kept in
# $XDG_RUNTIME_DIR/rooster-headless/$HEADLESS_NAME and removed when it ends.
#
# Example, from rooster/ after `flutter build linux --debug`:
#   scripts/headless-linux.sh run build/linux/x64/debug/bundle &
#   sleep 20 && scripts/headless-linux.sh shot login.png
#   scripts/headless-linux.sh record 6 login.mp4
#   scripts/headless-linux.sh stop; wait
#
# Why this shape: the machine has mutter but no Xvfb, weston or cage, and no
# GStreamer PipeWire source to read mutter's own screencast. An X server that
# draws its whole root window (rootful Xwayland) can be grabbed by ffmpeg's
# x11grab, so the app runs as an X11 client (GDK_BACKEND=x11). Needs mutter,
# Xwayland, dbus-daemon, xauth, mcookie and ffmpeg (with libx264); no root.
set -euo pipefail

name=${HEADLESS_NAME:-default}
state=${XDG_RUNTIME_DIR:-/tmp}/rooster-headless/$name

die() {
  echo "headless-linux: $*" >&2
  exit 1
}

# Loads the running session's display, or fails with a hint.
attach() {
  [[ -s $state/display ]] || die "no run named '$name' (start one with: $0 run BUNDLE)"
  DISPLAY=$(<"$state/display")
  XAUTHORITY=$state/xauth
  export DISPLAY XAUTHORITY
}

grab() {
  ffmpeg -hide_banner -loglevel error -y -f x11grab -draw_mouse 0 "$@"
}

find_executable() {
  local target=$1
  if [[ -f $target && -x $target ]]; then
    realpath "$target"
    return
  fi
  [[ -d $target ]] || die "$target is neither a bundle folder nor an executable"
  local found=()
  local f
  for f in "$target"/*; do
    [[ -f $f && -x $f && ! -L $f ]] && found+=("$f")
  done
  if ((${#found[@]} == 1)); then
    realpath "${found[0]}"
  elif [[ -x $target/rooster ]]; then
    realpath "$target/rooster"
  else
    die "cannot tell which executable in $target to run: ${found[*]:-none}"
  fi
}

wait_for() { # FILE [tenths of a second]
  local i
  for ((i = 0; i < ${2:-100}; i++)); do
    [[ -s $1 || -S $1 ]] && return 0
    sleep 0.1
  done
  return 1
}

run() {
  local size=1280x720 keep_home=0 offline=()
  while [[ ${1:-} == --* ]]; do
    case $1 in
      --size) size=$2 && shift 2 ;;
      --keep-home) keep_home=1 && shift ;;
      --offline) offline=(unshare --user --map-current-user --net) && shift ;;
      *) die "unknown option $1" ;;
    esac
  done
  [[ $# -ge 1 ]] || die "usage: $0 run [--size WxH] [--keep-home] [--offline] BUNDLE|EXE [ARGS...]"
  [[ $size =~ ^[0-9]*[02468]x[0-9]*[02468]$ ]] || die "--size must be WxH with even numbers"
  local exe
  exe=$(find_executable "$1")
  shift

  if [[ -s $state/session.pid ]] && kill -0 "$(<"$state/session.pid")" 2>/dev/null; then
    die "a run named '$name' is already going (HEADLESS_NAME picks another)"
  fi
  rm -rf "$state"
  mkdir -p "$state/logs"
  chmod 700 "$state"
  echo $$ >"$state/session.pid"

  local pids=()
  # shellcheck disable=SC2329 # called by the EXIT trap
  cleanup() {
    trap - EXIT INT TERM
    local p
    for ((p = ${#pids[@]} - 1; p >= 0; p--)); do
      kill "${pids[p]}" 2>/dev/null || true
      wait "${pids[p]}" 2>/dev/null || true
    done
    rm -rf "$state"
  }
  trap cleanup EXIT
  trap 'exit 143' INT TERM

  # Nothing from the user's session may reach the compositor or the app.
  unset WAYLAND_DISPLAY DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS
  export GIO_USE_VFS=local # no gvfs daemon on the private bus

  dbus-daemon --session --nofork --nopidfile --address="unix:path=$state/bus" \
    >"$state/logs/dbus.log" 2>&1 &
  pids+=($!)
  wait_for "$state/bus" || die "the private D-Bus did not start (see $state/logs/dbus.log)"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$state/bus"

  local wayland=rooster-headless-$name
  mutter --headless --wayland --no-x11 --virtual-monitor "$size" \
    --wayland-display "$wayland" >"$state/logs/mutter.log" 2>&1 &
  pids+=($!)
  wait_for "${XDG_RUNTIME_DIR:-/tmp}/$wayland" 300 ||
    die "mutter did not start (see $state/logs/mutter.log)"

  touch "$state/xauth"
  WAYLAND_DISPLAY=$wayland Xwayland -displayfd 3 -geometry "$size" -fullscreen \
    -auth "$state/xauth" -nolisten tcp 3>"$state/display.fd" \
    >"$state/logs/xwayland.log" 2>&1 &
  pids+=($!)
  wait_for "$state/display.fd" 300 || die "Xwayland did not start (see $state/logs/xwayland.log)"
  local display
  display=":$(head -n1 "$state/display.fd")"
  xauth -q -f "$state/xauth" add "$display" . "$(mcookie)"
  export DISPLAY=$display XAUTHORITY=$state/xauth GDK_BACKEND=x11

  if ((! keep_home)); then
    mkdir -p "$state/home/data" "$state/home/config" "$state/home/cache"
    export XDG_DATA_HOME=$state/home/data XDG_CONFIG_HOME=$state/home/config \
      XDG_CACHE_HOME=$state/home/cache
  fi

  "${offline[@]}" "$exe" "$@" > >(tee "$state/logs/app.log") 2>&1 &
  local app=$!
  pids+=("$app")
  echo "$app" >"$state/app.pid"
  echo "$display" >"$state/display" # last: shot and record wait for it
  echo "headless-linux: '$name' running $exe on $display (${size})" >&2

  local code=0
  wait "$app" || code=$?
  exit "$code"
}

case ${1:-} in
  run)
    shift
    run "$@"
    ;;
  shot)
    [[ $# -eq 2 ]] || die "usage: $0 shot FILE.png"
    attach
    grab -i "$DISPLAY" -frames:v 1 -update 1 "$2"
    ;;
  record)
    [[ $# -eq 3 && $2 =~ ^[0-9]+$ ]] || die "usage: $0 record SECONDS FILE.mp4"
    attach
    grab -framerate 30 -i "$DISPLAY" -t "$2" -c:v libx264 -preset veryfast \
      -pix_fmt yuv420p "$3"
    ;;
  env)
    echo "# this shell"
    for v in WAYLAND_DISPLAY DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS; do
      echo "$v=${!v-}"
    done
    attach
    pid=$(<"$state/app.pid")
    echo "# app process $pid: $(readlink "/proc/$pid/exe")"
    tr '\0' '\n' <"/proc/$pid/environ" | sort |
      sed -nE '/^(WAYLAND_DISPLAY|DISPLAY|XAUTHORITY|GDK_BACKEND|DBUS_SESSION_BUS_ADDRESS|XDG_[A-Z]+_HOME)=/p'
    wl=$(tr '\0' '\n' <"/proc/$pid/environ" | sed -n '/^WAYLAND_DISPLAY=/{s/.*/yes/;p;q}')
    echo "# WAYLAND_DISPLAY set for the app: ${wl:-no}"
    ;;
  stop)
    [[ -s $state/session.pid ]] || die "no run named '$name'"
    kill "$(<"$state/session.pid")"
    ;;
  *)
    sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'
    [[ $# -eq 0 || $1 == -h || $1 == --help ]]
    ;;
esac
