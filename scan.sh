#!/bin/bash
# timon.clipboard: reads text (tesseract OCR) and QR codes (zbarimg) from one
# stored clipboard image and prints {"ocr","qr","complete"} as JSON on stdout.
# Runs niced in the background; the text is never logged or put in argv.
#   scan.sh <image-path>          (only files inside the plugin's image dir)
set -uo pipefail
umask 077
IMAGE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/timon.clipboard/images"

# OCR languages (1.19.0): only language packs that are installed are used;
# nothing is ever downloaded. Like Omarchy's own omarchy-capture-text,
# OMARCHY_OCR_LANGS (e.g. "eng+deu") picks them; without it every installed
# pack is used (English first, at most 3, so a scan stays quick).
#   scan.sh --langs     print {"installed":[...],"used":"eng+deu","env":"...","hints":[...]}
#   scan.sh --sizes     language pack sizes from pacman (see below)
ocr_installed() { tesseract --list-langs 2>/dev/null | tail -n +2 | grep -vxE 'osd|equ|snum' | sort -u; }
ocr_langs() {
  local have want picked=()
  have=$(ocr_installed)
  [[ -n $have ]] || return 0
  if [[ -n ${OMARCHY_OCR_LANGS:-} ]]; then
    for want in ${OMARCHY_OCR_LANGS//+/ }; do grep -qx "$want" <<<"$have" && picked+=("$want"); done
  fi
  if (( ${#picked[@]} == 0 )); then
    grep -qx eng <<<"$have" && picked+=(eng)
    while read -r want; do [[ $want == eng ]] || picked+=("$want"); done <<<"$have"
    picked=("${picked[@]:0:3}")
  fi
  local IFS=+; echo "${picked[*]}"
}
# 1.27.0: "hints" (for the "install OCR for German?" suggestion): locale
# values, Hyprland keyboard layouts ("kb:de") and hunspell dictionaries
# ("dict:de_AT"). Read-only; nothing is installed.
lang_hints() {
  local v f l
  for v in "${LANG:-}" "${LC_ALL:-}" "${LC_MESSAGES:-}" "${LC_CTYPE:-}" "${LC_TIME:-}" "${LC_NUMERIC:-}" "${LC_MONETARY:-}" "${LC_PAPER:-}" "${LC_ADDRESS:-}" "${LC_TELEPHONE:-}" "${LC_MEASUREMENT:-}"; do
    [[ -n $v ]] && echo "$v"
  done
  [[ -n ${LANGUAGE:-} ]] && tr ':' '\n' <<<"$LANGUAGE"
  for f in /etc/locale.conf "${XDG_CONFIG_HOME:-$HOME/.config}/locale.conf"; do
    [[ -r $f ]] && sed -nE 's/^(LANG|LANGUAGE|LC_[A-Z]+)="?([^"]*)"?$/\2/p' "$f" | tr ':' '\n'
  done
  if command -v hyprctl >/dev/null; then
    timeout 2 hyprctl -j getoption input:kb_layout 2>/dev/null | jq -r '.str // empty' 2>/dev/null \
      | tr ',' '\n' | while read -r l; do [[ -n $l ]] && echo "kb:$l"; done
  fi
  for f in /usr/share/hunspell/*.dic; do [[ -e $f ]] && { l=${f##*/}; echo "dict:${l%.dic}"; }; done
  return 0
}
if [[ ${1:-} == --langs ]]; then
  hints=$(lang_hints | awk 'NF && !seen[$0]++')
  if ! command -v tesseract >/dev/null; then
    jq -cn --arg hints "$hints" '{installed: [], used: "", env: "", hints: ($hints | split("\n") | map(select(. != "")))}'
    exit 0
  fi
  jq -cn --arg inst "$(ocr_installed)" --arg used "$(ocr_langs)" --arg env "${OMARCHY_OCR_LANGS:-}" --arg hints "$hints" \
    '{installed: ($inst | split("\n") | map(select(. != ""))), used: $used, env: $env, hints: ($hints | split("\n") | map(select(. != "")))}'
  exit 0
fi
# 1.30.0: real sizes of the tesseract language packs, read from the local
# pacman sync database (pacman -Si; no network, no root, nothing installed):
#   scan.sh --sizes     print {"deu":{"download":"5.94 MiB","installed":"14.72 MiB"},...}
# {} when pacman or the packages are missing.
if [[ ${1:-} == --sizes ]]; then
  pacman=${NICE_CLIPBOARD_PACMAN:-pacman}
  command -v "$pacman" >/dev/null || { echo '{}'; exit 0; }
  mapfile -t pkgs < <(LC_ALL=C "$pacman" -Ssq '^tesseract-data-' 2>/dev/null | grep -E '^tesseract-data-[a-z_]+$')
  ((${#pkgs[@]})) || { echo '{}'; exit 0; }
  LC_ALL=C timeout 10 "$pacman" -Si "${pkgs[@]}" 2>/dev/null |
    awk -F' *: ' '/^Name/ { n = $2 } /^Download Size/ { d = $2 } /^Installed Size/ { if (n != "") print n "\t" d "\t" $2; n = "" }' |
    jq -cRn '[inputs | split("\t") | select(length == 3) | {key: (.[0] | sub("^tesseract-data-"; "")), value: {download: .[1], installed: .[2]}}] | from_entries'
  exit 0
fi
img=${1:-}
[[ $img == "$IMAGE_DIR"/* && -r $img ]] || exit 1

# QR codes (1.18.0): zbar (in Omarchy's base packages) misses many real
# codes: styled/rounded modules, screenshots cropped without the white quiet
# zone, light-on-dark codes. ZXing (zxing-cpp's ZXingReader, present on
# Omarchy via LibreOffice / GStreamer) reads those, also inverted ones, so
# it goes first; zbar is the fallback, retried with a white border added
# (ImageMagick) for tightly cropped codes.
complete=true ocr="" qr=""
if command -v ZXingReader >/dev/null; then
  qr=$(timeout 15s nice -n 19 ZXingReader -single -formats QRCode -bytes "$img" 2>/dev/null | head -c 4096)
fi
if [[ -z $qr ]] && command -v zbarimg >/dev/null; then
  qr=$(timeout 15s nice -n 19 zbarimg --quiet --raw -- "$img" 2>/dev/null | head -c 4096)
  if [[ -z $qr ]] && command -v magick >/dev/null; then
    qr=$(timeout 15s nice -n 19 magick "$img" -bordercolor white -border 10% png:- 2>/dev/null | timeout 15s nice -n 19 zbarimg --quiet --raw - 2>/dev/null | head -c 4096)
  fi
elif ! command -v ZXingReader >/dev/null; then
  complete=false
fi
# OCR (1.20.0): the QR code itself is painted over first (ZXing gives its
# corners), so its modules can't turn into junk lines; then tesseract's
# word confidences drop low-confidence words, icons read as symbols next to
# labels and symbol-only lines (ocr-clean.awk). The masked copy is a private
# temp file, removed right away.
qr_box() {
  command -v ZXingReader >/dev/null && command -v magick >/dev/null || return 1
  timeout 15s nice -n 19 ZXingReader -single -formats QRCode "$1" 2>/dev/null | awk '
    /^Position:/ { x0 = y0 = 1e9; x1 = y1 = -1
      for (i = 2; i <= NF; i++) { split($i, p, "x"); if (p[1] < x0) x0 = p[1]; if (p[1] > x1) x1 = p[1]; if (p[2] < y0) y0 = p[2]; if (p[2] > y1) y1 = p[2] }
      m = int((x1 - x0) * 0.08) + 4
      x0 -= m; y0 -= m; x1 += m; y1 += m; if (x0 < 0) x0 = 0; if (y0 < 0) y0 = 0
      printf "%d,%d %d,%d\n", x0, y0, x1, y1; exit }'
}
if command -v tesseract >/dev/null; then
  langs=$(ocr_langs); [[ -n $langs ]] || langs=eng
  src=$img masked=""
  if [[ -n $qr ]] && box=$(qr_box "$img") && [[ -n $box ]]; then
    masked=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/timon-clipboard-scan.XXXXXX.png") && trap 'rm -f "$masked"' EXIT
    if timeout 15s nice -n 19 magick "$img" -fill white -draw "rectangle $box" "$masked" 2>/dev/null; then src=$masked; fi
  fi
  ocr=$(OMP_THREAD_LIMIT=1 timeout 30s nice -n 19 tesseract "$src" - -l "$langs" tsv 2>/dev/null | awk -f "$(dirname "$(readlink -f "$0")")/ocr-clean.awk" | head -c 8192)
  [[ -n $masked ]] && rm -f "$masked"
else
  complete=false
fi
jq -cn --arg ocr "$ocr" --arg qr "$qr" --argjson complete "$complete" '{ocr: ($ocr | gsub("^\\s+|\\s+$"; "")), qr: ($qr | gsub("^\\s+|\\s+$"; "")), complete: $complete}'
