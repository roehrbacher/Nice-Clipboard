#!/bin/bash
# Run: bash tests/slots.test.sh  (fake wl-copy, temp data dir; never touches the real clipboard)
# 1.29.0: Alt+Shift+1…9, 0 slots = pinned entries first, then the newest
# history entries; clipboard.sh copy-slot, paste-slot.sh (+ old name
# paste-pinned.sh) and ClipboardHistory.slotHistoryIndex must agree.
set -u
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
here=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$T/bin" "$T/data/timon.clipboard"
printf '#!/bin/bash\ncat > "%s/copied"\n' "$T" > "$T/bin/wl-copy"; chmod +x "$T/bin/wl-copy"
fail=0
put() { printf '%s\n' "$1" > "$T/data/timon.clipboard/history.json"; }
run() { PATH="$T/bin:$PATH" XDG_DATA_HOME="$T/data" bash "$here/clipboard.sh" copy-slot "$1"; }
check() { rm -f "$T/copied"; run "$1"; rc=$?; got=$(cat "$T/copied" 2>/dev/null)
  if [[ $rc == "$2" && $got == "$3" ]]; then echo "ok   copy-slot $1 -> rc=$rc '${got}'"; else echo "FAIL copy-slot $1 -> rc=$rc '${got}' (want rc=$2 '$3')"; fail=1; fi; }
js() { node -e 'const H=require(process.argv[1]); const h=JSON.parse(require("fs").readFileSync(process.argv[2])); console.log(Array.from({length: 10}, (_, i) => H.slotHistoryIndex(h, i + 1)).join(","))' "$here/ClipboardHistory.js" "$T/data/timon.clipboard/history.json"; }

# 3 pins (c, a, b) among history h1 (newest), x, h3: slots c a b h1 x h3.
put '[{"type":"text","text":"h1"},{"type":"text","text":"c","pinned":true},{"type":"text","text":"x"},{"type":"text","text":"a","pinned":true},{"type":"text","text":"b","pinned":true},{"type":"text","text":"h3"}]'
check 1 0 c; check 2 0 a; check 3 0 b; check 4 0 h1; check 5 0 x; check 6 0 h3; check 7 1 ""
check 0 1 ""; check 11 1 ""; check x 1 ""
[[ $(js) == "1,3,4,0,2,5,-1,-1,-1,-1" ]] && echo "ok   JS slots = copy-slot" || { echo "FAIL JS slots $(js)"; fail=1; }

# 9 pins + history: slot 10 (key 0) = newest history item.
put "[$(for i in 1 2 3 4 5 6 7 8 9; do printf '{"type":"text","text":"p%s","pinned":true},' $i; done){\"type\":\"text\",\"text\":\"newest\"},{\"type\":\"text\",\"text\":\"older\"}]"
check 9 0 p9; check 10 0 newest
rm -f "$T/copied"; out=$(PATH="$T/bin:$PATH" XDG_DATA_HOME="$T/data" PASTE_PINNED_DRY=1 bash "$here/paste-slot.sh" 0)
[[ $(cat "$T/copied") == newest && $out == "hide popup"*'state = "down"'* ]] && echo "ok   paste-slot.sh 0 = slot 10 (newest history), popup hidden first" || { echo "FAIL paste-slot 0: $out"; fail=1; }
rm -f "$T/copied"; PATH="$T/bin:$PATH" XDG_DATA_HOME="$T/data" PASTE_PINNED_DRY=1 bash "$here/paste-pinned.sh" 2 >/dev/null
[[ $(cat "$T/copied") == p2 ]] && echo "ok   old name paste-pinned.sh 2 still works" || { echo "FAIL paste-pinned.sh"; fail=1; }

# 4 pins: keys 5…9, 0 = history items 1…6.
put "[$(for i in 1 2 3 4; do printf '{"type":"text","text":"p%s","pinned":true},' $i; done)$(for i in 1 2 3 4 5 6 7; do printf '{"type":"text","text":"h%s"},' $i; done | sed 's/,$//')]"
check 5 0 h1; check 9 0 h5; check 10 0 h6

# The popup paste sends Shift+Insert through Hyprland with explicit mods (1.28.0).
out=$(PATH="$T/bin:$PATH" XDG_DATA_HOME="$T/data" CLIPBOARD_PASTE_DRY=1 bash "$here/clipboard.sh" paste 1)
[[ $out == *'mods = "SHIFT", key = "Insert", state = "down"'*'state = "up"'* ]] && echo "ok   paste uses send_key_state SHIFT+Insert" || { echo "FAIL paste dispatch: $out"; fail=1; }
exit $fail
