#!/bin/bash
# Global Alt+Shift+1…9, 0 (hypr/shared-bindings.lua): paste slot N, i.e.
# the pinned entries first, then the newest history entries (1.29.0; key 0
# = slot 10). paste-pinned.sh is the old name and runs this.
# Started detached by the bind, so Hyprland never waits on it: wl-copy needs
# the compositor to answer, and a compositor blocked on its child deadlocks.
# Copies the entry (nothing happens if slot N is empty), then sends
# Shift+Insert with explicit mods, like the stock universal paste, so the
# held Alt+Shift don't merge in.
#   paste-slot.sh <1-9|0|10>
# PASTE_PINNED_DRY=1: copy only, print the dispatches instead of sending (tests).
set -u
# Children of Hyprland inherit a blocked SIGTERM, so the copy is capped with
# SIGKILL after 5 s instead of relying on a plain kill.
n=${1:-}
[[ $n == 0 ]] && n=10
[[ $n =~ ^([1-9]|10)$ ]] || exit 1
dir=$(dirname "$(readlink -f "$0")")
timeout -s KILL 5 "$dir/clipboard.sh" copy-slot "$n" || exit 1
# When the popup is open it has the keyboard, so the paste would
# land in its search field: close it first (no-op when it is closed).
if [[ ${PASTE_PINNED_DRY:-0} == 1 ]]; then echo "hide popup"; else timeout 2 omarchy-shell -q shell hide timon.clipboard >/dev/null 2>&1 || true; fi
send() {
  local d="hl.dsp.send_key_state({ mods = \"SHIFT\", key = \"Insert\", state = \"$1\" })"
  if [[ ${PASTE_PINNED_DRY:-0} == 1 ]]; then echo "dispatch $d"; else timeout 3 hyprctl dispatch "$d" >/dev/null; fi
}
sleep 0.15
send down
sleep 0.05
send up
