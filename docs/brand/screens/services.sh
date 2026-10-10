#!/bin/sh -e
# Starts what the screenshots need, all on 127.0.0.1: Synapse (8008),
# LiveKit in dev mode (7880, keys devkey/secret), the JWT stand-in (https
# on 8443) and the web build (8090). Logs go in $ROOSTER_SHOTS.
# `services.sh stop` stops them.
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${ROOSTER_SHOTS:-/tmp/rooster-shots}
cd "$WORK"

if [ "$1" = stop ]; then
  kill "$(cat synapse/homeserver.pid 2>/dev/null)" 2>/dev/null || true
  pkill -f "bin/livekit-server --dev" || true
  pkill -f "screens/jwt-service.mjs" || true
  pkill -f "http.server 8090" || true
  exit 0
fi

venv/bin/python -m synapse.app.homeserver -c synapse/homeserver.yaml --daemonize
nohup bin/livekit-server --dev --bind 127.0.0.1 --node-ip 127.0.0.1 > livekit.log 2>&1 &
ROOSTER_SHOTS="$WORK" nohup node "$HERE/jwt-service.mjs" > jwt.log 2>&1 &
(cd web && nohup python3 -m http.server 8090 --bind 127.0.0.1 > ../web.log 2>&1 &)

for _ in $(seq 1 30); do
  curl -sf http://localhost:8008/_matrix/client/versions >/dev/null && break
  sleep 1
done
echo "Synapse on :8008, LiveKit on :7880, the JWT stand-in on :8443, the app on http://localhost:8090/"
