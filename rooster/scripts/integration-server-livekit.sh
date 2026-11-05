#!/usr/bin/env bash
#
# Local MatrixRTC stack for the voice e2e integration environment (issue
# #225), done in two containers:
#
#   livekit      livekit/livekit-server, dev mode, the media server:
#                WebSocket on 7880, RTC on 7881/tcp, 7882/udp and
#                50000-60000/udp.
#   matrixrtc    dev_matrixrtc_auth_service.py (this repo): answers the
#                client's POST /sfu/get with a room JWT, introspecting the
#                OpenID token at the homeserver - the piece a plain
#                livekit-server does not serve.
#
# The homeserver's well-known (set by integration-prepare-homeserver.sh)
# announces the AUTH service as the rtc_foci: that is where clients ask
# for their token. `livekit://` in the well-known means only "a livekit
# focus"; the URL the clients hit is the one published.
#
# Idempotent: existing containers are reused (started when stopped), new
# ones are only created when missing.
#
# Env (all optional; CI sets them explicitly in
# .github/workflows/integration-test.yml):
#   LIVEKIT_API_KEY     fixed dev API key     (default: devkey)
#   LIVEKIT_API_SECRET  fixed dev API secret (default: secret)
#   LIVEKIT_CONTAINER   docker name of the SFU (default: livekit)
#   AUTH_CONTAINER      docker name of the auth service (default: matrixrtc)
#   HOMESERVER_URL      where auth introspects the OpenID token
#                       (default: http://localhost:80)
#
# The voice/game e2e test (issue #232) skips gracefully when the stack is
# not reachable, so local test runs without Docker keep working.
set -euo pipefail

CONTAINER="${LIVEKIT_CONTAINER:-livekit}"
AUTH_CONTAINER="${AUTH_CONTAINER:-matrixrtc}"
API_KEY="${LIVEKIT_API_KEY:-devkey}"
API_SECRET="${LIVEKIT_API_SECRET:-secret}"
HTTP_PORT="${LIVEKIT_HTTP_PORT:-7880}"
HOMESERVER="${HOMESERVER_URL:-http://localhost:80}"

# The host network keeps the addresses honest: the containers' ports ARE
# the host's, and the auth service reaches the Synapse on http://localhost
# (a compose-bridged setup would need the container names in HOMESERVER_URL;
# the CI and every dev box here are Linux, where host networking works).
if docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "Reusing existing LiveKit container '$CONTAINER'."
  docker start "$CONTAINER" >/dev/null
else
  echo "Starting livekit/livekit-server (dev mode, host network) as '$CONTAINER'..."
  docker run -d --name "$CONTAINER" \
    --network host \
    -e "LIVEKIT_KEYS=${API_KEY}: ${API_SECRET}" \
    livekit/livekit-server:latest --dev
fi

if docker inspect "$AUTH_CONTAINER" >/dev/null 2>&1; then
  echo "Reusing existing MatrixRTC auth container '$AUTH_CONTAINER'."
  docker start "$AUTH_CONTAINER" >/dev/null
else
  echo "Starting the auth service as '$AUTH_CONTAINER'..."
  docker run -d --name "$AUTH_CONTAINER" \
    --network host \
    -e "LISTEN_PORT=8180" \
    -e "LIVEKIT_URL=ws://localhost:${HTTP_PORT}" \
    -e "LIVEKIT_API_KEY=${API_KEY}" \
    -e "LIVEKIT_API_SECRET=${API_SECRET}" \
    -e "HOMESERVER_URL=${HOMESERVER}" \
    -v "$(pwd)/scripts/dev_matrixrtc_auth_service.py":/srv/auth.py:ro \
    python:3-alpine python /srv/auth.py
fi

echo "Waiting for LiveKit on http://localhost:${HTTP_PORT} ..."
for _ in $(seq 1 30); do
  if curl -s -o /dev/null "http://localhost:${HTTP_PORT}/"; then
    echo "LiveKit is up."
    break
  fi
  if [ "$_" = 30 ]; then
    echo "LiveKit did not answer on port ${HTTP_PORT}; last logs:" >&2
    docker logs "$CONTAINER" >&2 || true
    exit 1
  fi
  sleep 1
done

echo "Waiting for the MatrixRTC auth service on http://localhost:8180 ..."
for _ in $(seq 1 30); do
  if curl -s -o /dev/null "http://localhost:8180/"; then
    echo "MatrixRTC auth service is up (the well-known focus is http://localhost:8180)."
    exit 0
  fi
  sleep 1
done
echo "The auth service did not answer on port 8180; last logs:" >&2
docker logs "$AUTH_CONTAINER" >&2 || true
exit 1
