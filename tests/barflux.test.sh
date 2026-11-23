#!/bin/bash
# Run: bash tests/barflux.test.sh  (offscreen quickshell, temp data dir,
# flux-pause.sh is a stub that logs; needs the Omarchy shell's Ui, see
# OMARCHY_SHELL in run-harness.sh)
# 1.34.1: the bar icon asks flux-pause.sh for the Flux state only when
# incognito changes (or on the first read), not after every state.json
# write (settings, the daily update check).
set -u
ulimit -c 0
here=$(cd "$(dirname "$0")/.." && pwd)
shell_src=${OMARCHY_SHELL:-/usr/share/omarchy/shell}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/clip" "$tmp/data/timon.clipboard"
ln -s "$shell_src/Commons" "$tmp/Commons"; ln -s "$shell_src/Ui" "$tmp/Ui"
cp "$here/BarWidget.qml" "$here/Bridge.js" "$tmp/clip/"
printf '#!/bin/bash\necho "$*" >> "%s/fluxpause"\necho running\n' "$tmp" >"$tmp/clip/flux-pause.sh"; chmod +x "$tmp/clip/flux-pause.sh"
S="$tmp/data/timon.clipboard/state.json"
echo '{"private":false}' >"$S"
cat >"$tmp/shell.qml" <<QML
import Quickshell
import QtQuick
import QtQuick.Window
ShellRoot {
  id: shell
  property var w: null
  property int step: 0
  Window { id: win; width: 100; height: 40; visible: true }
  Component.onCompleted: {
    var c = Qt.createComponent("clip/BarWidget.qml")
    if (c.status !== Component.Ready) { console.log("BARFLUX ERR " + c.errorString()); Qt.quit(); return }
    w = c.createObject(win.contentItem, {})
    t.start()
  }
  Timer {
    id: t; interval: 6000; repeat: true
    onTriggered: {
      shell.step++
      console.log("BARFLUX step " + shell.step)
      if (shell.step === 1) Quickshell.execDetached(["sh", "-c", "echo step1 >> $tmp/fluxpause; echo '{\"private\":false,\"keepDays\":3}' > $S"])
      else if (shell.step === 2) Quickshell.execDetached(["sh", "-c", "echo step2 >> $tmp/fluxpause; echo '{\"private\":true,\"keepDays\":3}' > $S"])
      else { stop(); Qt.quit() }
    }
  }
}
QML
XDG_DATA_HOME="$tmp/data" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software setsid timeout -s KILL 40 quickshell -p "$tmp/shell.qml" >"$tmp/out" 2>&1
log=$(tr '\n' ' ' <"$tmp/fluxpause" 2>/dev/null)
fail=0
check() { if [[ $2 == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: got '$2' want '$3'"; fail=1; fi; }
first=${log%%step1*}; mid=${log#*step1 }; mid=${mid%%step2*}; last=${log#*step2 }
check "first read checks Flux" "$([[ $first == *status* ]] && echo yes || echo no)" yes
check "a settings write does not run flux-pause.sh" "$mid" ""
check "an incognito switch does" "$([[ $last == *status* ]] && echo yes || echo no)" yes
[[ $fail == 0 ]] || { echo "log: $log"; grep -E "BARFLUX|rror" "$tmp/out"; }
exit $fail
