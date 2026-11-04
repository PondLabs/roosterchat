#!/usr/bin/env bash

if [ -z $HOMESERVER ]; then
  echo "Please ensure HOMESERVER environment variable is set to the IP or hostname of the homeserver."
  exit 1
fi
if [ -z $USER1_NAME ]; then
  echo "Please ensure USER1_NAME environment variable is set to first user name."
  exit 1
fi
if [ -z $USER1_PW ]; then
  echo "Please ensure USER1_PW environment variable is set to first user password."
  exit 1
fi
if [ -z $USER2_NAME ]; then
  echo "Please ensure USER2_NAME environment variable is set to second user name."
  exit 1
fi
if [ -z $USER2_PW ]; then
  echo "Please ensure USER2_PW environment variable is set to second user password."
  exit 1
fi

echo "Waiting for homeserver to be available... (GET http://$HOMESERVER/_matrix/client/v3/login)"

while ! curl -XGET "http://$HOMESERVER/_matrix/client/v3/login" >/dev/null 2>/dev/null; do
  sleep 2
done

echo "Homeserver is up."

# Publish the local LiveKit as an RTC focus (MSC4143, issue #225) in
# /.well-known/matrix/client, the shape matrix_livekit_backend.dart's
# getFociUrl() consumes:
#   {"org.matrix.msc4143.rtc_foci": [{"type": "livekit",
#                                     "livekit_service_url": "..."}]}
# Synapse serves that file from its own config, which
# integration-server-synapse.sh bind-mounts rw from
# integration_test/synapse/data/homeserver.yaml: append the block, restart the
# container so it loads the config, then restore the pristine file (Synapse
# only reads the config at startup) to keep the checkout clean. Idempotent: a
# stale block left by an interrupted run is dropped first.
LIVEKIT_URL="${LIVEKIT_URL:-livekit://localhost:7880}"
SYNAPSE_CONTAINER="${SYNAPSE_CONTAINER:-synapse}"
HOMESERVER_YAML="$(pwd)/integration_test/synapse/data/homeserver.yaml"
WELLKNOWN_MARKER="# rooster-integration-livekit-wellknown"

if command -v docker >/dev/null 2>&1 && docker inspect "$SYNAPSE_CONTAINER" >/dev/null 2>&1; then
  if grep -q "^$WELLKNOWN_MARKER$" "$HOMESERVER_YAML"; then
    # A previous run was interrupted between append and restore: drop the
    # stale block (marker line to EOF) and any blank lines it left at the end.
    awk -v m="$WELLKNOWN_MARKER" '
      !found && $0 == m { found = 1 }
      !found { lines[++n] = $0 }
      END {
        while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
        for (i = 1; i <= n; i++) print lines[i]
      }
    ' "$HOMESERVER_YAML" > "$HOMESERVER_YAML.tmp" && mv "$HOMESERVER_YAML.tmp" "$HOMESERVER_YAML"
  fi

  hs_yaml_backup=$(mktemp /tmp/rooster-homeserver-yaml.XXXXXX)
  cp "$HOMESERVER_YAML" "$hs_yaml_backup"
  restore_homeserver_yaml() {
    cp "$hs_yaml_backup" "$HOMESERVER_YAML"
    rm -f "$hs_yaml_backup"
  }
  trap restore_homeserver_yaml EXIT

  cat >> "$HOMESERVER_YAML" <<EOF
$WELLKNOWN_MARKER
# Appended by scripts/integration-prepare-homeserver.sh (issue #225); the
# script removes this block again once Synapse has loaded it.
# public_baseurl is required for Synapse to serve /.well-known/matrix/client.
public_baseurl: "http://$HOMESERVER/"
extra_well_known_client_content:
  org.matrix.msc4143.rtc_foci:
    - type: livekit
      livekit_service_url: $LIVEKIT_URL
EOF

  echo "Restarting '$SYNAPSE_CONTAINER' to load the well-known rtc_foci block..."
  docker restart "$SYNAPSE_CONTAINER"

  echo "Waiting for homeserver to be available again... (GET http://$HOMESERVER/_matrix/client/v3/login)"
  for _ in $(seq 1 60); do
    if curl -XGET "http://$HOMESERVER/_matrix/client/v3/login" >/dev/null 2>/dev/null; then
      break
    fi
    sleep 2
  done
  if ! curl -XGET "http://$HOMESERVER/_matrix/client/v3/login" >/dev/null 2>/dev/null; then
    echo "Homeserver did not come back after the restart; last logs:" >&2
    docker logs "$SYNAPSE_CONTAINER" >&2 || true
    exit 1
  fi
  echo "Homeserver is up again."

  # Synapse read the config at startup; put the pristine file back.
  restore_homeserver_yaml
  trap - EXIT

  echo "Checking /.well-known/matrix/client announces the LiveKit focus..."
  if ! curl -fS --retry 3 "http://$HOMESERVER/.well-known/matrix/client" \
      | jq -e --arg url "$LIVEKIT_URL" \
          '[.["org.matrix.msc4143.rtc_foci"][]? | select(.type == "livekit" and .livekit_service_url == $url)] | length > 0' \
          >/dev/null; then
    echo "well-known does not announce $LIVEKIT_URL as a livekit focus" >&2
    exit 1
  fi
  echo "Well-known announces livekit focus $LIVEKIT_URL"
else
  echo "WARNING: no local '$SYNAPSE_CONTAINER' container found; assuming" >&2
  echo "http://$HOMESERVER already serves the rtc_foci well-known for $LIVEKIT_URL." >&2
fi

# create users

curl -fS --retry 3 -XPOST -d "{\"username\":\"$USER1_NAME\", \"password\":\"$USER1_PW\", \"inhibit_login\":true, \"auth\": {\"type\":\"m.login.dummy\"}}" "http://$HOMESERVER/_matrix/client/r0/register"
curl -fS --retry 3 -XPOST -d "{\"username\":\"$USER2_NAME\", \"password\":\"$USER2_PW\", \"inhibit_login\":true, \"auth\": {\"type\":\"m.login.dummy\"}}" "http://$HOMESERVER/_matrix/client/r0/register"

usertoken1=$(curl -fS --retry 3 "http://$HOMESERVER/_matrix/client/r0/login" -H "Content-Type: application/json" -d "{\"type\": \"m.login.password\", \"identifier\": {\"type\": \"m.id.user\",\"user\": \"$USER1_NAME\"},\"password\":\"$USER1_PW\"}" | jq -r '.access_token')
usertoken2=$(curl -fS --retry 3 "http://$HOMESERVER/_matrix/client/r0/login" -H "Content-Type: application/json" -d "{\"type\": \"m.login.password\", \"identifier\": {\"type\": \"m.id.user\",\"user\": \"$USER2_NAME\"},\"password\":\"$USER2_PW\"}" | jq -r '.access_token')


# get usernames' mxids
mxid1=$(curl -fS --retry 3 "http://$HOMESERVER/_matrix/client/r0/account/whoami" -H "Authorization: Bearer $usertoken1" | jq -r .user_id)
mxid2=$(curl -fS --retry 3 "http://$HOMESERVER/_matrix/client/r0/account/whoami" -H "Authorization: Bearer $usertoken2" | jq -r .user_id)

# setting the display name to username
curl -fS --retry 3 -XPUT -d "{\"displayname\":\"$USER1_NAME\"}" "http://$HOMESERVER/_matrix/client/v3/profile/$mxid1/displayname" -H "Authorization: Bearer $usertoken1"
curl -fS --retry 3 -XPUT -d "{\"displayname\":\"$USER2_NAME\"}" "http://$HOMESERVER/_matrix/client/v3/profile/$mxid2/displayname" -H "Authorization: Bearer $usertoken2"

echo "Set display names"

# create new room to invite user too
roomID=$(curl --retry 3 --silent --fail -XPOST -d "{\"name\":\"$USER2_NAME\", \"is_direct\": true}" "http://$HOMESERVER/_matrix/client/r0/createRoom?access_token=$usertoken2" | jq -r '.room_id')
echo "Created room '$roomID'"

# send message in created room
curl --retry 3 --fail --silent -XPOST -d '{"msgtype":"m.text", "body":"joined room successfully"}' "http://$HOMESERVER/_matrix/client/r0/rooms/$roomID/send/m.room.message?access_token=$usertoken2"
echo "Sent message"

curl -fS --retry 3 -XPOST -d "{\"user_id\":\"$mxid1\"}" "http://$HOMESERVER/_matrix/client/r0/rooms/$roomID/invite?access_token=$usertoken2"
echo "Invited $USER1_NAME"

# create a space owned by user1, so that tests which act on an existing space do
# not depend on another test having created one first
spaceID=$(curl --retry 3 --silent --fail -XPOST -H "Content-Type: application/json" -d "{\"name\":\"Integration Test Space\", \"preset\":\"private_chat\", \"creation_content\":{\"type\":\"m.space\"}}" "http://$HOMESERVER/_matrix/client/v3/createRoom?access_token=$usertoken1" | jq -r '.room_id')
echo "Created space '$spaceID' for $USER1_NAME"
