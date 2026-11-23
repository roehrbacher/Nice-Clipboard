#!/bin/bash
# Run: bash tests/paste-target.test.sh  (stub hyprctl, wl-copy and wtype in a temp PATH,
# temp data dir; never touches the real clipboard, never sends a key)
# 1.33.3: `clipboard.sh paste <index> <window>` copies the entry, focuses the
# window that had the keyboard when the popup opened (only when it isn't
# focused already) and sends Shift+Insert to that window. A window that is
# gone, or no address at all, pastes into whatever is focused (as before).
# 1.33.4: with an address there is no fixed wait before the key-down, and a
# needed focus goes out in one hyprctl --batch together with the key-down.
set -u
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
here=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$T/bin" "$T/data/timon.clipboard"
printf '#!/bin/bash\ncat > "%s/copied"\n' "$T" > "$T/bin/wl-copy"
printf '#!/bin/bash\necho "wtype $*" >> "%s/log"\n' "$T" > "$T/bin/wtype"
# hyprctl stub: "activewindow -j" answers $T/active; "dispatch" logs and
# answers ok, or the "window not found" warning for the address in $T/gone.
cat > "$T/bin/hyprctl" <<SH
#!/bin/bash
if [[ \$1 == activewindow ]]; then a=\$(cat "$T/active" 2>/dev/null); [[ -n \$a ]] && echo "{\"address\":\"\$a\"}" || echo "{}"; exit 0; fi
answer() {
  echo "\$(date +%s%N) dispatch \$1" >> "$T/times"
  echo "dispatch \$1" >> "$T/log"
  g=\$(cat "$T/gone" 2>/dev/null)
  if [[ -n \$g && \$1 == *"address:\$g"* ]]; then echo "warning: =[C]:-1: window not found"; else echo ok; fi
}
if [[ \$1 == dispatch ]]; then answer "\$2"; fi
# --batch "dispatch A ; dispatch B": one call, replies in order, blank lines between.
if [[ \$1 == --batch ]]; then
  echo "batch" >> "$T/batches"
  rest=\$2
  while [[ -n \$rest ]]; do
    c=\${rest%% ; *}; [[ \$c == "\$rest" ]] && rest="" || rest=\${rest#* ; }
    answer "\${c#dispatch }"; printf '\n\n'
  done
fi
SH
chmod +x "$T/bin/"*
printf '%s\n' '[{"type":"text","text":"zero"},{"type":"text","text":"one"}]' > "$T/data/timon.clipboard/history.json"
fail=0
run() { rm -f "$T/log" "$T/copied" "$T/times" "$T/batches"; date +%s%N > "$T/start"; PATH="$T/bin:$PATH" XDG_DATA_HOME="$T/data" bash "$here/clipboard.sh" paste "$@"; }
has() { grep -qF -- "$1" "$T/log"; }
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; sed 's/^/     /' "$T/log" 2>/dev/null; fail=1; fi; }

# Keyboard ended up on nothing (activewindow {}): focus the old window, keys go to it.
: > "$T/active"; : > "$T/gone"
run 1 55AA01
ok "copies the entry" '[[ $(cat "$T/copied") == one ]]'
ok "focuses the window from before the popup" 'has "hl.dsp.focus({ window = \"address:0x55aa01\" })"'
ok "Shift+Insert down/up go to that window" '[[ $(grep -c "send_key_state({ mods = \"SHIFT\", key = \"Insert\", state = \"[a-z]*\", window = \"address:0x55aa01\" })" "$T/log") == 2 ]]'
ok "focus comes before the keys" '[[ $(head -1 "$T/log") == *hl.dsp.focus* ]]'
ok "focus and key-down go out in one hyprctl call" '[[ $(wc -l < "$T/batches") == 1 ]]'
# No 0.15 s pause any more: the key-down follows the copy at once (1.33.3
# waited 150 ms first). Generous bound for a slow machine.
down_ms() { echo $(( ($(grep -m1 "state = \"down\"" "$T/times" | cut -d" " -f1) - $(cat "$T/start")) / 1000000 )); }
ok "key-down without the fixed wait ($(down_ms) ms)" '(( $(down_ms) < 130 ))'

# Already focused (0x prefix and case don't matter): no extra focus dispatch.
echo 0x55aa01 > "$T/active"
run 1 0x55AA01
ok "already focused: no focus dispatch" '! has "hl.dsp.focus"'
ok "already focused: keys still go to that window" 'has "window = \"address:0x55aa01\""'
ok "already focused: key-down without the fixed wait ($(down_ms) ms)" '(( $(down_ms) < 130 ))'

# The window was closed meanwhile: plain paste into whatever is focused.
: > "$T/active"; echo 0x55aa01 > "$T/gone"
run 1 55aa01
# (1.33.4: the key-down in the focus batch is refused with the focus.)
ok "window gone: plain Shift+Insert down and up, nothing reaches the old address" '[[ $(grep -c "state = \"[a-z]*\" })" "$T/log") == 2 ]] && ! has "state = \"up\", window"'

# No address (older callers, no Hyprland window): exactly the old behaviour.
: > "$T/gone"
run 0
ok "no address: still waits 0.15 s for the popup to let go ($(down_ms) ms)" '(( $(down_ms) >= 150 ))'
ok "no address: no focus, plain keys" '! has "hl.dsp.focus" && [[ $(grep -c "send_key_state" "$T/log") == 2 ]] && [[ $(cat "$T/copied") == zero ]]'
run 0 not-an-address
ok "junk address is ignored" '! has "hl.dsp.focus" && ! has "window ="'

# copy never pastes, whatever the third argument.
run_copy() { rm -f "$T/log"; PATH="$T/bin:$PATH" XDG_DATA_HOME="$T/data" bash "$here/clipboard.sh" copy 1 55aa01; }
run_copy
ok "copy sends no keys" '[[ ! -s $T/log ]]'
exit $fail
