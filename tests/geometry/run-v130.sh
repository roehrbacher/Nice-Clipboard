#!/bin/bash
# Offscreen (software) run of the real Clipboard.qml with v130.qml (1.30.0:
# update check off by default, then on against a stub (notice in the popup),
# OCR language pills with sizes from the local pacman database (read only),
# sidebar GitHub link, feedback "sent" note on its own wrapping line at
# 940 and 620 px against a local fake Worker). clipboard.sh, queue.sh, wl-copy, the
# notifiers and the terminal launcher are stubs that only log; temp data
# dir, no watchers, hard timeout. Nothing is installed, sent or pasted.
#   bash tests/geometry/run-v130.sh [png dir]
set -u
ulimit -c 0
here=$(cd "$(dirname "$0")" && pwd); src="$here/../.."
tmp=$(mktemp -d)
ln -s /usr/share/omarchy/shell/Commons "$tmp/Commons"; ln -s /usr/share/omarchy/shell/Ui "$tmp/Ui"
mkdir "$tmp/clip" "$tmp/data" "$tmp/bin" "$tmp/png"; cp "$src"/*.qml "$src"/*.js "$src"/*.sh "$src"/*.awk "$tmp/clip/"; cp "$here/PanelStub.qml" "$tmp/clip/"
# Never touch the live Hyprland binds: global-keys.sh is a stub that logs.
printf '#!/bin/bash\necho "$1" >> "%s/globalkeys"\n[[ $1 == apply ]] && printf "Alt+V\\ttaken\\tClipboard history\\nAlt+Shift+1\\ttaken\\tPaste pinned clipboard item 1\\nAlt+Shift+0\\tbound\\t\\n"\nexit 0\n' "$tmp" > "$tmp/clip/global-keys.sh"; chmod +x "$tmp/clip/global-keys.sh"
export NICE_CLIPBOARD_NO_GLOBAL_KEYS=1
printf '#!/bin/bash\necho "$*" >> "%s/queue"\nexit 0\n' "$tmp" > "$tmp/clip/queue.sh"
# Like the XPS: deu, eng, spa installed, hints en_US + kb:de, so no real suggestion.
# --sizes runs the real scan.sh: it only reads the pacman sync database.
mv "$tmp/clip/scan.sh" "$tmp/clip/scan-real.sh"
cat > "$tmp/clip/scan.sh" <<'SH'
#!/bin/bash
[[ $1 == --sizes ]] && exec "$(dirname "$0")/scan-real.sh" --sizes
[[ $1 == --langs ]] || exit 0
echo '{"installed":["deu","eng","ita","spa"],"used":"eng+deu+ita","env":"","hints":["en_US.UTF-8","kb:de"]}'
SH
# Never GitHub from tests: the update check is a stub that logs.
printf '#!/bin/bash\necho call >> "%s/updatecheck"\necho '"'"'{"latest":"1.31.0","git":false}'"'"'\n' "$tmp" > "$tmp/clip/update-check.sh"
printf '#!/bin/bash\necho "$*" >> "%s/helper"\n[[ $1 == current ]] && echo empty\nexit 0\n' "$tmp" > "$tmp/clip/clipboard.sh"; chmod +x "$tmp/clip/"*.sh
printf '#!/bin/bash\n[[ $1 == status ]] && echo '"'"'{"running":true,"devices":[]}'"'"'\nexit 0\n' > "$tmp/bin/flux-cli"
printf '#!/bin/bash\necho "uwsm-app: $*" >> "%s/install"\n' "$tmp" > "$tmp/bin/uwsm-app"
printf '#!/bin/bash\necho "SUDO MUST NOT RUN" >> "%s/install"; exit 1\n' "$tmp" > "$tmp/bin/sudo"
printf '#!/bin/bash\necho "$*" >> "%s/xdgopen"\n' "$tmp" > "$tmp/bin/xdg-open"
for b in omarchy-notification-send notify-send; do printf '#!/bin/bash\nprintf "%%s|" "$@" >> "%s/notify"; echo >> "%s/notify"\n' "$tmp" "$tmp" > "$tmp/bin/$b"; done
printf '#!/bin/bash\ncat >> "%s/wlcopy"; echo >> "%s/wlcopy"\n' "$tmp" "$tmp" > "$tmp/bin/wl-copy"; chmod +x "$tmp/bin/"*
printf 'KineticScroll 1.0 KineticScroll.qml\nMarqueeLabel 1.0 MarqueeLabel.qml\nPanelStub 1.0 PanelStub.qml\n' > "$tmp/clip/qmldir"
sed -i -e 's/^  KeyboardPanel {/  PanelStub {/' -e 's/; pkill -f [^"]*"/"/' -e '/textWatchProc.running = true$/d' -e '/imageWatchProc.running = true$/d' -e '/currentProc.running = true$/d' "$tmp/clip/Clipboard.qml"
printf '  function displayModelCount() { return displayModel.count }\n  function settingsLoaderItem() { return settingsWindowLoader.item }\n}\n' > "$tmp/tail"; sed -i '$d' "$tmp/clip/Clipboard.qml"; cat "$tmp/tail" >> "$tmp/clip/Clipboard.qml"
# Never the live feedback Worker: a local fake one answers {"ok":true}.
port=$((20000 + RANDOM % 20000))
cat > "$tmp/worker.py" <<PY
import http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("content-length", "0")); b = self.rfile.read(n)
        open("$tmp/posted", "ab").write(b + b"\n")
        self.send_response(201); self.send_header("content-type", "application/json"); self.end_headers()
        self.wfile.write(b'{"ok":true}')
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", $port), H).serve_forever()
PY
timeout -s KILL 65 python3 "$tmp/worker.py" & wpid=$!
trap 'kill $wpid 2>/dev/null; rm -rf "$tmp"' EXIT
sed -i -E "s|readonly property string feedbackEndpoint: \"[^\"]*\"|readonly property string feedbackEndpoint: \"http://127.0.0.1:$port/feedback\"|" "$tmp/clip/Clipboard.qml"
grep -q 'feedback.roehrbacher.com' "$tmp/clip/Clipboard.qml" && { echo "V130 ERROR live endpoint still set"; exit 1; }
cp "$here/v130.qml" "$tmp/shell.qml"
theme="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme/colors.toml"
tc() { sed -n "s/^$1 *= *\"\(#[0-9A-Fa-f]*\)\".*/\1/p" "$theme" 2>/dev/null | head -1; }
export V130_BG=$(tc background) V130_FG=$(tc foreground) V130_ACCENT=$(tc accent)
V130_PNG_DIR="$tmp/png" PATH="$tmp/bin:$PATH" XDG_DATA_HOME="$tmp/data" XDG_STATE_HOME="$tmp/data" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software setsid timeout -s KILL 55 quickshell -p "$tmp/shell.qml" > "$tmp/out" 2>&1
sleep 1
grep -E 'V130|ERROR|rror:|TypeError|ReferenceError|Unable' "$tmp/out" | grep -v 'qt.qpa'
echo "V130 helper calls: $(grep -v '^current' "$tmp/helper" 2>/dev/null | tr "\n" ";")"
echo "V130 install calls: $(tr "\n" ";" 2>/dev/null < "$tmp/install")"
echo "V130 fake Worker got: $(cat "$tmp/posted" 2>/dev/null)"
echo "V130 global-keys.sh calls: $(tr "\n" ";" 2>/dev/null < "$tmp/globalkeys")"
echo "V130 update-check.sh calls: $(grep -c call "$tmp/updatecheck" 2>/dev/null || echo 0)"
echo "V130 xdg-open calls: $(tr "\n" ";" 2>/dev/null < "$tmp/xdgopen")"
echo "V130 state.json: $(cat "$tmp/data/timon.clipboard/state.json" 2>/dev/null)"
if [[ -n ${1:-} ]]; then mkdir -p "$1"; cp "$tmp"/png/*.png "$1"/ 2>/dev/null; echo "V130 PNGs: $(cd "$1" && command ls *.png 2>/dev/null | tr "\n" " ")"; fi
