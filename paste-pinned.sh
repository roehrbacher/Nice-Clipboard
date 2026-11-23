#!/bin/bash
# Old name (older Hyprland binds call it): same as paste-slot.sh, so
# Alt+Shift+N keeps working. Slot N = pinned entries first, then the newest
# history entries.
exec "$(dirname "$(readlink -f "$0")")/paste-slot.sh" "$@"
