#!/bin/bash
# Run: bash tests/capture.test.sh   (needs jq, perl; wl-paste is stubbed)
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat >"$tmp/bin/wl-paste" <<'STUB'
#!/bin/bash
[[ ${1:-} == --list-types ]] && printf '%b' "${FAKE_TYPES:-text/plain\n}"
[[ ${1:-} == --type && ${2:-} == text ]] && printf '%s' "${FAKE_TEXT:-}"
exit 0
STUB
chmod +x "$tmp/bin/wl-paste"
# No live window: a real Hyprland session would add its "app" field.
printf "#!/bin/bash\nexit 1\n" >"$tmp/bin/hyprctl"; chmod +x "$tmp/bin/hyprctl"
export PATH="$tmp/bin:$PATH" XDG_DATA_HOME="$tmp/data"
fail=0
check() { if [[ $2 == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: got '$2' want '$3'"; fail=1; fi; }

out=$(printf 'hello world' | "$here/capture.sh" text)
check "text captured" "$out" '{"type":"text","text":"hello world"}'
check "data dir is 0700" "$(stat -c %a "$tmp/data/timon.clipboard")" 700

out=$(printf 'hunter2' | FAKE_TYPES='text/plain\nx-kde-passwordManagerHint\n' "$here/capture.sh" text)
check "password manager copy skipped" "$out" ""

out=$(printf 'secret' | CLIPBOARD_STATE=sensitive "$here/capture.sh" text)
check "sensitive clipboard state skipped" "$out" ""

echo '{"private": true}' >"$tmp/data/timon.clipboard/state.json"
out=$(printf 'private stuff' | "$here/capture.sh" text)
check "private mode skips text" "$out" ""
out=$(printf '\x89PNG\r\n\x1a\nfake' | "$here/capture.sh" image/png)
check "private mode skips images" "$out" ""
check "no image written in private mode" "$(ls "$tmp/data/timon.clipboard/images" | wc -l)" 0
echo '{"private": false}' >"$tmp/data/timon.clipboard/state.json"

out=$(printf '\x89PNG\r\n\x1a\nfake' | "$here/capture.sh" image/png | jq -r .type)
check "image captured" "$out" image
img=$(ls "$tmp/data/timon.clipboard/images")
check "image file is 0600" "$(stat -c %a "$tmp/data/timon.clipboard/images/$img")" 600
check "image size recorded" "$(printf '\x89PNG\r\n\x1a\nfake' | "$here/capture.sh" image/png | jq -r .bytes)" 12
# 1.13.2: browser "Copy image" (image + html + URL) vs screenshot tool (image only)
web='text/x-moz-url\ntext/html\nimage/png\nchromium/x-source-url\n'
out=$(printf 'https://i.example/a.webp' | FAKE_TYPES="$web" FAKE_TEXT='https://i.example/a.webp' "$here/capture.sh" text)
check "browser image copy: no separate link entry" "$out" ""
check "browser image copy: not a screenshot" "$(printf '\x89PNG\r\n\x1a\nweb' | FAKE_TYPES="$web" "$here/capture.sh" image/png | jq -r .screenshot)" false
check "screenshot tool (image only) is a screenshot" "$(printf '\x89PNG\r\n\x1a\nshot' | FAKE_TYPES='image/png\n' "$here/capture.sh" image/png | jq -r .screenshot)" true
# 1.34.1: text copied, then an image right after: the type list is read
# late and already shows the image; the text copy must not be lost.
check "text then a quick image copy: text kept" "$(printf 'copied text' | FAKE_TYPES='image/png\n' FAKE_TEXT='' "$here/capture.sh" text | jq -r .text)" "copied text"
check "plain text still captured" "$(printf 'hi' | FAKE_TYPES='text/plain\nUTF8_STRING\n' "$here/capture.sh" text | jq -r .text)" hi

out=$(head -c $((5 * 1024 * 1024)) /dev/zero | tr '\0' a | "$here/capture.sh" text)
check "huge text (>4 MiB) skipped" "$out" ""

# helper: init imports stock history once, prune drops orphans
mkdir -p "$tmp/state/omarchy"
echo '[{"type":"text","text":"from stock"}]' >"$tmp/state/omarchy/clipboard-history.json"
rm -rf "$tmp/data/timon.clipboard"
XDG_STATE_HOME="$tmp/state" "$here/clipboard.sh" init
check "stock history imported" "$(jq -r '.[0].text' "$tmp/data/timon.clipboard/history.json")" "from stock"
check "history file is 0600" "$(stat -c %a "$tmp/data/timon.clipboard/history.json")" 600
I="$tmp/data/timon.clipboard/images"
touch -d '-5 minutes' "$I/orphan.png"
"$here/clipboard.sh" prune
check "prune removes orphan images" "$(ls "$I" | wc -l)" 0

# 1.34.1: capture.sh writes the image before the popup saves its entry.
# A prune in between must not delete it (or a half-written temp file).
touch "$I/just-captured.png" "$I/clipboard.AbC123"
"$here/clipboard.sh" prune
check "prune spares images from the last minute" "$(ls "$I" | tr '\n' ' ')" "clipboard.AbC123 just-captured.png "
rm -f "$I"/*
# Copying an image again whose file is still there refreshes its time.
img=$(printf '\x89PNG\r\n\x1a\nagain' | "$here/capture.sh" image/png | jq -r .path)
touch -d '-5 minutes' "$img"
printf '\x89PNG\r\n\x1a\nagain' | "$here/capture.sh" image/png >/dev/null
"$here/clipboard.sh" prune
check "re-copied image survives a prune before its entry is saved" "$([[ -e $img ]] && echo kept || echo deleted)" kept
rm -f "$I"/*

# 1.34.1: an unreadable history.json is renamed, never rewritten.
H="$tmp/data/timon.clipboard/history.json"
printf '[{"type":"image","path":"%s/old.png","pinned":true},{"type":"te' "$I" >"$H"
orig=$(cat "$H")
touch -d '-5 minutes' "$I/old.png"
bad=$("$here/clipboard.sh" set-aside)
check "set-aside prints the new name" "$([[ $bad == history.json.bad-* ]] && echo yes || echo "no: $bad")" yes
check "set-aside keeps the file byte for byte" "$(cat "$tmp/data/timon.clipboard/$bad")" "$orig"
check "history.json is gone after set-aside" "$([[ -e $H ]] && echo there || echo gone)" gone
echo '[]' >"$H"
"$here/clipboard.sh" prune
check "images named in a set-aside file are kept" "$([[ -e $I/old.png ]] && echo kept || echo deleted)" kept
rm -f "$H"
check "set-aside without a file fails" "$("$here/clipboard.sh" set-aside; echo "rc=$?")" "rc=1"

exit $fail
