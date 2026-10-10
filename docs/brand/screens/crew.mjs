// The made-up crew, each in their own Chrome with the real web app: what
// capture.mjs uses to set a scene up and capture it. One profile per person
// (kept, so later runs don't log in again) and one fake microphone each.
//
// The app is Flutter, drawn on a canvas: it is driven through its
// accessibility tree (flt-semantics), by the labels a screen reader would
// read, and by position where a control has no label.
import { createRequire } from "node:module";

export const WORK = process.env.ROOSTER_SHOTS ?? "/tmp/rooster-shots";
const { chromium } = createRequire(`${WORK}/node/`)("playwright-core");
const APP = "http://localhost:8090/";
const PASSWORD = "rooster-landing-demo";
export const CAPS = `${WORK}/caps`;
const VOICES = { maya: "mid", theo: "low", priya: "high", jonas: "low", bia: "high", kenji: "low", lou: "mid" };
export const SONGS = ["The Night Owls - Sunrise Strut", "Low Tide - Coffee Run", "Barnyard FM - Neon Hen", "Comb & Yolk - Late Checkout"];

export const wait = (ms) => new Promise((r) => setTimeout(r, ms));
export const people = {};
export const log = (...args) => console.log(new Date().toISOString().slice(11, 19), ...args);

export async function open(user, { width = 1280, height = 800, scale = 1, mobile = false, fakeScreen } = {}) {
  const ctx = await chromium.launchPersistentContext(`${WORK}/profiles/${user}`, {
    channel: "chrome", headless: true,
    viewport: { width, height }, deviceScaleFactor: scale, isMobile: mobile, hasTouch: mobile,
    colorScheme: "dark", locale: "en-US", timezoneId: "America/Denver",
    permissions: ["microphone", "camera", "notifications"],
    args: [
      // The JWT stand-in's certificate is self-signed.
      "--ignore-certificate-errors",
      "--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream",
      `--use-file-for-fake-audio-capture=${WORK}/audio/voice-${VOICES[user]}.wav`,
      "--autoplay-policy=no-user-gesture-required",
      // Hidden tabs keep their call going at full speed.
      "--disable-background-timer-throttling", "--disable-renderer-backgrounding", "--disable-backgrounding-occluded-windows",
    ],
  });
  // The made-up server name never leaves the machine: its well-known is
  // answered here, with the LiveKit focus, and anything else is dropped.
  await ctx.route(/^https?:\/\/the-coop\.social\//, (route) => route.request().url().endsWith("/.well-known/matrix/client")
    ? route.fulfill({
      status: 200, headers: { "Access-Control-Allow-Origin": "*", "Content-Type": "application/json" },
      body: JSON.stringify({ "m.homeserver": { base_url: "http://localhost:8008/" },
        "org.matrix.msc4143.rtc_foci": [{ type: "livekit", livekit_service_url: "https://localhost:8443" }] }),
    })
    : route.abort());
  // The screen Jonas shares: a looping video of kart.html, served with the
  // app so the stream it captures isn't cross-origin.
  if (fakeScreen) {
    await ctx.addInitScript((src) => {
      navigator.mediaDevices.getDisplayMedia = async () => {
        const video = Object.assign(document.createElement("video"), { src, loop: true, muted: true, playsInline: true });
        video.style.cssText = "position:fixed;left:-10000px;top:0;width:1280px;height:720px";
        document.body.appendChild(video);
        await video.play();
        return video.captureStream(30);
      };
    }, fakeScreen);
  }
  const page = ctx.pages()[0] ?? await ctx.newPage();
  page.on("pageerror", (e) => log(`[${user}]`, String(e).slice(0, 160)));
  await page.goto(APP);
  await page.waitForSelector("flt-semantics-placeholder", { state: "attached", timeout: 60000 });
  await page.evaluate(() => document.querySelector("flt-semantics-placeholder")?.click());
  // Logged in already (the profile remembers), or the login form. A first
  // login sets encryption up in wasm and takes minutes; later opens take
  // seconds.
  const field = (name) => page.locator(`flt-semantics input[aria-label="${name}"]`);
  let submitted = false;
  for (const end = Date.now() + 15 * 60000; ; await wait(1000)) {
    if (Date.now() > end) throw new Error(user + ": not logged in after 15 minutes");
    const ready = await page.evaluate(() => !document.querySelector('flt-semantics input[aria-label="Homeserver"]')
      && document.querySelectorAll('flt-semantics [role="button"]').length > 6);
    if (ready) break;
    // The form stays up, without its progress bar at times, until the
    // login is done: send it once.
    if (!submitted && await field("Homeserver").count()) {
      await field("Homeserver").click();
      await field("Homeserver").fill("http://localhost:8008");
      await page.keyboard.press("Enter");
      await field("Username").waitFor({ timeout: 30000 });
      await field("Username").fill(user);
      await field("Password").fill(PASSWORD);
      await button(page, "Login").click();
      submitted = true;
    }
  }
  people[user] = { ctx, page };
  return page;
}

export async function close(user) {
  await people[user]?.ctx.close();
  delete people[user];
}

export const button = (page, text) => page.locator('flt-semantics [role="button"]', { hasText: text }).first();
export const labels = (page) => page.evaluate(() => [...document.querySelectorAll("flt-semantics [role], flt-semantics input")]
  .map((e) => (e.getAttribute("aria-label") || e.textContent || "").replace(/\s+/g, " ").trim()));
export const until = async (page, test, timeout = 60000) => {
  for (const end = Date.now() + timeout; Date.now() < end; await wait(1000)) {
    if ((await labels(page)).some(test)) return true;
  }
  throw new Error("timed out waiting on " + test);
};

// Behind a blank tab, Flutter stops drawing and the call goes on: seven
// apps at once need the CPU for the one being captured.
export async function hide(user) {
  const { ctx, page } = people[user];
  const blank = ctx.pages().find((p) => p !== page && p.url() === "about:blank") ?? await ctx.newPage();
  await blank.bringToFront();
}
export const show = (user) => people[user].page.bringToFront();

// The space rail has no labels: click down it until the header names it.
export async function goToSpace(page, name) {
  for (const y of [107, 167, 227, 287, 347]) {
    await page.mouse.click(35, y);
    await wait(900);
    const header = await page.evaluate(() => [...document.querySelectorAll('flt-semantics [role="button"]')]
      .filter((e) => { const r = e.getBoundingClientRect(); return r.y < 5 && r.x > 60 && r.x < 80; })
      .map((e) => e.textContent.trim()));
    if (header.includes(name)) return;
  }
  throw new Error("no space called " + name);
}

// A channel in the sidebar, by its name. A voice channel's row grows with
// the people in its call, so it's clicked on its title, not its middle.
export async function openChannel(page, name) {
  const row = await page.evaluate((name) => [...document.querySelectorAll('flt-semantics [role="button"]')]
    .filter((e) => (e.getAttribute("aria-label") || e.textContent || "").trim().startsWith(name))
    .map((e) => e.getBoundingClientRect())
    .filter((r) => r.x > 60 && r.x < 100)[0], name);
  if (!row) throw new Error("no channel called " + name);
  await page.mouse.click(row.x + 60, row.y + 18);
}

export async function joinLounge(user) {
  const page = people[user].page;
  await goToSpace(page, "The Coop");
  await openChannel(page, "Lounge");
  await wait(2000);
  await button(page, "Join").click();
  await until(page, (l) => l.startsWith("DJ booth"));
}

// The microphone is the first button of the call panel in the sidebar.
export async function toggleMic(user) {
  const page = people[user].page;
  await show(user);
  await wait(1000);
  const mic = await page.evaluate(() => [...document.querySelectorAll('flt-semantics [role="button"]')]
    .map((e) => e.getBoundingClientRect())
    .filter((r) => r.y > innerHeight - 160 && Math.abs(r.x - 76) < 3 && Math.abs(r.width - 40) < 3)
    .map((r) => [r.x + r.width / 2, r.y + r.height / 2])[0]);
  if (!mic) throw new Error(user + ": no call panel");
  await page.mouse.click(mic[0], mic[1]);
  await wait(800);
}

// The call's own bar floats over the call and hides while the pointer is
// elsewhere, and with it its buttons: move over the call first.
export async function callBar(page) {
  const { width, height } = page.viewportSize();
  await page.mouse.move(width * 0.5, height * 0.5);
  await wait(300);
  await page.mouse.move(width * 0.5, height - 70);
  await wait(800);
}

export const settle = async (page, ms = 3000) => {
  await page.mouse.move(page.viewportSize().width - 60, page.viewportSize().height - 20);
  await wait(ms);
};
export const shot = async (page, name) => {
  await page.screenshot({ path: `${CAPS}/${name}.png` });
  log("captured", name);
};
// A person's menu in a call opens with a right click on their tile. Tiles
// have no labels, so each is tried until the menu is the wanted person's;
// gives back the point that opened it. The menu takes a moment to show up
// with seven apps running, so it's waited for, and so is its closing.
const MENU = / Sound effects \d+%/;
const openMenu = async (page) => (await labels(page)).find((l) => MENU.test(l));

export async function openMenuOf(page, name) {
  const tiles = await page.evaluate(() => [...document.querySelectorAll('flt-semantics [role="button"]')]
    .filter((e) => !(e.getAttribute("aria-label") || e.textContent || "").trim())
    .map((e) => e.getBoundingClientRect())
    .filter((r) => r.x > 300 && r.x + r.width < 1310 && r.y > 40 && r.width > 150 && r.height > 150)
    .map((r) => [Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2)]));
  for (const [x, y] of tiles) {
    await page.mouse.click(x, y, { button: "right" });
    let menu;
    for (let i = 0; i < 12 && !menu; i++) {
      await wait(500);
      menu = await openMenu(page);
    }
    if (process.env.DEBUG) log("tile", x, y, "menu:", menu ?? "none");
    if (menu?.startsWith(name + " ")) return [x, y];
    // Someone else's menu, or a screen share's (which has no sound effects
    // slider): close whatever opened.
    await page.mouse.click(page.viewportSize().width - 50, 60);
    for (let i = 0; i < 12 && await openMenu(page); i++) await wait(500);
  }
  return null;
}

// Context menus close on a click outside them. Not on the call (a click
// there can pick a tile) nor its header: on the members list's heading.
export async function closeMenu(page) {
  for (let i = 0; i < 3 && await openMenu(page); i++) {
    await page.mouse.click(page.viewportSize().width - 50, 60);
    await wait(1500);
  }
}
