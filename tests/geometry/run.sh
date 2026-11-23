#!/bin/bash
# Offscreen geometry check of the real Clipboard.qml (KeyboardPanel replaced
# by PanelStub, no layer surface): prints header/row/button positions.
# Uses a temporary data dir; nothing touches the real history.
set -u
here=$(cd "$(dirname "$0")" && pwd); src="$here/../.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
ln -s /usr/share/omarchy/shell/Commons "$tmp/Commons"; ln -s /usr/share/omarchy/shell/Ui "$tmp/Ui"
mkdir "$tmp/clip" "$tmp/data"; cp "$src"/*.qml "$src"/*.js "$src"/*.sh "$tmp/clip/" 2>/dev/null; cp "$here/PanelStub.qml" "$tmp/clip/"
# Never touch the live Hyprland binds: global-keys.sh is a stub that logs.
printf '#!/bin/bash\necho "$1" >> "%s/globalkeys"\n[[ $1 == apply ]] && printf "Alt+V\\ttaken\\tClipboard history\\nAlt+Shift+1\\ttaken\\tPaste pinned clipboard item 1\\nAlt+Shift+0\\tbound\\t\\n"\nexit 0\n' "$tmp" > "$tmp/clip/global-keys.sh"; chmod +x "$tmp/clip/global-keys.sh"
export NICE_CLIPBOARD_NO_GLOBAL_KEYS=1
printf 'KineticScroll 1.0 KineticScroll.qml\nMarqueeLabel 1.0 MarqueeLabel.qml\nPanelStub 1.0 PanelStub.qml\n' > "$tmp/clip/qmldir"
sed -i 's/^  KeyboardPanel {/  PanelStub {/' "$tmp/clip/Clipboard.qml"
cp "$here/shell.qml" "$tmp/"
XDG_DATA_HOME="$tmp/data" XDG_STATE_HOME="$tmp/data" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software setsid quickshell -p "$tmp/shell.qml" > "$tmp/out" 2>&1 &
pid=$!; sleep 15; pg=$(ps -o pgid= "$pid" | tr -d ' '); [ -n "$pg" ] && kill -KILL -- "-$pg" 2>/dev/null
grep -o 'GEO.*' "$tmp/out"
