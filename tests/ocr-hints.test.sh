#!/bin/bash
# 1.27.0: scan.sh --langs reports language hints (locale, LANGUAGE,
# keyboard layouts as kb:<layout>) and never installs anything.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/cfg"
cat > "$tmp/bin/hyprctl" <<'H'
#!/bin/bash
[[ "$*" == "-j getoption input:kb_layout" ]] && echo '{"option":"input:kb_layout","str":"at,us","set":true}'
H
cat > "$tmp/bin/sudo" <<'H'
#!/bin/bash
echo "sudo must never run" >&2; exit 99
H
chmod +x "$tmp/bin/"*
echo 'LANG=fr_FR.UTF-8' > "$tmp/cfg/locale.conf"
out=$(env -i HOME="$tmp" PATH="$tmp/bin:/usr/bin:/bin" XDG_CONFIG_HOME="$tmp/cfg" \
  LANG=de_AT.UTF-8 LANGUAGE=de_AT:en LC_TIME=de_AT.UTF-8 bash "$here/scan.sh" --langs)
fail() { echo "FAIL: $*"; echo "$out"; exit 1; }
jq -e . >/dev/null <<<"$out" || fail "not JSON"
hints=$(jq -r '.hints[]' <<<"$out")
for want in de_AT.UTF-8 de_AT en fr_FR.UTF-8 kb:at kb:us; do grep -qxF "$want" <<<"$hints" || fail "missing hint $want"; done
[[ $(grep -cxF de_AT.UTF-8 <<<"$hints") == 1 ]] || fail "hints not de-duplicated"
jq -e '.installed | type == "array"' >/dev/null <<<"$out" || fail "installed missing"
# The mapping (hint -> tesseract code) itself: tests/history.test.js.
node -e '
const H = require(process.argv[1]); const hints = JSON.parse(process.argv[2]).hints
const s = H.ocrSuggestions(hints, ["eng"], [])
if (!s.map(x => x.code).join().startsWith("deu,fra")) { console.error("FAIL suggestions", JSON.stringify(s)); process.exit(1) }
' "$here/ClipboardHistory.js" "$out"
echo "ok ocr-hints"
