#!/bin/bash
# Offscreen (software) run of the real Clipboard.qml with v126.qml. clipboard.sh,
# queue.sh, wl-copy and the notifiers are stubs that only log (nothing reaches
# the real clipboard or the screen); temp data dir, no watchers, hard timeout.
set -u
ulimit -c 0
here=$(cd "$(dirname "$0")" && pwd); src="$here/../.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
ln -s /usr/share/omarchy/shell/Commons "$tmp/Commons"; ln -s /usr/share/omarchy/shell/Ui "$tmp/Ui"
mkdir "$tmp/clip" "$tmp/data" "$tmp/bin"; cp "$src"/*.qml "$src"/*.js "$src"/*.sh "$src"/*.awk "$tmp/clip/"; cp "$here/PanelStub.qml" "$tmp/clip/"
printf '#!/bin/bash\necho "$*" >> "%s/queue"\nexit 0\n' "$tmp" > "$tmp/clip/queue.sh"
printf '#!/bin/bash\necho "$*" >> "%s/helper"\n[[ $1 == current ]] && echo empty\nexit 0\n' "$tmp" > "$tmp/clip/clipboard.sh"; chmod +x "$tmp/clip/"*.sh
# flux-cli stub (status only), so the test never talks to the real fluxd.
printf '#!/bin/bash\n[[ $1 == status ]] && echo '"'"'{"running":true,"devices":[]}'"'"'\nexit 0\n' > "$tmp/bin/flux-cli"
for b in omarchy-notification-send notify-send; do printf '#!/bin/bash\nprintf "%%s|" "$@" >> "%s/notify"; echo >> "%s/notify"\n' "$tmp" "$tmp" > "$tmp/bin/$b"; done
printf '#!/bin/bash\ncat >> "%s/wlcopy"; echo >> "%s/wlcopy"\n' "$tmp" "$tmp" > "$tmp/bin/wl-copy"; chmod +x "$tmp/bin/"*
printf 'KineticScroll 1.0 KineticScroll.qml\nMarqueeLabel 1.0 MarqueeLabel.qml\nPanelStub 1.0 PanelStub.qml\n' > "$tmp/clip/qmldir"
sed -i -e 's/^  KeyboardPanel {/  PanelStub {/' -e 's/; pkill -f [^"]*"/"/' -e '/textWatchProc.running = true$/d' -e '/imageWatchProc.running = true$/d' -e '/currentProc.running = true$/d' "$tmp/clip/Clipboard.qml"
printf '  function displayModelCount() { return displayModel.count }\n  function displayModelGet(i) { return displayModel.get(i) }\n}\n' > "$tmp/tail"; sed -i '$d' "$tmp/clip/Clipboard.qml"; cat "$tmp/tail" >> "$tmp/clip/Clipboard.qml"
cp "$here/v126.qml" "$tmp/shell.qml"; mkdir "$tmp/png"
# Colours of the current Omarchy theme (read only), so the PNGs look real:
# the stub host has no theme, the popup's colour tokens would be empty.
theme="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme/colors.toml"
tc() { sed -n "s/^$1 *= *\"\(#[0-9A-Fa-f]*\)\".*/\1/p" "$theme" 2>/dev/null | head -1; }
export V126_BG=$(tc background) V126_FG=$(tc foreground) V126_ACCENT=$(tc accent)
V126_PNG_DIR="$tmp/png" PATH="$tmp/bin:$PATH" XDG_DATA_HOME="$tmp/data" XDG_STATE_HOME="$tmp/data" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software setsid timeout -s KILL 30 quickshell -p "$tmp/shell.qml" > "$tmp/out" 2>&1
grep -E 'V126|ERROR|rror:|TypeError|ReferenceError|Unable' "$tmp/out" | grep -v 'qt.qpa'
echo "V126 helper calls: $(tr "\n" ";" < "$tmp/helper" 2>/dev/null)"
echo "V126 wl-copy got: $(tr "\n" ";" < "$tmp/wlcopy" 2>/dev/null)"
echo "V126 queue.sh calls: $(tr "\n" ";" < "$tmp/queue" 2>/dev/null)"
echo "V126 notifications:"; sed 's/^/  /' "$tmp/notify" 2>/dev/null | while IFS= read -r l; do g=$(printf '%s' "$l" | sed -n 's/.*|-g|\(.\)|.*/\1/p'); printf '%s  [glyph U+%X]\n' "$l" "'$g"; done
# Screenshots of the settings page (top to bottom) go to $1 when given.
if [[ -n ${1:-} ]]; then mkdir -p "$1"; cp "$tmp"/png/*.png "$1"/ 2>/dev/null; echo "V126 PNGs: $(cd "$1" && ls *.png 2>/dev/null | tr "\n" " ")"; fi
