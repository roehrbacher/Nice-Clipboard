#!/bin/bash
# 1.31.0: Settings > Uninstall. Runs in Omarchy's floating terminal, shows
# every command first and waits for Enter (Ctrl+C cancels).
#   uninstall.sh               the plugin, its runtime keys and its data
#   uninstall.sh --languages   also the OCR packs Nice Clipboard installed
# Languages: only packs listed in <data dir>/ocr-installed (installed by
# ocr-install.sh) that are still installed, that nothing else needs (pacman
# "Required By" other than tesseract) and never the last one. Packs that were
# there before Nice Clipboard are never touched.
# UNINSTALL_DRY=1: print the commands instead of running them (tests).
set -u
id=timon.clipboard
plugin=$(cd "$(dirname "$0")" && pwd)
# The plugin folder goes away below: run from a copy.
if [[ -z ${NICE_CLIPBOARD_UNINSTALL_COPY:-} ]]; then
  copy=$(mktemp "${TMPDIR:-/tmp}/nice-clipboard-uninstall.XXXXXX") || exit 1
  cp "$0" "$copy"
  NICE_CLIPBOARD_UNINSTALL_COPY=$copy NICE_CLIPBOARD_PLUGIN_DIR=$plugin exec bash "$copy" "$@"
fi
trap 'rm -f "$NICE_CLIPBOARD_UNINSTALL_COPY"' EXIT
plugin=${NICE_CLIPBOARD_PLUGIN_DIR:-$plugin}
data="${XDG_DATA_HOME:-$HOME/.local/share}/$id"
pacman=${NICE_CLIPBOARD_PACMAN:-pacman}
langs=()
if [[ ${1:-} == --languages && -r $data/ocr-installed ]]; then
  mapfile -t all < <(LC_ALL=C "$pacman" -Qq 2>/dev/null | grep -E '^tesseract-data-[a-z_]+$' | grep -vx tesseract-data-osd)
  left=${#all[@]}
  while read -r code; do
    [[ $code =~ ^[a-z]{3}(_[a-z]{3,4})?$ ]] || continue
    "$pacman" -Q "tesseract-data-$code" >/dev/null 2>&1 || continue
    needed=$(LC_ALL=C "$pacman" -Qi "tesseract-data-$code" 2>/dev/null | awk '/^Required By/ { on = 1; sub(/^[^:]*: /, "") } /^[A-Z]/ && !/^Required By/ { on = 0 } on' | tr -s ' \n' '\n' | grep -vxE 'tesseract|None|' | paste -sd ' ')
    if [[ -n $needed ]]; then echo "Keeping tesseract-data-$code ($needed needs it)."; continue; fi
    if ((left <= 1)); then echo "Keeping tesseract-data-$code (the last language; tesseract needs one)."; continue; fi
    langs+=("tesseract-data-$code"); left=$((left - 1))
  done < "$data/ocr-installed"
fi

steps=()
((${#langs[@]})) && steps+=("sudo pacman -R ${langs[*]}")
steps+=("$plugin/global-keys.sh remove" "$plugin/clipboard.sh wipe" "omarchy plugin remove $id --yes" "rm -rf $HOME/.config/omarchy/plugins/.$id.bak.*")
printf '\nNice Clipboard will be uninstalled%s:\n\n' "$( ((${#langs[@]})) && echo " with the text recognition languages it installed")"
printf '    %s\n' "${steps[@]}"
cat <<'TXT'

That removes the Alt+V / Alt+Shift+1…9, 0 keys it added, the clipboard
history and settings (Flux is resumed if incognito had paused it) and the
plugin itself; Omarchy's own clipboard comes back.
TXT
[[ ${1:-} == --languages && ${#langs[@]} == 0 ]] && echo "No language packs to remove (none were installed by Nice Clipboard, or they are needed)."
printf '\nPress Enter to continue, Ctrl+C to cancel. '
read -r || exit 130
echo
run() {
  if [[ ${UNINSTALL_DRY:-0} == 1 ]]; then echo "(dry run) $*"; return 0; fi
  "$@"
}
rc=0
if ((${#langs[@]})); then run sudo pacman -R "${langs[@]}" || { rc=$?; echo "pacman exited with $rc; the languages stay, the rest continues."; }; fi
run "$plugin/global-keys.sh" remove || true
run "$plugin/clipboard.sh" wipe || true
run omarchy plugin remove "$id" --yes || rc=$?
for b in "$HOME/.config/omarchy/plugins/.$id.bak."*; do [[ -e $b ]] && run rm -rf "$b"; done
if ((rc == 0)); then printf '\nNice Clipboard is uninstalled. You can close this window.\n'
else printf '\nSomething did not finish (exit %s); see above. Press Enter to close.\n' "$rc"; read -r; fi
sleep "${UNINSTALL_CLOSE_AFTER:-5}"
exit $rc
