#!/usr/bin/env python3
"""The MatrixRTC authorization service for the integration stack (issue #225).

A minimal stand-in for element-hq's lk-jwt-service, matching exactly what
`matrix_livekit_backend.dart` consumes: `POST /sfu/get` with
{device_id, room, openid_token{...}} answers {url, jwt} — the room's
LiveKit WebSocket and a room-join token for this device.

The caller's identity comes from the OpenID token, introspected at the
homeserver (GET _matrix/federation/v1/openid/userinfo), and the signed
claim carries it, so the LiveKit roster shows matrix user ids like the
app expects (`.split(":").take(2)` = user, then the device).

Env:
  LISTEN_PORT        (default 8080; the compose maps it to 8180)
  LIVEKIT_URL        the ws:// URL handed back to clients (default
                     ws://localhost:7880)
  LIVEKIT_API_KEY    (default devkey)
  LIVEKIT_API_SECRET (default secret)
  HOMESERVER_URL     where OpenID tokens are introspected
                     (default http://localhost:80)

Development/testing only: the OpenID check is one introspection and no
more; do not run this on a public address.
"""
import base64
import hashlib
import hmac
import json
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "8080"))
LIVEKIT_URL = os.environ.get("LIVEKIT_URL", "ws://localhost:7880")
API_KEY = os.environ.get("LIVEKIT_API_KEY", "devkey")
API_SECRET = os.environ.get("LIVEKIT_API_SECRET", "secret")
HOMESERVER = os.environ.get("HOMESERVER_URL", "http://localhost:80")

TOKEN_TTL = 60 * 30


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _sign_room_jwt(identity: str, room: str) -> str:
    header = _b64(json.dumps(
        {"alg": "HS256", "typ": "JWT"}).encode())
    now = int(time.time())
    payload = _b64(json.dumps({
        "iss": API_KEY,
        "sub": identity,
        "nbf": now - 10,
        "exp": now + TOKEN_TTL,
        "name": identity,
        "video": {
            "room": room,
            "roomJoin": True,
            "canPublish": True,
            "canSubscribe": True,
            "canPublishData": True,
        },
    }).encode())
    signing = f"{header}.{payload}".encode()
    signature = _b64(hmac.new(API_SECRET.encode(), signing, hashlib.sha256).digest())
    return f"{header}.{payload}.{signature}"


def _introspect(access_token: str) -> str:
    """Who owns this OpenID token, per the homeserver: the matrix user id."""
    import urllib.request
    url = (f"{HOMESERVER}/_matrix/federation/v1/openid/userinfo"
           f"?access_token={access_token}")
    with urllib.request.urlopen(url, timeout=10) as response:
        answer = json.load(response)
    sub = answer.get("sub")
    if not sub or not str(sub).startswith("@"):
        raise ValueError("openid token does not name a matrix user")
    return str(sub)


class Handler(BaseHTTPRequestHandler):
    def _cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "content-type")

    def do_OPTIONS(self) -> None:
        self.send_response(200)
        self._cors()
        self.end_headers()

    def do_POST(self) -> None:
        if self.path.rstrip("/") != "/sfu/get":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("content-length", "0"))
            body = json.loads(self.rfile.read(length) or b"{}")
            openid = body.get("openid_token") or {}
            user = _introspect(openid.get("access_token", ""))
            identity = f"{user}:{body.get('device_id', '')}"
            jwt = _sign_room_jwt(identity, body.get("room", ""))
        except Exception as exc:  # noqa: BLE001 - answer, then log
            print(f"sfu/get refused: {exc}")
            self.send_response(401)
            self._cors()
            self.end_headers()
            self.wfile.write(str(exc).encode())
            return
        answer = json.dumps({"url": LIVEKIT_URL, "jwt": jwt}).encode()
        self.send_response(200)
        self._cors()
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(answer)))
        self.end_headers()
        self.wfile.write(answer)


if __name__ == "__main__":
    print(f"matrixrtc auth service on :{LISTEN_PORT} -> {LIVEKIT_URL}")
    ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), Handler).serve_forever()
