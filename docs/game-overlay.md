# In-game overlay

Request (2026-10-11): an in-game overlay like Discord's, without tripping
anticheats; some games with heavy anticheat flag overlays.

While a game runs fullscreen or borderless on Windows, Rooster shows who is
in the call (whoever is talking fully drawn with a green ring, everyone
else at 30% so the game shows through, and a slashed microphone or headset
at full strength on whoever is muted or deafened), and the messages that would
notify, as small dark pills in a corner of the game's screen. Clicks go
through them to the game. Settings, App, Overlay turns it off, picks the
corners, keeps the list to who is talking, or turns messages off.

## How it stays clear of anticheats

Discord's old overlay injected a DLL into the game and drew in its
`Present` call; anticheats whitelist Discord for that, and would not
whitelist us. Its new one (2024) and NVIDIA's and Overwolf's newer ones are
separate windows over the game, and so is this. What anticheats look for,
from the research behind this (vendor docs, published reverse engineering
of EAC, BattlEye and Call of Duty's TAC), and what Rooster does instead:

| Anticheats flag | Rooster |
| --- | --- |
| A DLL injected into the game, or a graphics hook (`Present`) | Draws in its own windows, in its own process |
| A global `SetWindowsHookEx` hook (loads into every process) | One `SetWinEventHook(EVENT_SYSTEM_FOREGROUND, WINEVENT_OUTOFCONTEXT)`: Windows tells Rooster's thread; nothing is loaded anywhere |
| A handle to the game's process (`OpenProcess`, even with limited rights) or reading its memory | Reads only the foreground window's style, rectangle and class, as any window manager does. It never opens the game |
| A window hidden from capture (`WDA_EXCLUDEFROMCAPTURE`), which is how ESP cheats hide from screenshots | Not hidden: a capture of the whole screen shows the overlay |
| A transparent topmost window covering most of the game (TAC checks half of it) | Small windows sized to what they show, at most 2048 px a side |
| Nameless or random window names | Class `RoosterOverlayWindow`, title "Rooster Overlay" |

Keep it that way. In particular:

- Never call `OpenProcess` on the foreground window's process, not even to
  read its exe name for a per-game list. If that is ever needed, match the
  pid against `CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS)`, which opens
  nothing.
- Never set a display affinity on the overlay windows.
- Hotkeys go through `RegisterHotKey` (`hotkey_manager`), not a low-level
  keyboard hook, which some anticheats kick for (BattlEye, FACEIT).

No anticheat vendor publishes a policy for separate overlay windows, and a
few games block every third-party overlay. BattlEye's FAQ says non-cheat
overlays are generally supported and that it only bans for actual cheats.
Rooster's builds are not code-signed, which the research rates a minor,
indirect risk (some anticheats look closer at unsigned modules in a process
that owns a window over the game).

## When it shows

`FullscreenWindowInFront` (`rooster/windows/runner/game_overlay.cpp`): the
foreground window fills its monitor, has no title bar (which rules out a
maximized window with an auto-hidden taskbar), and is not Rooster's own or
the desktop. Anything fullscreen counts, a video in a browser too: Rooster
cannot tell a game from it without reading the process.

Not over a game in **exclusive fullscreen**
(`SHQueryUserNotificationState` says `QUNS_RUNNING_D3D_FULL_SCREEN`, or
cannot say): no other window shows there, and a DXGI game can give up
fullscreen when one covers it. Most games today run borderless, or get
Windows' fullscreen optimizations, which make "fullscreen" borderless; the
setting's description tells people to switch a game to borderless. Over a
borderless game, DWM composes the overlay with it, which can cost the game
independent flip (a frame of latency) on GPUs without multiplane overlays,
the same as Discord's and NVIDIA's overlays.

Nor over a screen saver or a locked screen (`QUNS_NOT_PRESENT`: nobody is
looking, and messages would sit there for anyone passing), nor in Windows'
presentation mode (`QUNS_PRESENTATION_MODE`, which exists to hold pop-ups
back).

The runner checks again on every foreground change and once a second (a
game going fullscreen, or exclusive, while it has the focus), and hides the
panels at once when the game loses the focus. The once-a-second check also
raises the panels over the game again: a topmost game that applies its
video settings, or gets the focus back between two checks, goes back to the
top of the topmost windows without the foreground changing.

## How it is drawn

| Piece | Where |
| --- | --- |
| The windows, the foreground check, the layout | `rooster/windows/runner/game_overlay.{h,cpp}` |
| What the panels say, when to show them | `rooster/lib/utils/game_overlay/game_overlay.dart` |
| The pills and toasts | `rooster/lib/utils/game_overlay/overlay_painter.dart` |
| Who is in the call, talking, muted | `rooster/lib/utils/voice_controls/call_members.dart` |
| Names and avatars | `rooster/lib/utils/voice_controls/call_faces.dart` |
| Settings | `rooster/lib/ui/pages/settings/categories/app/game_overlay_settings_page.dart` |

- Dart draws each panel with a `Canvas` (no widget tree), as the taskbar
  buttons are drawn, at the game's screen's DPI, and sends premultiplied
  RGBA (`ImageByteFormat.rawRgba`). The runner swaps it to BGRA and hands it
  to `UpdateLayeredWindow`. Drawing works with Rooster minimized or in the
  tray; this was measured before the rest was built.
- The windows are `WS_EX_LAYERED | WS_EX_TRANSPARENT` (clicks go through),
  `WS_EX_TOPMOST`, `WS_EX_NOACTIVATE` (taking the focus would minimize a
  fullscreen game), `WS_EX_TOOLWINDOW` (no taskbar button or Alt+Tab
  entry), and have no owner, so they stay when Rooster's window is hidden.
  They are raised again over the game when it comes to the front.
- The call is read every 200 ms while a game is in front, the rate LiveKit
  reports who is talking at, and a panel is drawn again only when what it
  says changes. Nothing runs while no game is in front.
- Messages: `NotificationManager.notify` hands every message notification
  it is about to show to `GameOverlay.showMessage`, which never throws or
  waits. Windows' Focus Assist holds its own toasts back during games, so
  this is how they are seen. Three at most, six seconds each.
- Which messages, under Settings, App, Overlay: four kinds, each with its
  own toggle, and a message shows when any kind it is is on.
  - Direct messages.
  - Mentions of us and our keywords: the push rules' `highlight`, which
    `MatrixRoom.handleNotification` puts on the notification
    (`mentionsMe`).
  - The channel of our call: every message sent there, whether it would
    notify or not. On each read of the call (every 200 ms) the overlay
    looks at the channel's newest message (`Room.lastMessage`); the first
    look over a game only notes where the channel is, so nothing older
    shows. A burst within 200 ms shows its last message.
  - Everything else that notifies: rooms set to notify of every message, in
    every space and account.
  A message that comes both ways (the call's channel, and its notification)
  shows once.
- **Screen sharing**: messages are not shown while we share our screen.
  The overlay is not hidden from capture, so a share of the whole screen
  would carry them to everyone watching. The list of the call still shows;
  a share of the game's window alone never has the overlay in it. OBS's
  display capture records it too.

## The browser

A page cannot draw over other apps. The nearest thing is the floating call
controls panel (Document Picture-in-Picture, `docs/voice-controls.md`),
which stays over other windows, a borderless game's included: it now lists
who is in the call, with the same green ring and badges, above its
buttons. Unlike the native overlay it is opaque, takes the focus when
clicked, and only opens from a click (or Chrome leaving the tab mid-call).
Chrome slows the tab's timers once it is hidden, so who is talking may
update once a second there rather than five times.

## Not done

- Linux and macOS. Discord's overlay is Windows only too. Wayland gives an
  app no way to stay over another one (layer-shell aside, which GNOME
  lacks); X11 and macOS could take the same small windows.
- Discord's interactive overlay (Shift+\` to chat over the game). It takes
  the keyboard from the game, and Flutter cannot draw a second interactive
  window yet.
- Windowed games: the overlay only knows a game by its filling the screen.
