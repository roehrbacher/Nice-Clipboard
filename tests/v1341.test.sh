#!/bin/bash
# Run: bash tests/v1341.test.sh  (offscreen quickshell on the real
# Clipboard.qml, temp data dir, stubs; see tests/geometry/run-harness.sh)
# 1.34.1: unreadable history.json is set aside, not overwritten; copies
# before the load are kept; a copy during a pin drag keeps the drag.
set -u
here=$(cd "$(dirname "$0")" && pwd)
out=$(bash "$here/geometry/run-harness.sh" v1341 2>&1)
fail=0
check() { if grep -qF -- "$2" <<<"$out"; then echo "ok   $1"; else echo "FAIL $1: no line with '$2'"; fail=1; fi; }
seed=$(cat "$here/geometry/v1341.history")
check "cut-off file kept unchanged as history.json.bad-*" "set aside history.json.bad-"
line=$(grep -m1 "set aside history.json.bad-" <<<"$out")
[[ ${line#*: } == "$seed" ]] && echo "ok   set-aside file is byte-for-byte the original" || { echo "FAIL set-aside file differs from the original"; fail=1; }
check "new copy saved to a fresh history.json" 'V1341 history.json after a copy: [{"type":"text","text":"after the break"'
check "the user is told" "Clipboard history could not be read"
check "early copy kept after the load" "V1341 early copy then load: [early copy, *saved pin, saved item]"
check "drag order kept with a copy mid-drag" "V1341 drag with a copy mid-drag: history [incoming, *P2, *P3, *P1, h1, h2] rows [*P2, *P3, *P1, incoming, h1, h2]"
check "a press does not hold back the list" "V1341 rows right after a copy during a press: [*P1, *P2, pressed copy, h1]"
check "press, copy, then drag moves the pressed entry" "V1341 press, copy, then drag: history [pressed copy, h1, *P2, *P1]"
grep -E "TypeError|ReferenceError| ERROR " <<<"$out" && fail=1
[[ $fail == 0 ]] || { echo "--- harness output"; grep V1341 <<<"$out"; }
exit $fail
