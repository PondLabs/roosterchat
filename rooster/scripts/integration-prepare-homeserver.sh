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

# The MatrixRTC focus is announced by the homeserver itself: the config
# block joins integration_test/synapse/data/homeserver.yaml BEFORE the
# container boots (see scripts/integration-server-synapse.sh - Synapse only
# reads its config at startup, and a restart here was found to kill the
# container's tmpfs state). Verify the announcement: the e2e's joins hang
# off it.
LIVEKIT_URL="${LIVEKIT_URL:-http://localhost:8180}"
echo "Checking /.well-known/matrix/client announces the LiveKit focus..."
if ! curl -fS --retry 3 "http://$HOMESERVER/.well-known/matrix/client" \
    | jq -e --arg url "$LIVEKIT_URL" \
        '[.["org.matrix.msc4143.rtc_foci"][]? | select(.type == "livekit" and .livekit_service_url == $url)] | length > 0' \
        >/dev/null; then
  echo "well-known does not announce $LIVEKIT_URL as a livekit focus" >&2
  exit 1
fi
echo "Well-known announces livekit focus $LIVEKIT_URL"

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
