#!/bin/sh -e
# One-time setup for the landing page screenshots (README.md). Everything
# goes in $ROOSTER_SHOTS (default /tmp/rooster-shots): Synapse in a
# virtualenv, LiveKit's server, a self-signed certificate for the JWT
# stand-in, Playwright, the made-up crew's media, and a copy of the web
# build with Kart Night beside it. Build the web app first (README.md).
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
WORK=${ROOSTER_SHOTS:-/tmp/rooster-shots}
LIVEKIT=1.13.9

[ -f "$ROOT/rooster/build/web/main.dart.js" ] || { echo "Build the web app first: see README.md" >&2; exit 1; }
mkdir -p "$WORK/bin" "$WORK/certs" "$WORK/synapse" "$WORK/node"

[ -x "$WORK/venv/bin/python" ] || python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install -q --upgrade pip matrix-synapse numpy

[ -x "$WORK/bin/livekit-server" ] || curl -sSfL \
  "https://github.com/livekit/livekit/releases/download/v$LIVEKIT/livekit_${LIVEKIT}_linux_amd64.tar.gz" |
  tar xz -C "$WORK/bin" livekit-server

[ -f "$WORK/certs/key.pem" ] || openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
  -keyout "$WORK/certs/key.pem" -out "$WORK/certs/cert.pem" 2>/dev/null

sed "s|@WORK@|$WORK|g" "$HERE/homeserver.yaml" > "$WORK/synapse/homeserver.yaml"
cat > "$WORK/synapse/log.config" <<EOF
version: 1
formatters:
  precise:
    format: '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
handlers:
  file:
    class: logging.FileHandler
    formatter: precise
    filename: $WORK/synapse/homeserver.log
root:
  level: WARNING
  handlers: [file]
disable_existing_loggers: false
EOF
[ -f "$WORK/synapse/the-coop.signing.key" ] ||
  (cd "$WORK/synapse" && "$WORK/venv/bin/python" -m synapse.app.homeserver -c homeserver.yaml --generate-keys >/dev/null 2>&1)

[ -d "$WORK/node/node_modules/playwright-core" ] || npm install --silent --prefix "$WORK/node" playwright-core@1.56

"$WORK/venv/bin/python" "$HERE/make_media.py" "$WORK"
ROOSTER_SHOTS="$WORK" node "$HERE/media.mjs"

rm -rf "$WORK/web"
cp -r "$ROOT/rooster/build/web" "$WORK/web"
cp "$WORK/media/kart.webm" "$WORK/web/kart.webm"
echo "Ready in $WORK. Next: services.sh, then seed.mjs."
