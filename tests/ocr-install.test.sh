#!/bin/bash
# Run: bash tests/ocr-install.test.sh  (dry run: never calls sudo or pacman)
set -u
s="$(dirname "$0")/../ocr-install.sh"
fail=0
# Fake pacman (read-only queries) and own data dir: nothing real is read or written.
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export XDG_DATA_HOME="$t/data" NICE_CLIPBOARD_PACMAN="$t/pacman"
cat > "$t/pacman" <<'P'
#!/bin/bash
inst="deu eng ita"
case $1 in
  -Q) for x in $inst; do [[ $2 == tesseract-data-$x ]] && exit 0; done; exit 1 ;;
  -Qq) printf 'tesseract\ntesseract-data-osd\n'; for x in $inst; do echo "tesseract-data-$x"; done ;;
  -Qi) case $2 in
    tesseract-data-eng) printf 'Name            : tesseract-data-eng\nRequired By     : omasnap  tesseract\nOptional For    : tesseract\n' ;;
    *) printf 'Name            : %s\nRequired By     : tesseract\nOptional For    : tesseract\n' "$2" ;;
  esac ;;
esac
P
chmod +x "$t/pacman"
out=$(printf '\n' | OCR_INSTALL_DRY=1 OCR_INSTALL_CLOSE_AFTER=0 bash "$s" deu German); rc=$?
want='Nice Clipboard will install German text recognition:'
if [[ $rc == 0 && $out == *"$want"*'sudo pacman -S --needed tesseract-data-deu'*'Press Enter to continue, Ctrl+C to cancel.'*'(dry run) sudo pacman -S --needed tesseract-data-deu'*'Done, you can close this window.'* ]]; then
  echo "ok   shows the command, waits for Enter, runs it, says done"
else echo "FAIL dry run: rc=$rc $out"; fail=1; fi
# No Enter (stdin closed, like Ctrl+D): nothing runs.
out=$(OCR_INSTALL_DRY=1 bash "$s" fra French </dev/null); rc=$?
[[ $rc != 0 && $out != *"(dry run)"* ]] && echo "ok   nothing runs without Enter" || { echo "FAIL ran without Enter: $out"; fail=1; }
for bad in "" de "deu; rm -rf ~" "DEU" "../x" "deu fra"; do
  out=$(printf '\n' | OCR_INSTALL_DRY=1 bash "$s" "$bad" 2>&1); rc=$?
  [[ $rc == 2 && $out != *pacman* ]] && echo "ok   rejects '$bad'" || { echo "FAIL accepted '$bad'"; fail=1; }
done
out=$(printf '\n' | OCR_INSTALL_DRY=1 OCR_INSTALL_CLOSE_AFTER=0 bash "$s" ita '$(id)'); 
[[ $out == *"install ita text recognition"* ]] && echo "ok   odd names fall back to the code" || { echo "FAIL name: $out"; fail=1; }
# 1.31.0: installs are recorded (only packs that were not there before).
printf '\n' | OCR_INSTALL_DRY=1 OCR_INSTALL_CLOSE_AFTER=0 bash "$s" fra French >/dev/null
printf '\n' | OCR_INSTALL_DRY=1 OCR_INSTALL_CLOSE_AFTER=0 bash "$s" deu German >/dev/null
[[ $(cat "$XDG_DATA_HOME/timon.clipboard/ocr-installed" 2>/dev/null) == fra ]] && echo "ok   records new installs only (fra yes, deu was there)" || { echo "FAIL record: $(cat "$XDG_DATA_HOME/timon.clipboard/ocr-installed" 2>&1)"; fail=1; }
out=$(printf '\n' | OCR_INSTALL_DRY=1 OCR_INSTALL_CLOSE_AFTER=0 bash "$s" --remove ita Italian); rc=$?
[[ $rc == 0 && $out == *'sudo pacman -R tesseract-data-ita'*'Press Enter to continue'*'(dry run) sudo pacman -R tesseract-data-ita'* ]] && echo "ok   remove shows sudo pacman -R first, waits, runs" || { echo "FAIL remove: rc=$rc $out"; fail=1; }
printf '\n' | OCR_INSTALL_DRY=1 OCR_INSTALL_CLOSE_AFTER=0 bash "$s" --remove fra French >/dev/null
[[ ! -s $XDG_DATA_HOME/timon.clipboard/ocr-installed ]] && echo "ok   remove drops it from the record" || { echo "FAIL record after remove"; fail=1; }
out=$(printf '\n' | OCR_INSTALL_DRY=1 bash "$s" --remove eng English); rc=$?
[[ $rc == 3 && $out == *"omasnap needs it"* && $out != *"dry run"* ]] && echo "ok   eng kept: omasnap needs it" || { echo "FAIL eng protect: rc=$rc $out"; fail=1; }
[[ $(bash "$s" --needed-by eng) == omasnap && -z $(bash "$s" --needed-by deu) && $(bash "$s" --needed-by "x;y"; echo $?) == 2 ]] && echo "ok   --needed-by: eng omasnap, deu nothing, odd codes refused" || { echo "FAIL --needed-by"; fail=1; }
printf '#!/bin/bash\ncase $1 in -Qq) printf "tesseract-data-osd\\ntesseract-data-deu\\n";; -Qi) printf "Name : x\\nRequired By : tesseract\\n";; esac\n' > "$t/one"; chmod +x "$t/one"
out=$(printf '\n' | NICE_CLIPBOARD_PACMAN="$t/one" OCR_INSTALL_DRY=1 bash "$s" --remove deu German); rc=$?
[[ $rc == 3 && $out == *"last language"* ]] && echo "ok   last language kept" || { echo "FAIL last: rc=$rc $out"; fail=1; }
exit $fail
