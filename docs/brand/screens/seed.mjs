// Fills the local homeserver with the made-up crew the screenshots show:
// eight people, their houses, The Coop's text and voice channels, an
// evening of chat in #general (a picture, replies, reactions, a poll, a
// mention), a DM and four soundboard sounds. Nothing here is a real
// account. Run once on a fresh database: node seed.mjs
import fs from "node:fs";

const WORK = process.env.ROOSTER_SHOTS ?? "/tmp/rooster-shots";
const HS = process.env.HOMESERVER ?? "http://localhost:8008";
const SERVER = "the-coop.social";
export const PASSWORD = "rooster-landing-demo";

// The status line shows under each name in the member lists, where the
// server name would be otherwise.
const PEOPLE = {
  maya: { name: "Maya", presence: "online", status: "rematch at 10" },
  theo: { name: "Theo", presence: "online", status: "warming up the controller" },
  priya: { name: "Priya", presence: "online", status: "on the decks tonight" },
  jonas: { name: "Jonas", presence: "online", status: "streaming Kart Night" },
  bia: { name: "Bia", presence: "online", status: "noodles, then Lounge" },
  kenji: { name: "Kenji", presence: "online", status: "rematch? rematch." },
  lou: { name: "Lou", presence: "online", status: "lurking" },
  rafa: { name: "Rafa", presence: "offline", status: "back on Monday" },
};

let txn = 0;
async function api(token, method, path, body, { raw, contentType } = {}) {
  const res = await fetch(HS + path, {
    method,
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(body !== undefined ? { "Content-Type": contentType ?? "application/json" } : {}),
    },
    body: body === undefined ? undefined : raw ? body : JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${path} -> ${res.status} ${text}`);
  return text ? JSON.parse(text) : {};
}

const users = {};
const mx = (u) => users[u].mxid;
const as = (u) => users[u].token;

async function upload(u, file, mime) {
  const data = fs.readFileSync(file);
  const r = await api(as(u), "POST", `/_matrix/media/v3/upload?filename=${encodeURIComponent(file.split("/").pop())}`, data, { raw: true, contentType: mime });
  return { mxc: r.content_uri, size: data.length };
}

const send = (u, room, type, content) =>
  api(as(u), "PUT", `/_matrix/client/v3/rooms/${encodeURIComponent(room)}/send/${type}/seed${Date.now()}-${txn++}`, content).then((r) => r.event_id);
const state = (u, room, type, key, content) =>
  api(as(u), "PUT", `/_matrix/client/v3/rooms/${encodeURIComponent(room)}/state/${type}/${encodeURIComponent(key)}`, content);
const join = (u, room) => api(as(u), "POST", `/_matrix/client/v3/join/${encodeURIComponent(room)}?server_name=${SERVER}`, {});
const say = (u, room, body, extra = {}) => send(u, room, "m.room.message", { msgtype: "m.text", body, ...extra });
const react = (u, room, eventId, key) => send(u, room, "m.reaction", { "m.relates_to": { rel_type: "m.annotation", event_id: eventId, key } });
// Replies without the quoted fallback, the way current clients send them.
const reply = (u, room, to, body) => send(u, room, "m.room.message", { msgtype: "m.text", body, "m.relates_to": { "m.in_reply_to": { event_id: to } } });
// A little time between messages, so they come in the order they're sent.
const beat = () => new Promise((r) => setTimeout(r, 40));

for (const [id, p] of Object.entries(PEOPLE)) {
  const r = await api(null, "POST", "/_matrix/client/v3/register", {
    username: id, password: PASSWORD, auth: { type: "m.login.dummy" }, initial_device_display_name: "seed",
  });
  users[id] = { token: r.access_token, mxid: r.user_id };
  const { mxc } = await upload(id, `${WORK}/media/${id}.png`, "image/png");
  await api(as(id), "PUT", `/_matrix/client/v3/profile/${encodeURIComponent(mx(id))}/displayname`, { displayname: p.name });
  await api(as(id), "PUT", `/_matrix/client/v3/profile/${encodeURIComponent(mx(id))}/avatar_url`, { avatar_url: mxc });
}
const everyone = Object.keys(PEOPLE);

// Room version 12: the creator has unlimited power and is not listed.
const powerLevels = (owner, events = {}) => ({
  users: Object.fromEntries([["maya", 100], ["theo", 50]].filter(([u]) => u !== owner).map(([u, level]) => [mx(u), level])),
  users_default: 0,
  events: { "m.room.name": 50, "m.room.power_levels": 100, "m.space.child": 50, ...events },
  state_default: 50, events_default: 0, invite: 0, kick: 50, ban: 50, redact: 50,
});

async function createSpace(owner, name, topic, picture, invite) {
  const { mxc } = await upload(owner, `${WORK}/media/${picture}.png`, "image/png");
  const r = await api(as(owner), "POST", "/_matrix/client/v3/createRoom", {
    name, topic, preset: "private_chat", visibility: "private", invite: invite.map(mx),
    creation_content: { type: "m.space" },
    power_level_content_override: powerLevels(owner),
    initial_state: [{ type: "m.room.avatar", state_key: "", content: { url: mxc } }],
  });
  return r.room_id;
}

// What the app makes for a channel: open to the space's members, and for
// a voice channel the call room type, with anyone allowed to join the call
// and set the channel's status (MatrixClient.createRoom).
async function createChannel(space, name, { voice = false, topic, order }) {
  const r = await api(as("maya"), "POST", "/_matrix/client/v3/createRoom", {
    name, topic, preset: "private_chat", visibility: "private",
    ...(voice ? { creation_content: { type: "org.matrix.msc3417.call" } } : {}),
    power_level_content_override: powerLevels("maya", voice ? {
      "org.matrix.msc3401.call": 0, "org.matrix.msc3401.call.member": 0, "chat.commet.voice_channel_status": 0,
    } : {}),
    initial_state: [
      { type: "m.space.parent", state_key: space, content: { canonical: true, via: [SERVER] } },
      { type: "m.room.join_rules", state_key: "", content: { join_rule: "restricted", allow: [{ type: "m.room_membership", room_id: space }] } },
    ],
  });
  await state("maya", space, "m.space.child", r.room_id, { via: [SERVER], order });
  return r.room_id;
}

const coop = await createSpace("maya", "The Coop", "Come on in. Make yourself at home.", "space-coop", everyone.filter((u) => u !== "maya"));
for (const u of everyone) if (u !== "maya") await join(u, coop);
const rooms = { coop };
rooms.general = await createChannel(coop, "general", { topic: "Anything goes", order: "a" });
rooms.memes = await createChannel(coop, "memes", { order: "b" });
rooms.clips = await createChannel(coop, "clips", { topic: "Your best (and worst) moments", order: "c" });
rooms.music = await createChannel(coop, "music-recs", { order: "d" });
rooms.lounge = await createChannel(coop, "Lounge", { voice: true, order: "e" });
rooms.gameNight = await createChannel(coop, "Game night", { voice: true, order: "f" });
rooms.quiet = await createChannel(coop, "Quiet corner", { voice: true, order: "g" });
for (const u of everyone) {
  if (u === "maya") continue;
  for (const key of ["general", "memes", "clips", "music", "lounge", "gameNight", "quiet"]) await join(u, rooms[key]);
}

// Maya's other houses, for the space rail.
rooms.games = await createSpace("theo", "Game Night Club", "Fridays, 9 pm", "space-games", ["maya"]);
rooms.lan = await createSpace("jonas", "LAN Party", "Bring your own cables", "space-lan", ["maya"]);
rooms.books = await createSpace("priya", "Book Club", "One chapter at a time", "space-books", ["maya"]);
rooms.synth = await createSpace("bia", "Synth Lab", "Knobs and patches", "space-synth", ["maya"]);
for (const key of ["games", "lan", "books", "synth"]) await join("maya", rooms[key]);
const rail = Object.fromEntries(["coop", "games", "lan", "books", "synth"].map((key, i) => [rooms[key], { order: String.fromCharCode(97 + i) }]));
for (const u of everyone) {
  await api(as(u), "PUT", `/_matrix/client/v3/user/${encodeURIComponent(mx(u))}/account_data/chat.commet.sidebar_ordering`, { spaces: rail });
}

for (const [id, p] of Object.entries(PEOPLE)) {
  await api(as(id), "PUT", `/_matrix/client/v3/presence/${encodeURIComponent(mx(id))}/status`, { presence: p.presence, status_msg: p.status });
}

// #general: an evening in the house.
const g = rooms.general;
await say("kenji", g, "anyone up for kart night later?"); await beat();
await say("theo", g, "always. I'm warming up the controller"); await beat();
await say("bia", g, "I'll be in the Lounge after dinner 🍜"); await beat();
const open = await say("priya", g, "Lounge is open, I'm on the decks tonight 🎧");
await react("maya", g, open, "🔥");
await react("theo", g, open, "🔥");
await react("jonas", g, open, "🎶");
await beat();
const kart = await upload("jonas", `${WORK}/media/kart-win.png`, "image/png");
const picture = await send("jonas", g, "m.room.message", {
  msgtype: "m.image", body: "kart-win.png", url: kart.mxc, info: { mimetype: "image/png", size: kart.size, w: 1280, h: 720 },
});
await react("bia", g, picture, "😂");
await react("kenji", g, picture, "😂");
await react("maya", g, picture, "🏆");
await say("jonas", g, "first place, no items, no mercy"); await beat();
const corner = await reply("kenji", g, picture, "how did you even take that last corner"); await beat();
await reply("jonas", g, corner, "trade secret 🤫"); await beat();
const drift = await say("bia", g, "that last drift was illegal");
await react("theo", g, drift, "😂");
await react("priya", g, drift, "💯");
await beat();
const poll = await send("theo", g, "org.matrix.msc3381.poll.start", {
  "org.matrix.msc3381.poll.start": {
    kind: "org.matrix.msc3381.poll.disclosed", max_selections: 1,
    question: { "org.matrix.msc1767.text": "What are we playing Friday?" },
    answers: [
      { id: "kart", "org.matrix.msc1767.text": "Kart night (again)" },
      { id: "co-op", "org.matrix.msc1767.text": "Co-op survival" },
      { id: "party", "org.matrix.msc1767.text": "Party games" },
    ],
  },
  "org.matrix.msc1767.text": "What are we playing Friday?\n1. Kart night (again)\n2. Co-op survival\n3. Party games",
});
for (const [u, answer] of [["maya", "kart"], ["jonas", "kart"], ["bia", "party"], ["kenji", "kart"], ["priya", "co-op"], ["lou", "kart"]]) {
  await send(u, g, "org.matrix.msc3381.poll.response", {
    "m.relates_to": { rel_type: "m.reference", event_id: poll },
    "org.matrix.msc3381.poll.response": { answers: [answer] },
  });
}
await beat();
await say("maya", g, "rematch in the Lounge in 10. loser picks the next song"); await beat();
await say("theo", g, "Maya you're on snacks, you lost last time", {
  format: "org.matrix.custom.html",
  formatted_body: `<a href="https://matrix.to/#/${mx("maya")}">Maya</a> you're on snacks, you lost last time`,
  "m.mentions": { user_ids: [mx("maya")] },
});
await beat();
await say("lou", g, "kart night (again) (again) (again)");

// The other channels' last messages, for the lists that preview them.
await say("priya", rooms.music, "tonight's set: Sunrise Strut, Coffee Run, Neon Hen. requests open");
await say("theo", rooms.music, "Late Checkout please, it's a vibe");
await say("bia", rooms.memes, "me explaining federation to my mom: it's like email but for hanging out");
await say("kenji", rooms.clips, "posting the drift in a sec");
await state("theo", rooms.gameNight, "chat.commet.voice_channel_status", "", { status: "Kart Night, lap 2" });

// A DM from Theo.
const dm = await api(as("theo"), "POST", "/_matrix/client/v3/createRoom", { preset: "trusted_private_chat", is_direct: true, invite: [mx("maya")] });
await join("maya", dm.room_id);
await api(as("maya"), "PUT", `/_matrix/client/v3/user/${encodeURIComponent(mx("maya"))}/account_data/m.direct`, { [mx("theo")]: [dm.room_id] });
await api(as("theo"), "PUT", `/_matrix/client/v3/user/${encodeURIComponent(mx("theo"))}/account_data/m.direct`, { [mx("maya")]: [dm.room_id] });
await say("theo", dm.room_id, "you coming? the Lounge is packed");
await say("maya", dm.room_id, "two minutes, grabbing water");
await say("theo", dm.room_id, "Priya queued your song 👀");

// The Coop's own soundboard (MatrixSpaceSoundboardComponent: one state
// event per sound), next to the six every call has.
for (const [id, name, emoji, durationMs] of [["rematch", "Rematch?", "🔁", 587], ["gg", "GG", "🏁", 927], ["drumroll", "Drumroll", "🥁", 2407], ["sad-trombone", "Sad trombone", "🎺", 1957]]) {
  const { mxc } = await upload("maya", `${WORK}/sounds/${id}.ogg`, "audio/ogg");
  await state("maya", coop, "chat.commet.soundboard.sound", id, {
    sound_id: id, name, emoji, media_uri: mxc, mimetype: "audio/ogg", duration_ms: durationMs,
    normalized_gain_milli: 1000, volume_milli: 1000, version: 1,
  });
}

fs.writeFileSync(`${WORK}/seed.json`, JSON.stringify({ users, rooms }, null, 2));
console.log("seeded the crew; tokens and room ids in", `${WORK}/seed.json`);
