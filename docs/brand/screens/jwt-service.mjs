// Stands in for lk-jwt-service while the screenshots are taken. Rooster asks
// it for a LiveKit token (the legacy POST /sfu/get) and only takes an https
// focus; lk-jwt-service would also look the made-up server name up in DNS.
// This one serves https with setup.sh's self-signed certificate, checks the
// OpenID token with the local Synapse directly and signs a token for
// LiveKit's dev keys (devkey/secret), with lk-jwt-service's identity
// (`@user:server:DEVICE`) and room name (the room id, hashed).
import crypto from "node:crypto";
import fs from "node:fs";
import https from "node:https";

const WORK = process.env.ROOSTER_SHOTS ?? "/tmp/rooster-shots";
const HS = "http://localhost:8008";
const LIVEKIT_URL = "ws://localhost:7880";
const KEY = "devkey";
const SECRET = "secret";

function sign(claims) {
  const head = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url");
  const body = Buffer.from(JSON.stringify(claims)).toString("base64url");
  const mac = crypto.createHmac("sha256", SECRET).update(`${head}.${body}`).digest("base64url");
  return `${head}.${body}.${mac}`;
}

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Allow-Headers": "*",
};

https.createServer({
  key: fs.readFileSync(`${WORK}/certs/key.pem`),
  cert: fs.readFileSync(`${WORK}/certs/cert.pem`),
}, async (req, res) => {
  if (req.method === "OPTIONS") {
    res.writeHead(204, cors);
    res.end();
    return;
  }
  if (req.method !== "POST" || !req.url.startsWith("/sfu/get")) {
    res.writeHead(404, cors);
    res.end();
    return;
  }
  let raw = "";
  for await (const chunk of req) raw += chunk;
  try {
    const body = JSON.parse(raw);
    const who = await fetch(`${HS}/_matrix/federation/v1/openid/userinfo?access_token=${encodeURIComponent(body.openid_token.access_token)}`);
    if (!who.ok) throw new Error(`openid ${who.status}`);
    const { sub } = await who.json();
    const identity = `${sub}:${body.device_id}`;
    const room = crypto.createHash("sha256").update(body.room).digest("base64").replace(/=+$/, "");
    const now = Math.floor(Date.now() / 1000);
    const jwt = sign({
      iss: KEY, sub: identity, name: identity, nbf: now - 10, exp: now + 6 * 3600,
      video: { room, roomJoin: true, canPublish: true, canSubscribe: true, canPublishData: true },
    });
    console.log(new Date().toISOString(), "token for", identity);
    res.writeHead(200, { ...cors, "Content-Type": "application/json" });
    res.end(JSON.stringify({ url: LIVEKIT_URL, jwt }));
  } catch (e) {
    console.log("refused:", String(e));
    res.writeHead(401, { ...cors, "Content-Type": "application/json" });
    res.end(JSON.stringify({ errcode: "M_UNAUTHORIZED", error: String(e) }));
  }
}).listen(8443, "127.0.0.1", () => console.log("jwt service on https://localhost:8443"));
