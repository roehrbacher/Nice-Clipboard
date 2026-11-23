#!/bin/bash
# 1.29.0: Nice Clipboard's own global shortcuts, without touching any
# Hyprland or Omarchy config file. The plugin adds them to the running
# Hyprland (`hyprctl eval` with hl.bind, Hyprland 0.55+ Lua config) when it
# loads and again after every Hyprland config reload (which drops runtime
# binds), and removes them when it is switched off or unloaded.
#   Alt+V                 open / close the clipboard history
#   Alt+Shift+1…9, 0      paste slot 1…10 (pins first, then newest history)
# A key that already has a bind (your config, another plugin) is left alone
# and reported; only free keys are bound. Ours carry the description prefix
# "Nice Clipboard:", which is how remove finds them.
#   global-keys.sh apply     bind the free keys; prints one status line per key
#   global-keys.sh remove    unbind ours (only where nothing else shares the key)
#   global-keys.sh status    print what apply would do, change nothing
# Output lines: "<key label>\t<bound|ours|taken|removed|error>\t<detail>".
set -u
dir=$(dirname "$(readlink -f "$0")")
mode=${1:-status}
# Tests and offscreen harnesses must never change the live Hyprland.
[[ ${NICE_CLIPBOARD_NO_GLOBAL_KEYS:-0} == 1 ]] && { echo -e "all\terror\tdisabled by NICE_CLIPBOARD_NO_GLOBAL_KEYS"; exit 0; }
[[ $dir == *"'"* ]] && { echo -e "all\terror\tplugin path contains a quote"; exit 1; }
PREFIX="Nice Clipboard:"

# label | modmask | combo for hl.bind | key names that count as the same key | command | description
targets() {
  printf '%s|8|ALT + V|v|omarchy-shell shell toggle timon.clipboard|Clipboard history\n' "Alt+V"
  local syms=("" "1 exclam" "2 at quotedbl" "3 numbersign section" "4 dollar" "5 percent" "6 asciicircum ampersand" "7 ampersand slash" "8 asterisk parenleft" "9 parenleft parenright" "0 parenright equal")
  local n key
  for n in 1 2 3 4 5 6 7 8 9 10; do
    key=$((n == 10 ? 0 : n))
    printf "%s|9|ALT + SHIFT + code:%s|code:%s %s|setsid -f '%s/paste-slot.sh' %s|Paste clipboard slot %s\n" \
      "Alt+Shift+$key" $((n + 9)) $((n + 9)) "${syms[$n]}" "$dir" "$key" "$key"
  done
}

# Current global binds as "modmask<TAB>key (last part, lower case)<TAB>description".
current() {
  timeout 3 hyprctl binds 2>/dev/null | awk '
    /^bind/ { if (have && sm == "") print mm "\t" key "\t" desc; have = 1; mm = ""; key = ""; desc = ""; sm = ""; next }
    /^\tmodmask:/ { mm = $2 }
    /^\tsubmap:/ { s = $0; sub(/^\tsubmap: ?/, "", s); sm = s }
    /^\tkey:/ { k = $0; sub(/^\tkey: /, "", k); n = split(k, parts, / \+ /); key = tolower(parts[n]) }
    /^\tdescription:/ { d = $0; sub(/^\tdescription: ?/, "", d); desc = d }
    END { if (have && sm == "") print mm "\t" key "\t" desc }'
}

lua_str() { # Lua long string; refuses text that could end it
  [[ $1 == *']==]'* ]] && return 1
  printf '[==[%s]==]' "$1"
}

binds=$(current)
if [[ -z $binds ]] && [[ $mode != status ]]; then echo -e "all\terror\tHyprland did not answer (hyprctl binds)"; exit 1; fi

rc=0
while IFS='|' read -r label mm combo names cmd desc; do
  # Who holds this key now? (same modmask, any of its key names)
  holders=$(awk -F'\t' -v mm="$mm" -v names=" $names " '$1 == mm && index(names, " " $2 " ") { print $3 }' <<<"$binds")
  others=$(grep -v "^$PREFIX" <<<"$holders" | grep -c . || true)
  ours=$(grep -c "^$PREFIX" <<<"$holders" || true)
  case $mode in
  apply|status)
    if ((others > 0)); then
      echo -e "$label\ttaken\t$(grep -v "^$PREFIX" <<<"$holders" | head -1)"
    elif ((ours > 0)); then
      echo -e "$label\tours\t"
    elif [[ $mode == status ]]; then
      echo -e "$label\tfree\t"
    else
      c=$(lua_str "$combo") && x=$(lua_str "$cmd") && d=$(lua_str "$PREFIX $desc") || { echo -e "$label\terror\tunsafe path"; rc=1; continue; }
      out=$(timeout 3 hyprctl eval "hl.bind($c, hl.dsp.exec_cmd($x), { description = $d })" 2>&1)
      if [[ $? == 0 && $out != *rror* ]]; then
        echo -e "$label\tbound\t"
      else
        echo -e "$label\terror\thyprctl eval failed"; rc=1
      fi
    fi
    ;;
  remove)
    # hl.unbind drops every bind on the key, so only when all of them are ours.
    if ((ours > 0 && others == 0)); then
      c=$(lua_str "$combo")
      out=$(timeout 3 hyprctl eval "hl.unbind($c)" 2>&1)
      if [[ $? == 0 && $out != *rror* ]]; then echo -e "$label\tremoved\t"; else echo -e "$label\terror\tunbind failed"; rc=1; fi
    fi
    ;;
  *) echo "usage: global-keys.sh apply|remove|status" >&2; exit 2 ;;
  esac
done < <(targets)
exit $rc
