#!/usr/bin/env bash
#
# Local LiveKit server for the voice e2e integration environment (issue #225).
#
# Starts livekit/livekit-server in dev mode with a fixed API key/secret:
#   - HTTP + WebSocket API on port 7880, announced to clients as LIVEKIT_URL
#     (default livekit://localhost:7880)
#   - RTC over TCP on 7881, over UDP on 7882 and on the 50000-60000/udp range
#
# Idempotent: an existing 'livekit' container is reused (started when stopped),
# a new one is only created when missing, so re-running this script is safe.
#
# Env (all optional; CI sets them explicitly in
# .github/workflows/integration-test.yml):
#   LIVEKIT_URL         focus URL that scripts/integration-prepare-homeserver.sh
#                       publishes in the homeserver's well-known rtc_foci
#   LIVEKIT_API_KEY     fixed dev API key     (default: devkey)
#   LIVEKIT_API_SECRET  fixed dev API secret  (default: secret)
#   LIVEKIT_CONTAINER   docker container name (default: livekit)
#   LIVEKIT_HTTP_PORT   published HTTP port   (default: 7880)
#
# The voice/game e2e test (issue #232) skips gracefully when LiveKit is not
# reachable, so local test runs without Docker keep working.
set -euo pipefail

CONTAINER="${LIVEKIT_CONTAINER:-livekit}"
API_KEY="${LIVEKIT_API_KEY:-devkey}"
API_SECRET="${LIVEKIT_API_SECRET:-secret}"
HTTP_PORT="${LIVEKIT_HTTP_PORT:-7880}"

if docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "Reusing existing LiveKit container '$CONTAINER'."
  docker start "$CONTAINER" >/dev/null
else
  echo "Starting livekit/livekit-server (dev mode) as '$CONTAINER'..."
  docker run -d --name "$CONTAINER" \
    -p 7880:7880 \
    -p 7881:7881 \
    -p 7882:7882/udp \
    -p 50000-60000:50000-60000/udp \
    -e "LIVEKIT_KEYS=${API_KEY}: ${API_SECRET}" \
    livekit/livekit-server:latest --dev
fi

echo "Waiting for LiveKit on http://localhost:${HTTP_PORT} ..."
for _ in $(seq 1 30); do
  if curl -s -o /dev/null "http://localhost:${HTTP_PORT}/"; then
    echo "LiveKit is up (LIVEKIT_URL=${LIVEKIT_URL:-livekit://localhost:${HTTP_PORT}})."
    exit 0
  fi
  sleep 1
done

echo "LiveKit did not answer on port ${HTTP_PORT}; last logs:" >&2
docker logs "$CONTAINER" >&2 || true
exit 1
