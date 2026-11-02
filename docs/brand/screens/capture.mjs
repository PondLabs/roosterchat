// Takes the landing page's screenshots from the real web app: the call is
// set up the way the page shows it, then Maya's screens are captured on a
// laptop and a phone, and Priya's at the decks. Captures go to
// $ROOSTER_SHOTS/caps; export.py turns them into the page's images. Run
// services.sh and seed.mjs first.
import fs from "node:fs";
import {
  CAPS, SONGS, WORK, button, callBar, close, closeMenu, goToSpace, hide, joinLounge, labels, log, open,
  openChannel, openMenuOf, people, settle, shot, show, toggleMic, until, wait,
} from "./crew.mjs";

async function run() {
  fs.mkdirSync(CAPS, { recursive: true });

  // --- The Lounge fills up. Priya's tab is laptop sized at 2x, for her own
  // capture at the decks later.
  log("opening the crew");
  await Promise.all(["theo", "kenji", "lou", "bia"].map(async (u) => { await open(u); await joinLounge(u); await hide(u); }));
  await open("priya", { width: 1512, height: 891, scale: 2 });
  await joinLounge("priya");
  await open("jonas", { fakeScreen: "/kart.webm" });
  await joinLounge("jonas");
  await hide("jonas");
  for (const u of ["lou", "bia", "jonas", "priya"]) {
    await toggleMic(u);
    if (u !== "priya") await hide(u);
  }

  // --- Priya takes the decks and queues four songs, Sunrise Strut first.
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
    for (let i = 0; i < 4 && !(await labels(page)).some((l) => l.startsWith("DJ · playing The Night Owls")); i++) {
      await button(page, "Next song").click();
      await wait(2500);
    }
    // Her own view of the booth, a little way into the first song.
    await settle(page, 20000);
    await shot(page, "priya-dj");
    await hide("priya");
  }

  // --- Maya, on a laptop.
  log("Maya joins");
  const maya = await open("maya", { width: 1512, height: 891, scale: 2 });
  await joinLounge("maya");
  await settle(maya, 6000);
  await shot(maya, "call");

  await toggleMic("bia");
  await hide("bia");
  await show("jonas");
  await wait(1000);
  await button(people.jonas.page, "Share your screen").click();
  await wait(6000);
  await hide("jonas");
  await show("maya");
  await until(maya, (l) => l === "Watch stream");
  await button(maya, "Watch stream").click();
  await settle(maya, 5000);
  await shot(maya, "call-share");

  await button(maya, "Open sound effects").click();
  await wait(2500);
  await settle(maya, 800);
  await shot(maya, "call-soundboard");
  await maya.keyboard.press("Escape");
  await wait(1200);

  await callBar(maya);
  await button(maya, "DJ booth").click();
  await settle(maya, 3000);
  await shot(maya, "call-dj-listener");
  await button(maya, "Close the booth").click();
  await wait(1000);

  // #general, at the bottom (the laptop's screen) and a little way up (the
  // tour).
  await openChannel(maya, "general");
  await until(maya, (l) => l.includes("trade secret"));
  await maya.mouse.move(1000, 600);
  await maya.mouse.wheel(0, 3000);
  await settle(maya, 2500);
  await shot(maya, "chat");
  await maya.mouse.move(1000, 500);
  await maya.mouse.wheel(0, -380);
  await settle(maya, 2500);
  await shot(maya, "chat-up");

  // The Coop's home, from the banner over the channel list.
  await maya.mouse.click(160, 50);
  await settle(maya, 3000);
  await shot(maya, "space");

  // Theo's menu in the call, his voice turned down. The tiles have no
  // labels: right click each until the menu that opens is Theo's.
  await openChannel(maya, "Lounge");
  await wait(3000);
  const volume = await openMenuOf(maya, "Theo");
  if (volume) {
    const slider = await maya.evaluate(() => [...document.querySelectorAll('flt-semantics [role="slider"]')]
      .map((e) => e.getBoundingClientRect()).sort((a, b) => a.y - b.y)[0]);
    const from = slider.x + slider.width - 25;
    await maya.mouse.move(from, slider.y + slider.height / 2);
    await maya.mouse.down();
    await maya.mouse.move(from - 54, slider.y + slider.height / 2, { steps: 8 });
    await maya.mouse.up();
    await wait(1200);
    await shot(maya, "volume");
    // The menu opens above or below the tile, wherever there's room: the
    // card is cut around its first slider.
    const crop = [Math.round(slider.x - 118), Math.round(slider.y - 99), 330, 220];
    const menu = (await labels(maya)).find((l) => / Sound effects /.test(l));
    fs.writeFileSync(`${CAPS}/volume.json`, JSON.stringify({ crop, menu }));
    log("volume menu:", menu);
    await closeMenu(maya);
  } else {
    await shot(maya, "error-volume");
    log("Theo's tile not found: no volume capture (what the call looked like: error-volume.png)");
  }

  // --- Maya again, on a phone: the same account, a phone-sized window.
  log("Maya on a phone");
  await close("maya");
  const phone = await open("maya", { width: 402, height: 812, scale: 2, mobile: true });
  await wait(3000);
  await phone.mouse.click(30, 25);
  await wait(2500);
  await shot(phone, "phone-around");
  await button(phone, "Join call").click();
  await until(phone, (l) => l.startsWith("DJ · playing"));
  await until(phone, (l) => l === "Watch stream");
  await button(phone, "Watch stream").click();
  await wait(5000);
  await shot(phone, "phone-call");
  await phone.mouse.click(30, 25);
  await wait(1800);
  await goToSpace(phone, "The Coop");
  await button(phone, "general").click();
  await until(phone, (l) => l.includes("kart night (again) (again)"));
  await wait(2500);
  await shot(phone, "phone-chat");

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
