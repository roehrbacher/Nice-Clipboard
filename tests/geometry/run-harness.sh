#!/bin/bash
# Offscreen (software) run of the real Clipboard.qml with one scenario file:
#   v129.qml  1.29.0: Alt+Shift slots, settings window only + reopen, feedback
#             "sent" state, dev demo banner, install launch
#   v130.qml  1.30.0: update check off by default / on (notice in the popup),
#             OCR sizes, sidebar GitHub link, feedback note at 940 and 620 px
#   v131.qml  1.31.0: delete arm/confirm, Ctrl+Z undo, General / History /
#             Text recognition / Uninstall pages
#   v133.qml  1.33.0: no edit button, 1.31 left-click pills (pasteKeep
#             migrates), popup heading after Pinned and settings History
#             page next to the stock Display panel section
#   v1331.qml 1.33.1: typing during a slow feedback send is kept; a copy
#             from another app ends an armed delete
#   v1332.qml 1.33.2: empty-state and search-field dimming next to the
#             stock launcher; OCR no longer polls --langs while a job runs
#   v1333.qml 1.33.3: "Select, paste & close" closes and pastes into the
#             window that had the keyboard when the popup opened
#   v1322.qml 1.32.2: every popup close ends the clear question / armed
#             delete; a cancelled OCR job clears its state
#   v132.qml  1.32.0: popup header next to the stock PanelHero, no edit
#             button, left-click pills, General / History / Phone / Shortcuts,
#             subtitle sizes, phone quarantine after incognito
# clipboard.sh, queue.sh, global-keys.sh, update-check.sh, wl-copy, the
# notifiers, xdg-open and the terminal launcher are stubs that only log;
# feedback goes to a local fake Worker; temp data dir, no watchers, hard
# timeout. Nothing is installed, removed, sent or pasted.
#   bash tests/geometry/run-harness.sh v129|v130|v131|v132|v1322|v133|v1331|v1332 [png dir]
set -u
name=${1:?usage: run-harness.sh v129|v130|v131|v132|v1322|v133|v1331|v1332|v1333 [png dir]}; shift
tag=${name^^}
ulimit -c 0
here=$(cd "$(dirname "$0")" && pwd); src="$here/../.."
tmp=$(mktemp -d)
shell_src=${OMARCHY_SHELL:-/usr/share/omarchy/shell}
ln -s "$shell_src/Commons" "$tmp/Commons"; ln -s "$shell_src/Ui" "$tmp/Ui"
mkdir -p "$tmp/clip" "$tmp/data/timon.clipboard" "$tmp/bin" "$tmp/png"; cp "$src"/*.qml "$src"/*.js "$src"/*.sh "$src"/*.awk "$tmp/clip/"; cp "$here/PanelStub.qml" "$tmp/clip/"
# Never touch the live Hyprland binds: global-keys.sh is a stub that logs.
printf '#!/bin/bash\necho "$1" >> "%s/globalkeys"\n[[ $1 == apply ]] && printf "Alt+V\\ttaken\\tClipboard history\\nAlt+Shift+1\\ttaken\\tPaste pinned clipboard item 1\\nAlt+Shift+0\\tbound\\t\\n"\nexit 0\n' "$tmp" > "$tmp/clip/global-keys.sh"; chmod +x "$tmp/clip/global-keys.sh"
export NICE_CLIPBOARD_NO_GLOBAL_KEYS=1
printf '#!/bin/bash\necho "$*" >> "%s/queue"\nexit 0\n' "$tmp" > "$tmp/clip/queue.sh"
# Like the XPS: deu, eng, ita, spa installed, hints en_US + kb:de, so no real suggestion.
# --sizes runs the real scan.sh: it only reads the pacman sync database.
mv "$tmp/clip/scan.sh" "$tmp/clip/scan-real.sh"
cat > "$tmp/clip/scan.sh" <<SH
#!/bin/bash
[[ \$1 == --sizes ]] && exec "\$(dirname "\$0")/scan-real.sh" --sizes
[[ \$1 == --langs ]] || exit 0
echo langs >> "$tmp/data/langs"
echo '{"installed":["deu","eng","ita","spa"],"used":"eng+deu+ita+spa","env":"","hints":["en_US.UTF-8","kb:de"]}'
SH
# Never the real Flux: flux-pause.sh is a stub that logs (the real one stops
# and starts fluxd.service), and systemctl is a logging stub as well.
printf '#!/bin/bash\necho "$*" >> "%s/fluxpause"\ncase $1 in pause) echo paused;; *) echo running;; esac\n' "$tmp" > "$tmp/clip/flux-pause.sh"
printf '#!/bin/bash\necho "$*" >> "%s/systemctl"\nexit 0\n' "$tmp" > "$tmp/bin/systemctl"
# Never GitHub from tests: the update check is a stub that logs.
printf '#!/bin/bash\necho call >> "%s/updatecheck"\necho '"'"'{"latest":"99.0.0","git":false}'"'"'\n' "$tmp" > "$tmp/clip/update-check.sh"
printf '#!/bin/bash\necho "$*" >> "%s/helper"\n[[ $1 == current ]] && echo empty\nexit 0\n' "$tmp" > "$tmp/clip/clipboard.sh"; chmod +x "$tmp/clip/"*.sh
printf '#!/bin/bash\n[[ $1 == status ]] && echo '"'"'{"running":true,"devices":[]}'"'"'\nexit 0\n' > "$tmp/bin/flux-cli"
printf '#!/bin/bash\necho "uwsm-app: $*" >> "%s/install"\n' "$tmp" > "$tmp/bin/uwsm-app"
printf '#!/bin/bash\necho "SUDO MUST NOT RUN" >> "%s/install"; exit 1\n' "$tmp" > "$tmp/bin/sudo"
printf '#!/bin/bash\necho "$*" >> "%s/xdgopen"\n' "$tmp" > "$tmp/bin/xdg-open"
for b in omarchy-notification-send notify-send; do printf '#!/bin/bash\nprintf "%%s|" "$@" >> "%s/notify"; echo >> "%s/notify"\n' "$tmp" "$tmp" > "$tmp/bin/$b"; done
printf '#!/bin/bash\ncat >> "%s/wlcopy"; echo >> "%s/wlcopy"\n' "$tmp" "$tmp" > "$tmp/bin/wl-copy"; chmod +x "$tmp/bin/"*
printf 'KineticScroll 1.0 KineticScroll.qml\nMarqueeLabel 1.0 MarqueeLabel.qml\nSwitchTrack 1.0 SwitchTrack.qml\nPanelStub 1.0 PanelStub.qml\n' > "$tmp/clip/qmldir"
sed -i -e 's/^  KeyboardPanel {/  PanelStub {/' -e 's/; pkill -f [^"]*"/"/' -e '/textWatchProc.running = true$/d' -e '/imageWatchProc.running = true$/d' -e '/currentProc.running = true$/d' "$tmp/clip/Clipboard.qml"
printf '  function displayModelCount() { return displayModel.count }\n  function displayRow(i) { return displayModel.get(i) }\n  function settingsLoaderItem() { return settingsWindowLoader.item }\n}\n' > "$tmp/tail"; sed -i '$d' "$tmp/clip/Clipboard.qml"; cat "$tmp/tail" >> "$tmp/clip/Clipboard.qml"
# Never the live feedback Worker: a local fake one answers {"ok":true}.
port=$((20000 + RANDOM % 20000))
cat > "$tmp/worker.py" <<PY
import http.server, time
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("content-length", "0")); b = self.rfile.read(n)
        open("$tmp/posted", "ab").write(b + b"\n")
        if b"slow" in b: time.sleep(2)  # v1331: a send that takes a while
        self.send_response(201); self.send_header("content-type", "application/json"); self.end_headers()
        self.wfile.write(b'{"ok":true}')
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", $port), H).serve_forever()
PY
timeout -s KILL 65 python3 "$tmp/worker.py" & wpid=$!
trap 'kill $wpid 2>/dev/null; rm -rf "$tmp"' EXIT
sed -i -E "s|readonly property string feedbackEndpoint: \"[^\"]*\"|readonly property string feedbackEndpoint: \"http://127.0.0.1:$port/feedback\"|" "$tmp/clip/Clipboard.qml"
grep -q 'feedback.roehrbacher.com' "$tmp/clip/Clipboard.qml" && { echo "$tag ERROR live endpoint still set"; exit 1; }
cp "$here/$name.qml" "$tmp/shell.qml"
theme="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme/colors.toml"
tc() { sed -n "s/^$1 *= *\"\(#[0-9A-Fa-f]*\)\".*/\1/p" "$theme" 2>/dev/null | head -1; }
export HARNESS_BG=$(tc background) HARNESS_FG=$(tc foreground) HARNESS_ACCENT=$(tc accent) HARNESS_URGENT=$(tc red)
HARNESS_PNG_DIR="$tmp/png" PATH="$tmp/bin:$PATH" XDG_DATA_HOME="$tmp/data" XDG_STATE_HOME="$tmp/data" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software setsid timeout -s KILL 55 quickshell -p "$tmp/shell.qml" > "$tmp/out" 2>&1
sleep 1
grep -E "$tag|"'ERROR|rror:|TypeError|ReferenceError|Unable' "$tmp/out" | grep -v 'qt.qpa'
echo "$tag helper calls: $(grep -v '^current' "$tmp/helper" 2>/dev/null | tr "\n" ";")"
echo "$tag fake Worker got: $(cat "$tmp/posted" 2>/dev/null)"
echo "$tag update-check.sh calls: $(grep -c call "$tmp/updatecheck" 2>/dev/null || echo 0)"
echo "$tag scan.sh --langs calls: $(grep -c langs "$tmp/data/langs" 2>/dev/null || echo 0)"
echo "$tag global-keys.sh calls: $(tr "\n" ";" 2>/dev/null < "$tmp/globalkeys")"
echo "$tag terminal launches: $(sed "s#$tmp#TMP#g" "$tmp/install" 2>/dev/null | tr "\n" ";")"
echo "$tag flux-pause.sh calls: $(tr "\n" ";" 2>/dev/null < "$tmp/fluxpause") systemctl calls: $(tr "\n" ";" 2>/dev/null < "$tmp/systemctl")"
echo "$tag xdg-open calls: $(tr "\n" ";" 2>/dev/null < "$tmp/xdgopen")"
echo "$tag state.json: $(cat "$tmp/data/timon.clipboard/state.json" 2>/dev/null)"
if [[ -n ${1:-} ]]; then mkdir -p "$1"; cp "$tmp"/png/*.png "$1"/ 2>/dev/null; echo "$tag PNGs: $(cd "$1" && command ls *.png 2>/dev/null | tr "\n" " ")"; fi
