#!/bin/bash
# Run: bash tests/copy-pinned.test.sh  (fake wl-copy, temp data dir; never touches the real clipboard)
set -u
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/data/timon.clipboard"
printf '#!/bin/bash\ncat > "%s/copied"\n' "$T" > "$T/bin/wl-copy"; chmod +x "$T/bin/wl-copy"
cat > "$T/data/timon.clipboard/history.json" <<'J'
[{"type":"text","text":"c","pinned":true},{"type":"text","text":"x"},{"type":"text","text":"a","pinned":true},{"type":"text","text":"b","pinned":true}]
J
run() { PATH="$T/bin:$PATH" XDG_DATA_HOME="$T/data" bash "$(dirname "$0")/../clipboard.sh" copy-pinned "$1"; }
fail=0
check() { rm -f "$T/copied"; run "$1"; rc=$?; got=$(cat "$T/copied" 2>/dev/null)
  if [[ $rc == "$2" && $got == "$3" ]]; then echo "ok   copy-pinned $1 -> rc=$rc '${got}'"; else echo "FAIL copy-pinned $1 -> rc=$rc '${got}' (want rc=$2 '$3')"; fail=1; fi; }
check 1 0 c
check 2 0 a
check 3 0 b
check 4 1 ""
check 0 1 ""
check x 1 ""
# 1.28.0: the popup's Alt+N picks the same pin as copy-pinned N.
want=$(node -e 'const H=require(process.argv[1]); const h=JSON.parse(require("fs").readFileSync(process.argv[2])); console.log([1,2,3,4].map(n=>H.pinHistoryIndex(h,n)).join(","))' "$(cd "$(dirname "$0")/.." && pwd)/ClipboardHistory.js" "$T/data/timon.clipboard/history.json")
if [[ $want == "0,2,3,-1" ]]; then echo "ok   pinHistoryIndex = copy-pinned order"; else echo "FAIL pinHistoryIndex $want"; fail=1; fi
# 1.28.0: paste sends Shift+Insert through Hyprland with explicit mods.
out=$(PATH="$T/bin:$PATH" XDG_DATA_HOME="$T/data" CLIPBOARD_PASTE_DRY=1 bash "$(dirname "$0")/../clipboard.sh" paste 1)
if [[ $out == *'mods = "SHIFT", key = "Insert", state = "down"'*'state = "up"'* ]]; then echo "ok   paste uses send_key_state SHIFT+Insert"; else echo "FAIL paste dispatch: $out"; fail=1; fi
# paste-pinned closes the popup before pasting.
out=$(PATH="$T/bin:$PATH" XDG_DATA_HOME="$T/data" PASTE_PINNED_DRY=1 bash "$(dirname "$0")/../paste-pinned.sh" 2)
if [[ $out == "hide popup"*'state = "down"'* && $(cat "$T/copied") == a ]]; then echo "ok   paste-pinned hides the popup, then pastes pin 2"; else echo "FAIL paste-pinned: $out"; fail=1; fi
exit $fail
