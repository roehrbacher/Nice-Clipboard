#!/bin/bash
# Installs one Tesseract language for OCR, in a terminal the user
# sees (Settings > Text recognition or the popup banner open it in Omarchy's
# floating terminal). It shows the exact command first and waits for Enter,
# so the sudo password is only ever typed after reading what runs. Nice
# Clipboard itself never holds root.
#   ocr-install.sh <code> [shown name]            e.g. ocr-install.sh deu German
#   ocr-install.sh --remove <code> [shown name]   sudo pacman -R
# A pack this script installed is noted in <data dir>/ocr-installed (so
# "Uninstall plugin and languages" removes only those). --remove refuses a
# pack something else needs (pacman "Required By" other than tesseract, e.g.
# eng: omasnap) and the last installed language (tesseract needs one).
#   ocr-install.sh --needed-by <code>             what else needs the pack
#                                                 (also used by uninstall.sh)
# OCR_INSTALL_DRY=1: print the command instead of running it (tests).
set -u
pacman=${NICE_CLIPBOARD_PACMAN:-pacman}
# Packages that need tesseract-data-<code>, other than tesseract itself
# (pacman "Required By"), space separated; empty when nothing else does.
needed_by() {
  LC_ALL=C "$pacman" -Qi "tesseract-data-$1" 2>/dev/null | awk '/^Required By/ { on = 1; sub(/^[^:]*: /, "") } /^[A-Z]/ && !/^Required By/ { on = 0 } on' | tr -s ' \n' '\n' | grep -vxE 'tesseract|None|' | paste -sd ' '
}
remove=0
[[ ${1:-} == --remove ]] && { remove=1; shift; }
[[ ${1:-} == --needed-by ]] && { [[ ${2:-} =~ ^[a-z]{3}(_[a-z]{3,4})?$ ]] || exit 2; needed_by "$2"; exit 0; }
code=${1:-}
name=${2:-}
if [[ ! $code =~ ^[a-z]{3}(_[a-z]{3,4})?$ ]]; then
  echo "Nice Clipboard: not a Tesseract language code: '$code'" >&2
  exit 2
fi
[[ $name =~ ^[A-Za-z][A-Za-z\ ().,-]{0,40}$ ]] || name=$code
pkg=tesseract-data-$code
data="${XDG_DATA_HOME:-$HOME/.local/share}/timon.clipboard"
record="$data/ocr-installed"

if ((remove)); then
  needed=$(needed_by "$code")
  langs=$(LC_ALL=C "$pacman" -Qq 2>/dev/null | grep -E '^tesseract-data-[a-z_]+$' | grep -vx tesseract-data-osd | wc -l)
  if [[ -n $needed ]]; then
    printf '\nNice Clipboard keeps %s text recognition: %s needs it.\nPress Enter to close.\n' "$name" "$needed"; read -r; exit 3
  fi
  if ((langs <= 1)); then
    printf '\nNice Clipboard keeps %s text recognition: it is the last language, and tesseract needs one.\nPress Enter to close.\n' "$name"; read -r; exit 3
  fi
  cmd=(sudo pacman -R "$pkg")
  printf '\nNice Clipboard will remove %s text recognition:\n\n    %s\n\n' "$name" "${cmd[*]}"
else
  cmd=(sudo pacman -S --needed "$pkg")
  printf '\nNice Clipboard will install %s text recognition:\n\n    %s\n\n' "$name" "${cmd[*]}"
fi
printf 'Press Enter to continue, Ctrl+C to cancel. '
read -r || exit 130
echo
had=0
"$pacman" -Q "$pkg" >/dev/null 2>&1 && had=1
if [[ ${OCR_INSTALL_DRY:-0} == 1 ]]; then
  echo "(dry run) ${cmd[*]}"
  rc=0
else
  "${cmd[@]}"
  rc=$?
fi
if ((rc == 0)); then
  mkdir -p "$data" && chmod 700 "$data"
  if ((remove)); then
    [[ -f $record ]] && { grep -vxF "$code" "$record" > "$record.tmp"; mv "$record.tmp" "$record"; }
  elif ((!had)) && ! grep -qxF "$code" "$record" 2>/dev/null; then
    echo "$code" >> "$record"
  fi
  printf '\nDone, you can close this window. It closes by itself in 5 seconds.\n'
  sleep "${OCR_INSTALL_CLOSE_AFTER:-5}"
else
  printf '\nNothing changed (pacman exited with %s). Press Enter to close.\n' "$rc"
  read -r
fi
exit $rc
