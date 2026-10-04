#!/bin/sh
# The Linux installer: rooster-<tag>-linux-x64-setup.sh. This script with the
# release bundle, the launcher entry and the icon appended as a tar.gz after
# the marker line at the end (.github/workflows/installers.yml).
#
# Installs for this user only, no root: into ~/.local/opt/Rooster, with a
# launcher entry, an icon and ~/.local/bin/rooster. A directory the user owns
# is one the updater can replace (docs/updating.md); a .deb under /usr is not.
#
#   sh rooster-<tag>-linux-x64-setup.sh              install, or reinstall
#   sh rooster-<tag>-linux-x64-setup.sh --uninstall  remove it again
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
