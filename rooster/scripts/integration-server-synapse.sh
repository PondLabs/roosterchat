#!/usr/bin/env bash
#
# Brings the integration homeserver up with the MatrixRTC focus already in
# its configuration. Synapse reads its config once, at boot, so the
# well-known block is appended BEFORE the container starts (and the file is
# restored as soon as the server answers, which is after it has read and
# loaded it - see docs/call-activities.md, the integration stack section).
# A restart here would wipe the container's tmpfs state and race its own
# port; do not reintroduce one.
#
# Env: LIVEKIT_URL - the focus the well-known announces; the default is the
# auth service that scripts/integration-server-livekit.sh brings up on
# http://localhost:8180.
set -euo pipefail

CONFIG="$(pwd)/integration_test/synapse/data/homeserver.yaml"
LOG_CONFIG="$(pwd)/integration_test/synapse/data/localhost.log.config"
HOMESERVER_HOST="${HOMESERVER:-localhost}"
LIVEKIT_URL="${LIVEKIT_URL:-http://localhost:8180}"
MARKER="# rooster-integration-livekit-wellknown"

restore_config() {
  if [ -n "${config_backup:-}" ] && [ -f "${config_backup:-}" ]; then
    cp "$config_backup" "$CONFIG"
    rm -f "$config_backup"
  fi
}
trap restore_config EXIT

# A stale block from an interrupted run comes off first.
awk -v m="$MARKER" '
  !found && $0 == m { found = 1 }
  !found { lines[++n] = $0 }
  END {
    while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
    for (i = 1; i <= n; i++) print lines[i]
  }
' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"

config_backup=$(mktemp /tmp/rooster-homeserver-yaml.XXXXXX)
cp "$CONFIG" "$config_backup"

cat >> "$CONFIG" <<EOF
$MARKER
# The MatrixRTC focus for the integration stack (see the script's header).
# public_baseurl makes Synapse serve /.well-known/matrix/client.
public_baseurl: "http://$HOMESERVER_HOST/"
extra_well_known_client_content:
  org.matrix.msc4143.rtc_foci:
    - type: livekit
      livekit_service_url: $LIVEKIT_URL
EOF

if docker inspect synapse >/dev/null 2>&1; then
  echo "Reusing existing Synapse container 'synapse'."
  docker start synapse >/dev/null
else
  echo "Starting Synapse..."
  docker run -d --name synapse --tmpfs /data \
    --volume="$CONFIG":/data/homeserver.yaml:rw \
    --volume="$LOG_CONFIG":/data/localhost.log.config:rw \
    -p 80:80 matrixdotorg/synapse:latest
fi

echo "Waiting for homeserver to be available... (GET http://$HOMESERVER_HOST/_matrix/client/v3/login)"
for _ in $(seq 1 120); do
  if curl -s -o /dev/null "http://$HOMESERVER_HOST/_matrix/client/v3/login"; then
    # The config was read at boot; the checkout's file goes back now.
    trap - EXIT
    restore_config
    echo "Homeserver is up, advertising $LIVEKIT_URL as the livekit focus."
    exit 0
  fi
  sleep 1
done
echo "Homeserver did not come up; last logs:" >&2
docker logs synapse 2>&1 | tail -40 >&2 || true
exit 1
