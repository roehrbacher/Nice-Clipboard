#!/bin/bash
# Offscreen (software) run of the real Clipboard.qml with v128.qml (1.28.0:
# OCR banner in the popup, click-to-install through stub terminal/pkg-add,
# re-detect, Alt+N = pins, version in the header, settings window with a
# sidebar, toast-sized OCR preview). clipboard.sh, queue.sh, wl-copy, the
# notifiers and the install commands are stubs that only log; temp data
# dir, no watchers, hard timeout. Nothing is installed or pasted for real.
set -u
ulimit -c 0
here=$(cd "$(dirname "$0")" && pwd); src="$here/../.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
ln -s /usr/share/omarchy/shell/Commons "$tmp/Commons"; ln -s /usr/share/omarchy/shell/Ui "$tmp/Ui"
mkdir "$tmp/clip" "$tmp/data" "$tmp/bin"; cp "$src"/*.qml "$src"/*.js "$src"/*.sh "$src"/*.awk "$tmp/clip/"; cp "$here/PanelStub.qml" "$tmp/clip/"
printf '#!/bin/bash\necho "$*" >> "%s/queue"\nexit 0\n' "$tmp" > "$tmp/clip/queue.sh"
# scan.sh --langs stub: English installed (+ German once the fake install ran),
# German locale + Austrian layout.
cat > "$tmp/clip/scan.sh" <<SH
#!/bin/bash
[[ \$1 == --langs ]] || exit 0
inst='"eng"'; [[ -e "$tmp/installed-deu" ]] && inst='"deu","eng"'
echo "{\"installed\":[\$inst],\"used\":\"eng\",\"env\":\"\",\"hints\":[\"de_AT.UTF-8\",\"en_US.UTF-8\",\"kb:at\",\"kb:us\"]}"
SH
printf '#!/bin/bash\necho "$*" >> "%s/helper"\n[[ $1 == current ]] && echo empty\nexit 0\n' "$tmp" > "$tmp/clip/clipboard.sh"; chmod +x "$tmp/clip/"*.sh
printf '#!/bin/bash\n[[ $1 == status ]] && echo '"'"'{"running":true,"devices":[]}'"'"'\nexit 0\n' > "$tmp/bin/flux-cli"
# Install stubs: the "terminal" logs its command and marks deu installed.
printf '#!/bin/bash\necho "terminal: $*" >> "%s/install"\ntouch "%s/installed-deu"\n' "$tmp" "$tmp" > "$tmp/bin/omarchy-launch-floating-terminal-with-presentation"
printf '#!/bin/bash\necho "pkg-add: $*" >> "%s/install"\n' "$tmp" > "$tmp/bin/omarchy-pkg-add"
printf '#!/bin/bash\necho "SUDO MUST NOT RUN" >> "%s/install"; exit 1\n' "$tmp" > "$tmp/bin/sudo"
for b in omarchy-notification-send notify-send; do printf '#!/bin/bash\nprintf "%%s|" "$@" >> "%s/notify"; echo >> "%s/notify"\n' "$tmp" "$tmp" > "$tmp/bin/$b"; done
printf '#!/bin/bash\ncat >> "%s/wlcopy"; echo >> "%s/wlcopy"\n' "$tmp" "$tmp" > "$tmp/bin/wl-copy"; chmod +x "$tmp/bin/"*
printf 'KineticScroll 1.0 KineticScroll.qml\nMarqueeLabel 1.0 MarqueeLabel.qml\nPanelStub 1.0 PanelStub.qml\n' > "$tmp/clip/qmldir"
sed -i -e 's/^  KeyboardPanel {/  PanelStub {/' -e 's/; pkill -f [^"]*"/"/' -e '/textWatchProc.running = true$/d' -e '/imageWatchProc.running = true$/d' -e '/currentProc.running = true$/d' "$tmp/clip/Clipboard.qml"
# Never the live feedback Worker: point Send at a closed local port.
sed -i -E 's|readonly property string feedbackEndpoint: "[^"]*"|readonly property string feedbackEndpoint: "http://127.0.0.1:9/feedback"|' "$tmp/clip/Clipboard.qml"
grep -q 'feedback.roehrbacher.com' "$tmp/clip/Clipboard.qml" && { echo "V128 ERROR live endpoint still set"; exit 1; }
printf '  function displayModelCount() { return displayModel.count }\n  function displayModelGet(i) { return displayModel.get(i) }\n}\n' > "$tmp/tail"; sed -i '$d' "$tmp/clip/Clipboard.qml"; cat "$tmp/tail" >> "$tmp/clip/Clipboard.qml"
cp "$here/v128.qml" "$tmp/shell.qml"; mkdir "$tmp/png"
theme="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme/colors.toml"
tc() { sed -n "s/^$1 *= *\"\(#[0-9A-Fa-f]*\)\".*/\1/p" "$theme" 2>/dev/null | head -1; }
export V128_BG=$(tc background) V128_FG=$(tc foreground) V128_ACCENT=$(tc accent)
V128_PNG_DIR="$tmp/png" PATH="$tmp/bin:$PATH" XDG_DATA_HOME="$tmp/data" XDG_STATE_HOME="$tmp/data" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software setsid timeout -s KILL 50 quickshell -p "$tmp/shell.qml" > "$tmp/out" 2>&1
grep -E 'V128|ERROR|rror:|TypeError|ReferenceError|Unable' "$tmp/out" | grep -v 'qt.qpa'
echo "V128 helper calls: $(tr "\n" ";" 2>/dev/null < "$tmp/helper")"
echo "V128 install calls: $(tr "\n" ";" 2>/dev/null < "$tmp/install")"
echo "V128 state.json: $(cat "$tmp/data/timon.clipboard/state.json" 2>/dev/null)"
echo "V128 notifications:"; sed 's/^/  /' "$tmp/notify" 2>/dev/null
if [[ -n ${1:-} ]]; then mkdir -p "$1"; cp "$tmp"/png/*.png "$1"/ 2>/dev/null; echo "V128 PNGs: $(cd "$1" && ls *.png 2>/dev/null | tr "\n" " ")"; fi
