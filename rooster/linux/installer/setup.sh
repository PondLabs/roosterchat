#!/bin/sh
# The Linux installer: rooster-<tag>-linux-<arch>-setup.sh (x64 or arm64).
# This script with the release bundle, the launcher entry, the icon and the
# bundle's architecture appended as a tar.gz after the marker line at the
# end (.github/workflows/installers.yml).
#
# Installs for this user only, no root: into ~/.local/opt/Rooster, with a
# launcher entry, an icon and ~/.local/bin/rooster. A directory the user owns
# is one the updater can replace (docs/updating.md); a .deb under /usr is not.
#
#   sh rooster-<tag>-linux-<arch>-setup.sh              install, or reinstall
#   sh rooster-<tag>-linux-<arch>-setup.sh --uninstall  remove it again
set -eu

data=${XDG_DATA_HOME:-$HOME/.local/share}
opt=$HOME/.local/opt
install=$opt/Rooster
desktop=$data/applications/com.pondlabs.rooster.desktop
icon=$data/icons/hicolor/256x256/apps/com.pondlabs.rooster.png
bin=$HOME/.local/bin/rooster

if [ "${1:-}" = --uninstall ]; then
  rm -rf "$install" "$opt/.rooster-update" "$desktop" "$icon" "$bin"
  echo "Rooster is uninstalled. Your accounts and settings were left alone."
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
line=$(awk '/^__PAYLOAD__$/ { print NR + 1; exit }' "$0")
tail -n +"$line" "$0" | tar -xz -C "$tmp"

# A bundle for another CPU would install fine and never start.
if [ -f "$tmp/arch" ]; then
  case "$(uname -m)" in
    x86_64 | amd64) machine=x64 ;;
    aarch64 | arm64) machine=arm64 ;;
    *) machine=$(uname -m) ;;
  esac
  built=$(cat "$tmp/arch")
  if [ "$built" != "$machine" ]; then
    echo "This installer holds the $built build of Rooster; this computer is $machine." >&2
    echo "Take rooster-<tag>-linux-$machine-setup.sh from the release instead." >&2
    exit 1
  fi
fi

# A rename, so a reinstall over a running Rooster never leaves half of one.
mkdir -p "$opt" "$(dirname "$desktop")" "$(dirname "$icon")" "$(dirname "$bin")"
rm -rf "$install.old"
if [ -e "$install" ]; then mv "$install" "$install.old"; fi
mv "$tmp/Rooster" "$install"
rm -rf "$install.old"

sed -e "s|^Exec=rooster|Exec=\"$install/rooster\"|" -e 's|^Version=.*|Version=1.0|' \
  "$tmp/rooster.desktop" > "$desktop"
cp "$tmp/rooster.png" "$icon"
ln -sf "$install/rooster" "$bin"
update-desktop-database "$(dirname "$desktop")" 2> /dev/null || true

echo "Rooster is installed in $install. It is in your applications menu."
if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  (cd "$install" && nohup ./rooster > /dev/null 2>&1 &)
fi
exit 0
__PAYLOAD__
