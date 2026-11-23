#!/bin/bash
# Run: bash tests/send.test.sh  (fake fluxd socket + fake flux-cli; never the real phone)
# 1.29.0: "Send via Flux" sends only to the phone: no wl-copy, history untouched.
set -u
T=$(mktemp -d)
here=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$T/bin" "$T/data/timon.clipboard"
printf '#!/bin/bash\necho called >> "%s/wlcopy"; cat >/dev/null\n' "$T" > "$T/bin/wl-copy"
printf '#!/bin/bash\n[[ $1 == status ]] && echo '"'"'{"devices":[{"id":"offline1","paired":true,"online":false},{"id":"dev42","paired":true,"online":true}]}'"'"'\n[[ $1 == clip ]] && echo clip >> "%s/fluxcli"\nexit 0\n' "$T" > "$T/bin/flux-cli"
chmod +x "$T/bin/"*
printf '%s\n' '[{"type":"text","text":"newest"},{"type":"text","text":"secret \"quoted\" -- text"}]' > "$T/data/timon.clipboard/history.json"
before=$(md5sum < "$T/data/timon.clipboard/history.json")
python3 - "$T/fluxd.sock" "$T/got" <<'PY' & srv=$!
import json, os, socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.bind(sys.argv[1]); s.listen(1); s.settimeout(15)
c, _ = s.accept(); f = c.makefile("rb"); line = f.readline()
open(sys.argv[2], "wb").write(line)
c.sendall(b'{"event":"state","data":{}}\n' + json.dumps({"id": json.loads(line)["id"], "result": {}}).encode() + b"\n")
PY
trap 'kill $srv 2>/dev/null; rm -rf "$T"' EXIT
for i in $(seq 1 50); do [[ -S $T/fluxd.sock ]] && break; sleep 0.1; done
fail=0
PATH="$T/bin:$PATH" XDG_DATA_HOME="$T/data" FLUX_SOCKET="$T/fluxd.sock" bash "$here/clipboard.sh" send 1; rc=$?
got=$(cat "$T/got" 2>/dev/null)
[[ $rc == 0 ]] && echo "ok   send exits 0 on fluxd's reply" || { echo "FAIL rc=$rc"; fail=1; }
[[ $(jq -r .method <<<"$got") == clipboard.send && $(jq -r .params.device <<<"$got") == dev42 && $(jq -r .params.text <<<"$got") == 'secret "quoted" -- text' ]] && echo "ok   clipboard.send to the online phone with the exact text" || { echo "FAIL request: $got"; fail=1; }
[[ ! -e $T/wlcopy ]] && echo "ok   no wl-copy (the computer's clipboard is untouched)" || { echo "FAIL wl-copy ran"; fail=1; }
[[ ! -e $T/fluxcli ]] && echo "ok   no flux-cli clip (it would send the clipboard)" || { echo "FAIL flux-cli clip ran"; fail=1; }
[[ $(md5sum < "$T/data/timon.clipboard/history.json") == "$before" ]] && echo "ok   history file unchanged" || { echo "FAIL history changed"; fail=1; }
# No socket: fails quietly, still no wl-copy.
PATH="$T/bin:$PATH" XDG_DATA_HOME="$T/data" FLUX_SOCKET="$T/none.sock" bash "$here/clipboard.sh" send 1; rc=$?
[[ $rc != 0 && ! -e $T/wlcopy ]] && echo "ok   no fluxd: exit $rc, nothing copied" || { echo "FAIL no-socket rc=$rc"; fail=1; }
exit $fail
