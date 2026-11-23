#!/bin/bash
# timon.clipboard helper. Entries are always read from the history file by
# index, so clipboard text never shows up in a process list or a log.
#
#   clipboard.sh init                     create the data dir (user-only), import stock history once
#   clipboard.sh paste <index>            copy entry <index> and paste it (Shift+Insert)
#   clipboard.sh copy <index>             copy entry <index> only
#   clipboard.sh copy-slot <1-10>         copy slot n: pinned entries first, then the newest
#                                         history ones (global Alt+Shift+1…9, 0; paste-slot.sh)
#   clipboard.sh paste-md <index>         paste the HTML of entry <index> as Markdown:
#                                         pandoc if installed, else html2md.py; plain text if both fail
#   clipboard.sh markdown <index>         print that Markdown (tests)
#   clipboard.sh current                  print a key of what is on the clipboard (text:<md5> or
#                                         image:<sha256>), for the "on the clipboard" mark
#   clipboard.sh send <index>             send text entry <index> to the phone through fluxd's socket
#                                         (the local clipboard is not touched)
#   clipboard.sh open <index>             open a URL in the browser, text in the editor, an image in the editor
#   clipboard.sh clear                    empty the live clipboard
#   clipboard.sh prune                    delete stored images no entry points to
#   clipboard.sh wipe                     resume Flux if we paused it, delete all stored history (used by uninstall)

set -uo pipefail
umask 077

DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/timon.clipboard"
HISTORY="$DATA_DIR/history.json"
IMAGE_DIR="$DATA_DIR/images"
STOCK_HISTORY="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/clipboard-history.json"

field() { jq -er --argjson i "$1" ".[\$i].$2" "$HISTORY" 2>/dev/null; }

valid_index() { [[ ${1:-} =~ ^[0-9]+$ ]] && [[ -r $HISTORY ]]; }

copy_entry() {
  local i=$1 type mime path
  type=$(field "$i" type) || return 1
  case $type in
  text)
    jq -j --argjson i "$i" '.[$i].text' "$HISTORY" | wl-copy
    ;;
  image)
    mime=$(field "$i" mime) || mime=image/png
    path=$(field "$i" path) || return 1
    [[ -r $path ]] || return 1
    wl-copy --type "$mime" <"$path"
    ;;
  *) return 1 ;;
  esac
}

# Shift+Insert through Hyprland with explicit mods (as paste-slot.sh
# does), so keys still held from the shortcut (Alt of Alt+1) do not merge in:
# wtype's virtual keyboard shares the modifier state, and Alt+Shift+Insert
# pastes nothing. wtype stays the fallback when hyprctl is missing or fails.
# CLIPBOARD_PASTE_DRY=1 prints the dispatches instead (tests).
send_paste() {
  local d='hl.dsp.send_key_state({ mods = "SHIFT", key = "Insert", state = "%s" })'
  if [[ ${CLIPBOARD_PASTE_DRY:-0} == 1 ]]; then printf "dispatch $d\n" down up; return 0; fi
  # shellcheck disable=SC2059
  if command -v hyprctl >/dev/null && [[ $(timeout 3 hyprctl dispatch "$(printf "$d" down)" 2>/dev/null) == ok ]]; then
    sleep 0.05
    timeout 3 hyprctl dispatch "$(printf "$d" up)" >/dev/null 2>&1 || timeout 3 hyprctl dispatch "$(printf "$d" up)" >/dev/null 2>&1
    return 0
  fi
  wtype -M shift -k Insert -m shift 2>/dev/null || true
}

case "${1:-}" in
init)
  mkdir -p "$IMAGE_DIR"
  chmod 700 "$DATA_DIR" "$IMAGE_DIR"
  if [[ ! -e $HISTORY ]]; then
    # One-time import of the stock Omarchy history so nothing is lost.
    if [[ -r $STOCK_HISTORY ]] && jq -e 'type == "array"' "$STOCK_HISTORY" >/dev/null 2>&1; then
      jq '.' "$STOCK_HISTORY" >"$HISTORY.tmp" && mv "$HISTORY.tmp" "$HISTORY"
    else
      echo '[]' >"$HISTORY"
    fi
  fi
  [[ -e $DATA_DIR/state.json ]] || echo '{"private": false}' >"$DATA_DIR/state.json"
  chmod 600 "$HISTORY" "$DATA_DIR/state.json"
  ;;
paste | copy)
  valid_index "${2:-}" || exit 1
  copy_entry "$2" || exit 1
  [[ $1 == copy ]] && exit 0
  sleep 0.15
  send_paste
  ;;
current)
  # "empty" when nothing is on the clipboard at all (the popup then
  # puts the top pinned item there); a timeout prints nothing (unknown).
  types=$(timeout 2s wl-paste --list-types 2>/dev/null); rc=$?
  (( rc == 124 || rc == 127 )) && exit 0
  [[ -z ${types//[[:space:]]/} ]] && { echo empty; exit 0; }
  grep -qx 'x-kde-passwordManagerHint' <<<"$types" && exit 0
  mime=""  # same order as capture.sh, so the hash matches the stored file
  for m in image/png image/jpeg image/webp image/gif image/bmp image/tiff; do grep -qx "$m" <<<"$types" && { mime=$m; break; }; done
  if [[ -n $mime ]]; then
    echo "image:$(timeout 3s wl-paste --type "$mime" 2>/dev/null | sha256sum | awk '{print $1}')"
  elif grep -qE '^text/|^UTF8_STRING$|^STRING$' <<<"$types"; then
    echo "text:$(timeout 2s wl-paste --type text --no-newline 2>/dev/null | md5sum | awk '{print $1}')"
  fi
  ;;
markdown | paste-md)
  valid_index "${2:-}" || exit 1
  [[ $(field "$2" type) == text ]] || exit 1
  md=""
  if jq -e --argjson i "$2" '.[$i].html | type == "string" and length > 0' "$HISTORY" >/dev/null 2>&1; then
    if command -v pandoc >/dev/null; then
      md=$(jq -j --argjson i "$2" '.[$i].html' "$HISTORY" | timeout 10s pandoc -f html -t gfm-raw_html --wrap=none 2>/dev/null)
    fi
    if [[ -z ${md//[[:space:]]/} ]] && command -v python3 >/dev/null; then
      md=$(jq -j --argjson i "$2" '.[$i].html' "$HISTORY" | timeout 10s python3 "$(dirname "$(readlink -f "$0")")/html2md.py" 2>/dev/null)
    fi
  fi
  # Degrade gracefully: no HTML or no converter = the plain text.
  [[ -n ${md//[[:space:]]/} ]] || md=$(jq -j --argjson i "$2" '.[$i].text' "$HISTORY")
  if [[ $1 == markdown ]]; then printf '%s\n' "$md"; exit 0; fi
  # The Markdown is a paste, not a copy: capture.sh drops the one
  # copy whose hash is in skip-next (and nothing else), so it never becomes
  # a history entry. Afterwards the entry itself goes back on the clipboard.
  printf '%s' "$md" | sha256sum | awk '{print $1}' >"$DATA_DIR/skip-next"
  printf '%s' "$md" | wl-copy || exit 1
  sleep 0.15
  send_paste
  # The target app reads the paste on its own time; give it a second, then
  # restore only if the clipboard still holds our Markdown.
  sleep 1
  if [[ $(wl-paste --no-newline --type text 2>/dev/null | sha256sum | awk '{print $1}') == "$(printf '%s' "$md" | sha256sum | awk '{print $1}')" ]]; then
    copy_entry "$2" || true
  fi
  rm -f "$DATA_DIR/skip-next"
  ;;
copy-slot)
  # Slot 1…10 (key 0 = 10): pinned entries first (history order),
  # then the newest unpinned ones. Same as ClipboardHistory.slotHistoryIndex.
  [[ ${2:-} =~ ^([1-9]|10)$ && -r $HISTORY ]] || exit 1
  i=$(jq -r --argjson n "$2" '([to_entries[] | select(.value.pinned == true) | .key] + [to_entries[] | select(.value.pinned != true) | .key])[$n - 1] // empty' "$HISTORY") || exit 1
  [[ -n $i ]] || exit 1
  copy_entry "$i" || exit 1
  ;;
send)
  # Straight to fluxd's socket (the same "clipboard.send" call the
  # Flux window uses), so the computer's clipboard and the history order are
  # left alone. The text goes over the socket, never through argv.
  valid_index "${2:-}" || exit 1
  [[ $(field "$2" type) == text ]] || exit 1
  sock=${FLUX_SOCKET:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/flux/fluxd.sock}
  [[ -S $sock ]] || exit 1
  dev=$(timeout 5 flux-cli status --json 2>/dev/null | jq -r '[.devices[]? | select(.paired == true and .online == true)][0].id // empty') || exit 1
  [[ -n $dev ]] || exit 1
  jq -c --argjson i "$2" --arg d "$dev" '{id: 1, method: "clipboard.send", params: {device: $d, text: .[$i].text}}' "$HISTORY" |
    timeout 10 python3 -c '
import json, socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(8)
s.connect(sys.argv[1])
s.sendall(sys.stdin.buffer.read().rstrip(b"\n") + b"\n")
buf = b""
while True:
    chunk = s.recv(65536)
    if not chunk:
        sys.exit(1)
    buf += chunk
    while b"\n" in buf:
        line, buf = buf.split(b"\n", 1)
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if isinstance(msg, dict) and msg.get("id") == 1:
            sys.exit(1 if msg.get("error") else 0)
' "$sock" || exit 1
  ;;
open)
  valid_index "${2:-}" || exit 1
  type=$(field "$2" type) || exit 1
  if [[ $type == image ]]; then
    path=$(field "$2" path) || exit 1
    [[ -r $path ]] && exec tensaku-edit "$path"
    exit 1
  fi
  text=$(jq -j --argjson i "$2" '.[$i].text' "$HISTORY") || exit 1
  url=$(grep -Eom1 'https?://[^[:space:]"'\''<>]+' <<<"$text" || true)
  if [[ -z $url && $text =~ ^[[:space:]]*([[:alnum:]][[:alnum:].-]+\.[[:alpha:]]{2,})(/[^[:space:]]*)?[[:space:]]*$ ]]; then
    url="https://${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
  fi
  [[ -n $url ]] && exec omarchy-launch-browser "$url"
  mkdir -p "$DATA_DIR/open"
  find "$DATA_DIR/open" -type f -mmin +60 -delete 2>/dev/null
  file=$(mktemp --tmpdir="$DATA_DIR/open" clip.XXXXXX.txt) || exit 1
  printf '%s' "$text" >"$file"
  exec omarchy-launch-editor "$file"
  ;;
clear)
  wl-copy --clear
  ;;
prune)
  [[ -r $HISTORY && -d $IMAGE_DIR ]] || exit 0
  keep=$(jq -r '.[] | select(.type == "image") | .path' "$HISTORY" 2>/dev/null) || exit 0
  for f in "$IMAGE_DIR"/*; do
    [[ -f $f ]] || continue
    grep -qxF "$f" <<<"$keep" || rm -f "$f"
  done
  ;;
wipe)
  # Never leave Flux paused behind when the plugin goes away.
  "$(dirname "$0")/flux-pause.sh" resume >/dev/null 2>&1
  rm -rf "$DATA_DIR" "${XDG_STATE_HOME:-$HOME/.local/state}/timon.clipboard"
  ;;
*)
  sed -n '2,17p' "$0" >&2
  exit 1
  ;;
esac
