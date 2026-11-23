#!/bin/bash
# 1.29.0: installs one Tesseract language for OCR, in a terminal the user
# sees (Settings > OCR or the popup banner open it in Omarchy's floating
# terminal). It shows the exact command first and waits for Enter, so the
# sudo password is only ever typed after reading what runs. Nice Clipboard
# itself never holds root.
#   ocr-install.sh <code> [shown name]      e.g. ocr-install.sh deu German
# OCR_INSTALL_DRY=1: print the command instead of running it (tests).
set -u
code=${1:-}
name=${2:-}
if [[ ! $code =~ ^[a-z]{3}(_[a-z]{3,4})?$ ]]; then
  echo "Nice Clipboard: not a Tesseract language code: '$code'" >&2
  exit 2
fi
[[ $name =~ ^[A-Za-z][A-Za-z\ ().,-]{0,40}$ ]] || name=$code
cmd=(sudo pacman -S --needed "tesseract-data-$code")

printf '\nNice Clipboard will install %s text recognition:\n\n    %s\n\n' "$name" "${cmd[*]}"
printf 'Press Enter to continue, Ctrl+C to cancel. '
read -r || exit 130
echo
if [[ ${OCR_INSTALL_DRY:-0} == 1 ]]; then
  echo "(dry run) ${cmd[*]}"
  rc=0
else
  "${cmd[@]}"
  rc=$?
fi
if ((rc == 0)); then
  printf '\nDone, you can close this window. It closes by itself in 5 seconds.\n'
  sleep "${OCR_INSTALL_CLOSE_AFTER:-5}"
else
  printf '\nNot installed (pacman exited with %s). Press Enter to close.\n' "$rc"
  read -r
fi
exit $rc
