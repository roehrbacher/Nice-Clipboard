#!/bin/bash
# Run: bash tests/global-keys.test.sh  (stub hyprctl; never touches the live Hyprland)
set -u
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
here=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$T/bin"
cat > "$T/bin/hyprctl" <<SH
#!/bin/bash
if [[ \$1 == binds ]]; then cat "$T/binds"; exit 0; fi
echo "\$*" >> "$T/log"; echo ok
SH
chmod +x "$T/bin/hyprctl"
bind() { printf '%s\n\tmodmask: %s\n\tsubmap: %s\n\tkey: %s\n\tkeycode: 0\n\tcatchall: false\n\tdescription: %s\n\tdispatcher: __lua\n\targ: 1\n\n' "${5:-bindd}" "$1" "$2" "$3" "$4"; }
run() { PATH="$T/bin:$PATH" bash "$here/global-keys.sh" "$@"; }
fail=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

# Like Timon's machines: Alt+V and Alt+Shift+1…9 come from the shared config.
{ bind 8 "" V "Clipboard history"; for n in 1 2 3 4 5 6 7 8 9; do bind 9 "" "ALT + SHIFT + code:$((n + 9))" "Paste pinned clipboard item $n"; done; bind 64 "" "SUPER + code:19" "Workspace 10"; } > "$T/binds"
out=$(run apply)
ok "only Alt+Shift+0 is free and gets bound" '[[ $(grep -c "	bound" <<<"$out") == 1 && $out == *"Alt+Shift+0	bound"* ]]'
ok "taken keys are reported with their owner" '[[ $out == *"Alt+V	taken	Clipboard history"* && $out == *"Alt+Shift+3	taken	Paste pinned clipboard item 3"* ]]'
ok "the bind is code:19 -> paste-slot.sh 0 with our description" 'grep -q "hl.bind(\[==\[ALT + SHIFT + code:19\]==\], hl.dsp.exec_cmd(\[==\[setsid -f '"'"'$here/paste-slot.sh'"'"' 0\]==\]), { description = \[==\[Nice Clipboard: Paste clipboard slot 0\]==\] })" "$T/log"'
ok "SUPER+code:19 (other modifiers) does not count" '[[ $out != *"Alt+Shift+0	taken"* ]]'

# Fresh system: everything free -> 11 binds. Keysym and other-layout binds count as taken.
rm -f "$T/log"; bind 64 "" Return "Terminal" > "$T/binds"; out=$(run apply)
ok "fresh system: all 11 bound" '[[ $(grep -c "	bound" <<<"$out") == 11 && $(wc -l < "$T/log") == 11 ]]'
ok "Alt+V opens the popup" 'grep -q "ALT + V\]==\], hl.dsp.exec_cmd(\[==\[omarchy-shell shell toggle timon.clipboard" "$T/log"'
{ bind 9 "" exclam "someone else"; bind 9 "" "ALT + SHIFT + 2" "user key"; bind 9 "resize" "ALT + SHIFT + code:12" "in a submap"; } > "$T/binds"
out=$(run status)
ok "Shift+1 keysym (exclam) and plain 2 count as taken" '[[ $out == *"Alt+Shift+1	taken	someone else"* && $out == *"Alt+Shift+2	taken	user key"* ]]'
ok "submap binds do not block" '[[ $out == *"Alt+Shift+3	free"* ]]'

# After apply, ours are recognised; remove only drops ours.
{ bind 9 "" "ALT + SHIFT + code:19" "Nice Clipboard: Paste clipboard slot 0" bind; bind 9 "" "ALT + SHIFT + code:10" "Nice Clipboard: Paste clipboard slot 1" bind; bind 9 "" "ALT + SHIFT + code:10" "added later by the user"; bind 8 "" V "Clipboard history"; } > "$T/binds"
out=$(run status)
ok "ours shows as ours, no double bind" '[[ $out == *"Alt+Shift+0	ours"* ]]'
rm -f "$T/log"; out=$(run remove)
ok "remove unbinds ours only" '[[ $(cat "$T/log") == "eval hl.unbind([==[ALT + SHIFT + code:19]==])" && $out == *"Alt+Shift+0	removed"* ]]'
ok "a key we share with a later user bind is not unbound" '! grep -q "code:10" "$T/log"'

# Safety switch used by every test harness.
rm -f "$T/log"; : > "$T/binds"; NICE_CLIPBOARD_NO_GLOBAL_KEYS=1 run apply >/dev/null
ok "NICE_CLIPBOARD_NO_GLOBAL_KEYS=1 changes nothing" '[[ ! -e $T/log ]]'
exit $fail
