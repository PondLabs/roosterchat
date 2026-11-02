// The landing page's behaviour. Everything here only writes data-* attributes
// and CSS custom properties that style.css reads; without this file the page
// is complete and still, with every download link going to the releases page.
(() => {
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const finePointer = matchMedia("(hover: hover) and (pointer: fine)").matches;

  // The words this file writes, in the page's language (index.html, and its
  // Brazilian Portuguese twin in pt-br/).
  const TEXT = {
    en: {
      downloadFor: (os) => `Download for ${os}`,
      openApp: "Open Rooster",
      armSetup: "arm64 · setup script",
      useLight: "Use the light theme",
      useDark: "Use the dark theme",
    },
    pt: {
      downloadFor: (os) => `Baixar para ${os}`,
      openApp: "Abrir o Rooster",
      armSetup: "arm64 · script de instalação",
      useLight: "Usar o tema claro",
      useDark: "Usar o tema escuro",
    },
  };
  const text = document.documentElement.lang.startsWith("pt") ? TEXT.pt : TEXT.en;

  // ------------------------------------------------------------- theme
  // Light or dark: the system's, until someone picks one with the header's
  // button; the choice is kept in this browser and applied before the first
  // paint by the script in <head>. style.css reads data-theme.
  const THEME_KEY = "rooster.theme";
  const THEME_COLOR = { light: "#F7EDE1", dark: "#1B1613" };
  const systemDark = matchMedia("(prefers-color-scheme: dark)");
  const toggle = document.querySelector("[data-theme-toggle]");
  const theme = () => document.documentElement.dataset.theme ?? (systemDark.matches ? "dark" : "light");
  const paintTheme = () => {
    const dark = theme() === "dark";
    toggle?.setAttribute("aria-pressed", String(dark));
    if (toggle) toggle.title = dark ? text.useLight : text.useDark;
    // A choice of ours overrides the system's colour for the browser's bar.
    if (document.documentElement.dataset.theme) {
      for (const meta of document.querySelectorAll('meta[name="theme-color"]')) meta.content = THEME_COLOR[theme()];
    }
  };
  toggle?.addEventListener("click", () => {
    const next = theme() === "dark" ? "light" : "dark";
    document.documentElement.dataset.theme = next;
    try {
      localStorage.setItem(THEME_KEY, next);
    } catch {}
    paintTheme();
  });
  systemDark.addEventListener("change", paintTheme);
  paintTheme();

  // The other language's page opens at the same section.
  for (const link of document.querySelectorAll("[data-lang-switch]")) {
    link.addEventListener("click", () => {
      if (location.hash) link.href = link.getAttribute("href").split("#")[0] + location.hash;
    });
  }

  // ------------------------------------------------------------ header
  // The header turns solid once the top of the page leaves the screen.
  const sentinel = document.querySelector(".top-sentinel");
  if (sentinel && "IntersectionObserver" in window) {
    new IntersectionObserver(([entry]) => {
      document.body.toggleAttribute("data-scrolled", !entry.isIntersecting);
    }).observe(sentinel);
  }

  // ------------------------------------------------------------ reveal
  // Blocks marked data-reveal wait off screen (pending) and come in when
  // they enter (shown), from below or from above, as often as they pass.
  // Blocks that enter together get a growing --offset and arrive one after
  // the other. What's on screen when the page opens never waits.
  if (!reducedMotion && "IntersectionObserver" in window) {
    const BATCH_MS = 380;
    const sideOf = (rect) => (rect.top < 0 ? "top" : "bottom");
    const hide = (el, side) => {
      el.dataset.revealState = "pending";
      el.dataset.revealFrom = side;
      el.style.removeProperty("--offset");
    };
    const observer = new IntersectionObserver((entries) => {
      const shown = entries
        .filter((e) => e.isIntersecting)
        .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
      shown.forEach((entry, position) => {
        const el = entry.target;
        if (shown.length > 1) el.style.setProperty("--offset", `${position * BATCH_MS}ms`);
        const rect = entry.boundingClientRect;
        const side = rect.top < 0 ? "top" : rect.bottom > innerHeight ? "bottom" : el.dataset.revealFrom || "bottom";
        if (el.dataset.revealFrom !== side) {
          el.dataset.revealFrom = side;
          void el.offsetHeight;
        }
        el.dataset.revealState = "shown";
      });
      for (const entry of entries) {
        if (!entry.isIntersecting) hide(entry.target, sideOf(entry.boundingClientRect));
      }
    }, { rootMargin: "0px 0px -8% 0px" });

    const blocks = [...document.querySelectorAll("[data-reveal]")].map((el) => ({ el, rect: el.getBoundingClientRect() }));
    for (const { el, rect } of blocks) {
      if (rect.top >= innerHeight || rect.bottom <= 0) hide(el, sideOf(rect));
      observer.observe(el);
    }
  }

  // ----------------------------------------------------- pointer effects
  // The hero's stage tilts toward the pointer, and the main button leans a
  // little toward it. Only with a fine pointer that hovers, never on touch.
  if (finePointer && !reducedMotion) {
    const track = (el, onMove, onLeave) => {
      let rect = null;
      el.addEventListener("pointerenter", () => { rect = el.getBoundingClientRect(); });
      el.addEventListener("pointermove", (e) => {
        rect ??= el.getBoundingClientRect();
        onMove(e.clientX - rect.left, e.clientY - rect.top, rect);
      }, { passive: true });
      el.addEventListener("pointerleave", () => { rect = null; onLeave(); });
    };
    const clamp = (v, limit) => Math.max(-limit, Math.min(limit, v));

    for (const stage of document.querySelectorAll("[data-tilt]")) {
      const tilt = stage.querySelector(".tilt") ?? stage;
      track(stage, (x, y, rect) => {
        const max = 7;
        tilt.style.setProperty("--rx", `${(clamp(x / rect.width - 0.5, 0.5) * 2 * max).toFixed(2)}deg`);
        tilt.style.setProperty("--ry", `${(-clamp(y / rect.height - 0.5, 0.5) * 2 * max).toFixed(2)}deg`);
      }, () => {
        tilt.style.setProperty("--rx", "0deg");
        tilt.style.setProperty("--ry", "0deg");
      });
    }

    for (const button of document.querySelectorAll("[data-magnet]")) {
      track(button, (x, y, rect) => {
        button.style.setProperty("--mx", `${clamp((x - rect.width / 2) * 0.22, 10).toFixed(1)}px`);
        button.style.setProperty("--my", `${clamp((y - rect.height / 2) * 0.22, 10).toFixed(1)}px`);
      }, () => {
        button.style.setProperty("--mx", "0px");
        button.style.setProperty("--my", "0px");
      });
    }
  }

  // -------------------------------------------------------- active step
  // The reading line is 40% down the window. A step is reached once its
  // marker has crossed it (its marker fills with comb red, and the stage's
  // progress mark with it); the current step is the last one reached, whose
  // screenshot the stage shows. Before any, the stage shows the first.
  if ("IntersectionObserver" in window) {
    for (const list of document.querySelectorAll("[data-steps]")) {
      const section = list.closest("section");
      const steps = [...list.querySelectorAll("[data-step]")];
      const items = [...section.querySelectorAll("[data-stage-item]")];
      const marks = [...section.querySelectorAll("[data-stage-progress]")];
      const flag = (el, name, on) => (on ? el.setAttribute(name, "") : el.removeAttribute(name));
      const observer = new IntersectionObserver((entries) => {
        for (const entry of entries) {
          const step = entry.target.closest("[data-step]");
          flag(step, "data-reached", entry.isIntersecting || entry.boundingClientRect.top < 0);
        }
        const reached = steps.map((s) => s.hasAttribute("data-reached"));
        const current = reached.lastIndexOf(true);
        steps.forEach((s, i) => flag(s, "data-current", i === current));
        items.forEach((s, i) => flag(s, "data-current", i === Math.max(0, current)));
        marks.forEach((s, i) => flag(s, "data-reached", reached[i] ?? false));
      }, { rootMargin: "400% 0px -60% 0px" });
      for (const marker of list.querySelectorAll("[data-step-marker]")) observer.observe(marker);
    }
  }

  // ----------------------------------------------------------- downloads
  // Point every download at the latest release's own file, and the hero's
  // button at the one for this computer. Offline or rate limited, they all
  // keep going to the releases page, which works too.
  const ua = navigator.userAgent;
  const phone = /Android|iPhone|iPad|iPod/i.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
  const os = phone ? null : /Windows/.test(ua) ? "windows" : /Mac/.test(ua) ? "macos" : /Linux|X11|CrOS/.test(ua) ? "linux" : null;
  const names = { windows: "Windows", macos: "macOS", linux: "Linux" };
  const primary = document.getElementById("primary-download");

  if (phone && primary) {
    // No phone build yet: the browser version is the way in.
    primary.textContent = text.openApp;
    primary.href = primary.nextElementSibling?.getAttribute("href") ?? "app/";
    primary.nextElementSibling?.remove();
  } else if (os && primary) {
    primary.textContent = text.downloadFor(names[os]);
    document.querySelector(`.dl[data-os="${os}"]`)?.classList.add("mine");
  }

  const archOf = async () => {
    try {
      const data = await navigator.userAgentData?.getHighEntropyValues?.(["architecture", "bitness"]);
      if (data?.architecture === "arm") return "arm64";
      if (data?.architecture === "x86") return "x64";
    } catch {}
    return /aarch64|arm64/i.test(ua) ? "arm64" : "x64";
  };

  Promise.all([
    fetch("https://api.github.com/repos/PondLabs/roosterchat/releases/latest").then((r) => (r.ok ? r.json() : Promise.reject(r.status))),
    archOf(),
  ]).then(([release, arch]) => {
    const find = (end) => release.assets.find((a) => a.name.endsWith(end))?.browser_download_url;
    const linuxArch = os === "linux" ? arch : "x64";
    const files = {
      windows: [find("-windows-x64-setup.exe"), find("-windows-x64-release.zip")],
      macos: [find("-macos-universal.dmg"), find("-macos-universal-release.zip")],
      linux: [find(`-linux-${linuxArch}-setup.sh`), find(`-linux-${linuxArch}-release.tar.gz`)],
    };
    for (const [key, [main, alt]] of Object.entries(files)) {
      const card = document.querySelector(`.dl[data-os="${key}"]`);
      const other = document.querySelector(`[data-alt="${key}"]`);
      if (card && main) card.href = main;
      if (other && alt) other.href = alt;
      if (key === os && primary && main) primary.href = main;
    }
    if (linuxArch === "arm64") {
      const label = document.querySelector("[data-arch-label]");
      if (label) label.textContent = text.armSetup;
    }
    const version = document.getElementById("version");
    if (version && release.tag_name) {
      version.textContent = release.tag_name;
      version.hidden = false;
    }
  }).catch(() => {});
})();
