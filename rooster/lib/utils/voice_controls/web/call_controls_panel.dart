// The call controls panel the browser floats over other windows (Document
// Picture-in-Picture), for issue #146. Plain DOM: Flutter cannot draw into a
// second document yet (flutter/flutter#181953). Nothing here imports
// Flutter, so the panel can be built into a test page on its own.
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// A button as the panel shows it.
class PanelButton {
  const PanelButton({
    required this.id,
    required this.active,
    required this.label,
  });

  /// "mute", "deafen" or "disconnect".
  final String id;

  /// Muted or deafened: the slashed glyph, in the critical colour.
  final bool active;

  /// Its tooltip and accessible name.
  final String label;
}

/// Someone in the call as the panel lists them.
class PanelMember {
  const PanelMember({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.talking = false,
    this.deafened = false,
    this.silentLabel,
  });

  /// Their user id.
  final String id;
  final String name;

  /// Their circle-masked avatar (a blob URL); a plain circle until then.
  final String? avatarUrl;

  /// Their voice is coming through: a green ring, as in the app.
  final bool talking;

  /// The slashed headset rather than the slashed microphone.
  final bool deafened;

  /// What their badge says when they cannot be heard ("Microphone muted",
  /// "Deafened"); null when they can.
  final String? silentLabel;

  @override
  bool operator ==(Object other) =>
      other is PanelMember &&
      other.id == id &&
      other.name == name &&
      other.avatarUrl == avatarUrl &&
      other.talking == talking &&
      other.deafened == deafened &&
      other.silentLabel == silentLabel;

  @override
  int get hashCode =>
      Object.hash(id, name, avatarUrl, talking, deafened, silentLabel);
}

/// The panel's DOM in [document]: who is in the call and who is talking,
/// over a row of round buttons with the call panel's glyphs. It is the
/// browser's in-game overlay: the window floats over other windows,
/// a borderless game's included.
///
/// It follows the browser's light or dark look and a forced-colors
/// (contrast) theme by itself, live, through CSS: the picture-in-picture
/// window is its own document with its own media queries.
class CallControlsPanel {
  CallControlsPanel(this.document,
      {required this.onPress, required String title, String? language}) {
    document.title = title;
    // The app's language (a BCP 47 tag), which screen readers read the
    // buttons' names in.
    if (language != null) {
      document.documentElement?.setAttribute("lang", language);
    }
    final style = document.createElement("style")..textContent = _css;
    document.head?.append(style);
    _members = document.createElement("div") as web.HTMLDivElement
      ..className = "members"
      ..setAttribute("role", "list");
    _row = document.createElement("div") as web.HTMLDivElement
      ..className = "controls";
    document.body?.append(_members);
    document.body?.append(_row);
  }

  final web.Document document;
  final void Function(String id) onPress;
  late final web.HTMLDivElement _members;
  late final web.HTMLDivElement _row;
  final Map<String, _MemberRow> _memberRows = {};

  /// Lists [members]. Called several times a second, so it only touches
  /// rows that changed: rebuilding them would reload every avatar.
  void renderMembers(List<PanelMember> members) {
    final listed = <String>{};
    web.Node? previous;
    for (final member in members) {
      listed.add(member.id);
      final row = _memberRows.putIfAbsent(member.id, () => _MemberRow(this))
        ..show(member);
      final here = previous == null ? _members.firstChild : previous.nextSibling;
      if (here == null || !here.isSameNode(row.element)) {
        _members.insertBefore(row.element, here);
      }
      previous = row.element;
    }
    _memberRows.removeWhere((id, row) {
      if (listed.contains(id)) return false;
      row.element.remove();
      return true;
    });
  }

  void render(List<PanelButton> buttons) {
    _row.replaceChildren(<JSAny>[].toJS);
    for (final button in buttons) {
      final element = document.createElement("button") as web.HTMLButtonElement
        ..type = "button"
        ..title = button.label
        ..className = button.id;
      element.setAttribute("aria-label", button.label);
      if (button.id != "disconnect") {
        element.setAttribute("aria-pressed", button.active.toString());
      }
      element.append(_glyph(_glyphs[button.id]![button.active ? 1 : 0]));
      element.addEventListener(
          "click", ((web.Event _) => onPress(button.id)).toJS);
      _row.append(element);
    }
  }

  web.Element _glyph(List<String> paths) {
    const svg = "http://www.w3.org/2000/svg";
    final glyph = document.createElementNS(svg, "svg")
      ..setAttribute("viewBox", "0 0 24 24")
      ..setAttribute("aria-hidden", "true");
    for (final d in paths) {
      glyph.append(document.createElementNS(svg, "path")..setAttribute("d", d));
    }
    return glyph;
  }

  /// The same glyphs as the call panel in the app: Material Icons, rounded
  /// (google/material-design-icons, Apache License 2.0), as [off, on].
  static const _glyphs = {
    "mute": [
      [
        "M12 14c1.66 0 3-1.34 3-3V5c0-1.66-1.34-3-3-3S9 3.34 9 5v6c0 1.66 1.34 3 3 3zm5.91-3c-.49 0-.9.36-.98.85C16.52 14.2 14.47 16 12 16s-4.52-1.8-4.93-4.15c-.08-.49-.49-.85-.98-.85-.61 0-1.09.54-1 1.14.49 3 2.89 5.35 5.91 5.78V20c0 .55.45 1 1 1s1-.45 1-1v-2.08c3.02-.43 5.42-2.78 5.91-5.78.1-.6-.39-1.14-1-1.14z",
      ],
      [
        "M15 10.6V5c0-1.66-1.34-3-3-3-1.54 0-2.79 1.16-2.96 2.65L15 10.6zm3.08.4c-.41 0-.77.3-.83.71-.05.32-.12.64-.22.93l1.27 1.27c.3-.6.52-1.25.63-1.94.07-.51-.33-.97-.85-.97zM3.71 3.56c-.39.39-.39 1.02 0 1.41L9 10.27v.43c0 1.19.6 2.32 1.63 2.91.75.43 1.41.44 2.02.31l1.66 1.66c-.71.33-1.5.52-2.31.52-2.54 0-4.88-1.77-5.25-4.39-.06-.41-.42-.71-.83-.71-.52 0-.92.46-.85.97.46 2.96 2.96 5.3 5.93 5.75V20c0 .55.45 1 1 1s1-.45 1-1v-2.28c.91-.13 1.77-.45 2.55-.9l3.49 3.49c.39.39 1.02.39 1.41 0 .39-.39.39-1.02 0-1.41L5.12 3.56c-.39-.39-1.02-.39-1.41 0z",
      ],
    ],
    "deafen": [
      [
        "M11.4 1.02C6.62 1.33 3 5.52 3 10.31V17c0 1.66 1.34 3 3 3h1c1.1 0 2-.9 2-2v-4c0-1.1-.9-2-2-2H5v-1.71C5 6.45 7.96 3.11 11.79 3 15.76 2.89 19 6.06 19 10v2h-2c-1.1 0-2 .9-2 2v4c0 1.1.9 2 2 2h1c1.66 0 3-1.34 3-3v-7c0-5.17-4.36-9.32-9.6-8.98z",
      ],
      [
        "M12,4c3.87,0,7,3.13,7,7v1h-2c-0.6,0-1.13,0.27-1.49,0.68L21,18.17V11c0-4.97-4.03-9-9-9C9.98,2,8.12,2.67,6.62,3.8 l1.43,1.43C9.17,4.45,10.53,4,12,4z",
        "M21.19,21.19L2.81,2.81c-0.39-0.39-1.02-0.39-1.41,0C1,3.2,1,3.83,1.39,4.22l2.63,2.63C3.37,8.09,3,9.5,3,11v7 c0,1.1,0.9,2,2,2h2c1.1,0,2-0.9,2-2v-4c0-1.1-0.9-2-2-2H5v-1c0-0.94,0.19-1.83,0.52-2.65L15,17.83V18c0,1.1,0.9,2,2,2h0.17l1,1H13 c-0.55,0-1,0.45-1,1s0.45,1,1,1h6c0.36,0,0.68-0.1,0.97-0.26c0.38,0.23,0.89,0.2,1.22-0.13C21.58,22.22,21.58,21.58,21.19,21.19z",
      ],
    ],
    "disconnect": [
      [
        "M4.51 15.48l2-1.59c.48-.38.76-.96.76-1.57v-2.6c3.02-.98 6.29-.99 9.32 0v2.61c0 .61.28 1.19.76 1.57l1.99 1.58c.8.63 1.94.57 2.66-.15l1.22-1.22c.8-.8.8-2.13-.05-2.88-6.41-5.66-16.07-5.66-22.48 0-.85.75-.85 2.08-.05 2.88l1.22 1.22c.71.72 1.85.78 2.65.15z",
      ],
      [
        "M4.51 15.48l2-1.59c.48-.38.76-.96.76-1.57v-2.6c3.02-.98 6.29-.99 9.32 0v2.61c0 .61.28 1.19.76 1.57l1.99 1.58c.8.63 1.94.57 2.66-.15l1.22-1.22c.8-.8.8-2.13-.05-2.88-6.41-5.66-16.07-5.66-22.48 0-.85.75-.85 2.08-.05 2.88l1.22 1.22c.71.72 1.85.78 2.65.15z",
      ],
    ],
  };

  /// The colours are WinUI's text and critical fills, the same as the
  /// taskbar thumbnail's. The slash tells muted from not by shape too, and a
  /// contrast theme gets its own button colours and no red. The talking ring
  /// is the app's SpeakingIndicator green.
  static const _css = """
:root {
  color-scheme: light dark;
  --surface: #f3f3f3;
  --button: #ffffff;
  --button-hover: #e9e9e9;
  --text: rgba(0, 0, 0, 0.894);
  --critical: #c42b1c;
}
@media (prefers-color-scheme: dark) {
  :root {
    --surface: #202020;
    --button: #2d2d2d;
    --button-hover: #383838;
    --text: #ffffff;
    --critical: #ff99a4;
  }
}
html, body { height: 100%; margin: 0; }
body {
  background: var(--surface);
  color: var(--text);
  display: flex;
  flex-direction: column;
  font-family: system-ui, sans-serif;
}
.members {
  flex: 1;
  overflow-y: auto;
  padding: 10px 12px 0;
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.members:empty { display: none; }
.member { display: flex; align-items: center; gap: 8px; min-height: 28px; }
.face {
  width: 24px;
  height: 24px;
  flex: none;
  border-radius: 50%;
  background: var(--button);
  object-fit: cover;
  outline: 2px solid transparent;
  outline-offset: 1.5px;
}
.member[data-talking="true"] .face { outline-color: #23a55a; }
.member[data-silent="true"] .face { outline-color: transparent; opacity: 0.5; }
.name {
  flex: 1;
  min-width: 0;
  font-size: 13px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  opacity: 0.75;
}
.member[data-talking="true"] .name { opacity: 1; font-weight: 600; }
.badge { display: grid; color: var(--critical); }
.badge svg { width: 16px; height: 16px; }
.controls { display: flex; gap: 12px; padding: 8px; justify-content: center; margin: auto; }
button {
  width: 44px;
  height: 44px;
  border-radius: 50%;
  border: 1px solid transparent;
  background: var(--button);
  color: var(--text);
  display: grid;
  place-items: center;
  cursor: pointer;
  padding: 0;
}
button:hover { background: var(--button-hover); }
button:focus-visible { outline: 2px solid Highlight; outline-offset: 2px; }
button[aria-pressed="true"] { color: var(--critical); }
svg { width: 24px; height: 24px; fill: currentColor; }
@media (forced-colors: active) {
  body { background: Canvas; }
  button, button:hover {
    background: ButtonFace;
    color: ButtonText;
    border-color: ButtonText;
  }
  button[aria-pressed="true"] { color: ButtonText; }
  .member[data-talking="true"] .face { outline-color: Highlight; }
  .member[data-silent="true"] .face { outline-color: transparent; }
  .badge { color: CanvasText; }
}
""";
}

/// One person's row in the panel's list, kept from one render to the next.
class _MemberRow {
  _MemberRow(this._panel)
      : element = _panel.document.createElement("div") as web.HTMLDivElement,
        _face = _panel.document.createElement("img") as web.HTMLImageElement,
        _name = _panel.document.createElement("span") as web.HTMLElement,
        _badge = _panel.document.createElement("span") as web.HTMLElement {
    element
      ..className = "member"
      ..setAttribute("role", "listitem");
    _face
      ..className = "face"
      ..alt = "";
    _name.className = "name";
    _badge.className = "badge";
    element
      ..append(_face)
      ..append(_name)
      ..append(_badge);
  }

  final CallControlsPanel _panel;
  final web.HTMLDivElement element;
  final web.HTMLImageElement _face;
  final web.HTMLElement _name;
  final web.HTMLElement _badge;
  PanelMember? _shown;

  void show(PanelMember member) {
    final shown = _shown;
    if (member == shown) return;
    _shown = member;

    element.setAttribute("data-talking", member.talking.toString());
    element.setAttribute("data-silent", (member.silentLabel != null).toString());
    if (member.name != shown?.name) _name.textContent = member.name;
    if (member.avatarUrl != shown?.avatarUrl) {
      final url = member.avatarUrl;
      if (url == null) {
        _face.removeAttribute("src");
      } else {
        _face.src = url;
      }
    }

    if (member.silentLabel == shown?.silentLabel &&
        member.deafened == shown?.deafened) {
      return;
    }
    _badge.replaceChildren(<JSAny>[].toJS);
    final label = member.silentLabel;
    if (label == null) {
      _badge
        ..removeAttribute("role")
        ..removeAttribute("aria-label")
        ..removeAttribute("title");
      return;
    }
    _badge
      ..setAttribute("role", "img")
      ..setAttribute("aria-label", label)
      ..setAttribute("title", label)
      ..append(_panel._glyph(
          CallControlsPanel._glyphs[member.deafened ? "deafen" : "mute"]![1]));
  }
}
