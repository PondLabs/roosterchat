// The demo video's screens that the landing page doesn't have
// (docs/brand/demo): Lou's camera in the call, Jonas's stream full screen,
// and Maya's noise suppression setting with its live meter, on and off,
// while her microphone hears someone typing. The call is set up as
// capture.mjs sets it up. Run services.sh and seed.mjs first.
//
//   ROOSTER_CAMERA=clip.y4m ROOSTER_NOISY_MIC=noisy_48k.wav node capture-video.mjs
//
// The camera clip and the noisy recording are made by the demo's own
// tooling (docs/brand/README.md, "Demo videos").
import fs from "node:fs";
import {
  CAPS, SONGS, WORK, button, callBar, close, hide, joinLounge, labels, log, open, people, settle, shot, show,
  toggleMic, until, wait,
} from "./crew.mjs";

const CAMERA = process.env.ROOSTER_CAMERA;
const NOISY = process.env.ROOSTER_NOISY_MIC;
if (!CAMERA || !NOISY) throw new Error("set ROOSTER_CAMERA and ROOSTER_NOISY_MIC");

// Unlabelled buttons, by where and how big they are.
const buttonsAt = (page, test) => page.evaluate((test) => [...document.querySelectorAll('flt-semantics [role="button"]')]
  .filter((e) => !(e.getAttribute("aria-label") || e.textContent || "").trim())
  .map((e) => { const r = e.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2, w: r.width, h: r.height }; })
  .filter(new Function("b", `return ${test}`)), test);

async function run() {
  fs.mkdirSync(CAPS, { recursive: true });

  log("opening the crew");
  for (const u of ["theo", "kenji", "bia"]) { await open(u); await joinLounge(u); await hide(u); }
  await open("lou", { camera: CAMERA });
  await joinLounge("lou");
  await hide("lou");
  await open("priya");
  await joinLounge("priya");
  await open("jonas", { fakeScreen: "/kart.webm" });
  await joinLounge("jonas");
  await hide("jonas");
  for (const u of ["lou", "bia", "jonas", "priya"]) {
    await toggleMic(u);
    if (u !== "priya") await hide(u);
  }

  // Priya on the decks, as on the landing page.
  {
    const page = people.priya.page;
    await callBar(page);
    await button(page, "DJ booth").click();
    await wait(2500);
    if (await button(page, "Take the decks").count()) {
      await button(page, "Take the decks").click();
      await wait(2500);
    }
    const [chooser] = await Promise.all([page.waitForEvent("filechooser"), button(page, "Choose files").click()]);
    await chooser.setFiles(SONGS.map((s) => `${WORK}/audio/${s}.ogg`));
    await wait(3000);
    await button(page, "Close the DJ booth").click().catch(() => {});
    await hide("priya");
  }

  // Jonas shares Kart Night.
  await show("jonas");
  await wait(1000);
  await button(people.jonas.page, "Share your screen").click();
  await wait(6000);
  await hide("jonas");

  // Lou puts his camera on: the fourth button of the call's bar.
  {
    await show("lou");
    const page = people.lou.page;
    await callBar(page);
    // (the sidebar's own call panel sits lower on the left: x > 340 skips it)
    const bar = (await buttonsAt(page, `b.y > ${page.viewportSize().height - 120} && b.x > 340 && b.w > 30 && b.w < 60`))
      .sort((a, b) => a.x - b.x);
    if (process.env.DEBUG) log("lou's call bar:", JSON.stringify(bar));
    // Unlabelled, left to right: share, microphone, headphones, camera,
    // hang up (the soundboard and DJ buttons have labels).
    await page.mouse.click(bar[3].x, bar[3].y);
    await wait(6000);
    await shot(page, "lou-camera");
    await hide("lou");
  }

  // Maya, on a laptop, her microphone hearing someone type.
  log("Maya joins");
  const maya = await open("maya", { width: 1512, height: 891, scale: 2, mic: NOISY });
  await joinLounge("maya");
  await until(maya, (l) => l === "Watch stream");
  await button(maya, "Watch stream").click();
  await settle(maya, 6000);
  await shot(maya, "call-camera");

  // Jonas's stream, full screen.
  const full = await buttonsAt(maya, "b.w > 44 && b.w < 52 && b.h > 44 && b.h < 52 && b.x > 300");
  if (process.env.DEBUG) log("48 px buttons:", JSON.stringify(full));
  // One per video in the call (Lou's camera, Jonas's stream): each is
  // captured, and the video uses Jonas's.
  for (const [i, b] of full.entries()) {
    await maya.mouse.move(b.x - 200, b.y + 60);
    await wait(500);
    await maya.mouse.click(b.x, b.y);
    await settle(maya, 4000);
    await shot(maya, `call-fullscreen-${i}`);
    if (await button(maya, "Exit fullscreen").count()) await button(maya, "Exit fullscreen").click();
    else await maya.keyboard.press("Escape");
    await wait(2500);
  }

  // Her settings: Voice and Video, noise suppression with the meter live.
  const gear = (await buttonsAt(maya, `b.y > ${maya.viewportSize().height - 60} && b.x < 300`)).sort((a, b) => b.x - a.x)[0];
  await maya.mouse.click(gear.x, gear.y);
  await wait(2500);
  if (await button(maya, "App Settings").count()) { await button(maya, "App Settings").click(); await wait(1500); }
  await button(maya, "Voice and Video").click();
  await wait(2500);
  if (process.env.DEBUG) log("settings:", (await labels(maya)).filter(Boolean).join(" | "));
  const toggle = maya.locator('flt-semantics [role="switch"], flt-semantics [role="checkbox"], flt-semantics input[type="checkbox"]');
  const ns = await maya.evaluate(() => [...document.querySelectorAll("flt-semantics [role], flt-semantics input")]
    .find((e) => (e.getAttribute("aria-label") || e.textContent || "").includes("Noise suppression"))?.getBoundingClientRect().y);
  if (ns != null) { await maya.mouse.move(900, 500); await maya.mouse.wheel(0, ns - 200); await wait(1500); }
  log("switches:", await toggle.count());
  const frames = async (name) => {
    for (let i = 0; i < 16; i++) { await maya.screenshot({ path: `${CAPS}/${name}-${String(i).padStart(2, "0")}.png` }); await wait(150); }
    log("captured", name);
  };
  await settle(maya, 2000);
  await frames("ns-on");
  // The switch on the noise suppression row: the one level with its title.
  const sw = await maya.evaluate(() => {
    const title = [...document.querySelectorAll("flt-semantics *")]
      .filter((e) => (e.getAttribute("aria-label") || e.textContent || "").trim().startsWith("Noise suppression"))
      .map((e) => e.getBoundingClientRect()).sort((a, b) => a.height - b.height)[0];
    const switches = [...document.querySelectorAll('flt-semantics [role="switch"], flt-semantics [role="checkbox"], flt-semantics input[type="checkbox"]')]
      .map((e) => e.getBoundingClientRect());
    if (!title) return null;
    const y = title.y + title.height / 2;
    return switches.sort((a, b) => Math.abs(a.y + a.height / 2 - y) - Math.abs(b.y + b.height / 2 - y))[0];
  });
  log("noise suppression switch:", JSON.stringify(sw));
  if (sw) {
    await maya.mouse.click(sw.x + sw.width / 2, sw.y + sw.height / 2);
    await settle(maya, 2000);
    await frames("ns-off");
    await maya.mouse.click(sw.x + sw.width / 2, sw.y + sw.height / 2);
  }

  for (const user of Object.keys(people)) await close(user);
  log("done:", fs.readdirSync(CAPS).join(", "));
}

try {
  await run();
} catch (e) {
  for (const [user, { page }] of Object.entries(people)) {
    await page.screenshot({ path: `${CAPS}/error-${user}.png` }).catch(() => {});
  }
  console.error(e);
  console.error(`Stopped. What each window showed is in ${CAPS}/error-*.png.`);
  for (const user of Object.keys(people)) await close(user).catch(() => {});
  process.exit(1);
}
