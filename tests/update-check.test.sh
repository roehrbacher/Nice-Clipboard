#!/bin/bash
# Run: bash tests/update-check.test.sh
# update-check.sh (1.30.0) against a local fake GitHub API: never the real one.
set -u
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d)
fail=0
mkdir -p "$t/rel/releases" "$t/tags" "$t/none" "$t/rel/tags"
echo '{"tag_name":"v1.31.0","name":"x"}' > "$t/rel/releases/latest"
printf '[{"name":"v1.9.0"},{"name":"1.30.2"},{"name":"nightly"},{"name":"v1.30.10"}]' > "$t/tags/tags"
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
# Serves files; "tags?per_page=100" maps to the file "tags".
python3 - "$t" "$port" <<'PY' &
import http.server, os, sys, urllib.parse
root, port = sys.argv[1], int(sys.argv[2])
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        p = urllib.parse.urlparse(self.path).path.lstrip("/")
        f = os.path.join(root, p)
        if self.headers.get("Authorization") or self.headers.get("Cookie"):
            self.send_response(400); self.end_headers(); return
        if os.path.isfile(f):
            b = open(f, "rb").read(); self.send_response(200); self.end_headers(); self.wfile.write(b)
        else:
            self.send_response(404); self.end_headers(); self.wfile.write(b'{"message":"Not Found"}')
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
srv=$!
trap 'kill $srv 2>/dev/null; rm -rf "$t"' EXIT
for _ in $(seq 50); do curl -s "http://127.0.0.1:$port/" >/dev/null 2>&1 && break; sleep 0.1; done
run() { NICE_CLIPBOARD_UPDATE_API="http://127.0.0.1:$port/$1" bash "$here/../update-check.sh"; }
git=false; [[ -e $here/../.git ]] && git=true
out=$(run rel)
[[ $out == "{\"latest\":\"1.31.0\",\"git\":$git}" ]] && echo "ok   latest release" || { echo "FAIL release: $out"; fail=1; }
out=$(run tags)
[[ $out == "{\"latest\":\"1.30.10\",\"git\":$git}" ]] && echo "ok   no release: highest version tag" || { echo "FAIL tags: $out"; fail=1; }
out=$(run none)
[[ $out == "{\"latest\":\"\",\"git\":$git}" ]] && echo "ok   private/missing repo (404): nothing, quietly" || { echo "FAIL 404: $out"; fail=1; }
out=$(NICE_CLIPBOARD_UPDATE_API="http://127.0.0.1:1/x" bash "$here/../update-check.sh" 2>&1)
[[ $out == "{\"latest\":\"\",\"git\":$git}" ]] && echo "ok   offline: nothing, quietly" || { echo "FAIL offline: $out"; fail=1; }
exit $fail
