#!/bin/bash
# Run: bash tests/ocr-install.test.sh  (dry run: never calls sudo or pacman)
set -u
s="$(dirname "$0")/../ocr-install.sh"
fail=0
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
exit $fail
