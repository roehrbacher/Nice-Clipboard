#!/bin/bash
# Run: bash tests/uninstall.test.sh
# uninstall.sh (1.31.0) in a fake HOME with stub pacman, sudo, omarchy and
# plugin scripts: never removes anything real.
set -u
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
export HOME="$t/home" XDG_DATA_HOME="$t/home/.local/share" TMPDIR="$t" NICE_CLIPBOARD_PACMAN="$t/bin/pacman"
P="$HOME/.config/omarchy/plugins/timon.clipboard"
mkdir -p "$P" "$XDG_DATA_HOME/timon.clipboard" "$t/bin"
cp "$here/../uninstall.sh" "$P/"
for s in global-keys.sh clipboard.sh; do printf '#!/bin/bash\necho "%s $*" >> "%s/log"\n' "$s" "$t" > "$P/$s"; done
printf '#!/bin/bash\necho "sudo $*" >> "%s/log"\n' "$t" > "$t/bin/sudo"
printf '#!/bin/bash\necho "omarchy $*" >> "%s/log"\n[[ $1 == plugin && $2 == remove ]] && mv "%s" "%s/.timon.clipboard.bak.20261123"\n' "$t" "$P" "$HOME/.config/omarchy/plugins" > "$t/bin/omarchy"
cat > "$t/bin/pacman" <<'P'
#!/bin/bash
inst="deu eng ita fra"
case $1 in
  -Q) for x in $inst; do [[ $2 == tesseract-data-$x ]] && exit 0; done; exit 1 ;;
  -Qq) printf 'tesseract\ntesseract-data-osd\n'; for x in $inst; do echo "tesseract-data-$x"; done ;;
  -Qi) case $2 in
    tesseract-data-eng) printf 'Name            : tesseract-data-eng\nRequired By     : omasnap  tesseract\n' ;;
    *) printf 'Name            : %s\nRequired By     : tesseract\n' "$2" ;;
  esac ;;
esac
P
chmod +x "$t/bin/"* "$P/"*
# The plugin installed ita and eng (eng is needed by omasnap) and spa (gone since).
printf 'ita\neng\nspa\n' > "$XDG_DATA_HOME/timon.clipboard/ocr-installed"
echo '[]' > "$XDG_DATA_HOME/timon.clipboard/history.json"

out=$(printf '\n' | PATH="$t/bin:$PATH" UNINSTALL_DRY=1 UNINSTALL_CLOSE_AFTER=0 bash "$P/uninstall.sh" --languages 2>&1); rc=$?
[[ $rc == 0 && $(grep -c 'pacman -R' <<<"$out") == 2 && $(grep 'pacman -R' <<<"$out" | sed 's/.*-R //' | sort -u) == "tesseract-data-ita" ]] && echo "ok   languages: only ita (eng needed by omasnap, spa not installed, deu/fra not ours)" || { echo "FAIL langs plan: rc=$rc $out"; fail=1; }
[[ $out == *"Keeping tesseract-data-eng (omasnap needs it)"* ]] && echo "ok   says why eng stays" || { echo "FAIL eng reason"; fail=1; }
[[ $out == *"Press Enter to continue"*"(dry run) sudo pacman -R tesseract-data-ita"*"global-keys.sh remove"*"(dry run) omarchy plugin remove timon.clipboard --yes"* ]] && echo "ok   shows the commands first, then runs them in order" || { echo "FAIL order: $out"; fail=1; }
[[ ! -e $t/log && -d $P && -e $XDG_DATA_HOME/timon.clipboard/history.json ]] && echo "ok   dry run changes nothing" || { echo "FAIL dry run changed something"; fail=1; }
out=$(PATH="$t/bin:$PATH" bash "$P/uninstall.sh" </dev/null 2>&1); rc=$?
[[ $rc == 130 && ! -e $t/log && -d $P ]] && echo "ok   nothing runs without Enter" || { echo "FAIL ran without Enter: rc=$rc"; fail=1; }
out=$(printf '\n' | PATH="$t/bin:$PATH" UNINSTALL_DRY=1 UNINSTALL_CLOSE_AFTER=0 bash "$P/uninstall.sh" 2>&1)
[[ $out != *pacman* ]] && echo "ok   plugin only: no pacman" || { echo "FAIL plugin only ran pacman: $out"; fail=1; }

# Real run against the stubs.
out=$(printf '\n' | PATH="$t/bin:$PATH" UNINSTALL_CLOSE_AFTER=0 bash "$P/uninstall.sh" --languages 2>&1); rc=$?
want=$'sudo pacman -R tesseract-data-ita\nglobal-keys.sh remove\nclipboard.sh wipe\nomarchy plugin remove timon.clipboard --yes'
[[ $rc == 0 && $(cat "$t/log") == "$want" ]] && echo "ok   stub run: pacman, keys, wipe, plugin remove" || { echo "FAIL stub run rc=$rc log=$(cat "$t/log") out=$out"; fail=1; }
[[ ! -e $HOME/.config/omarchy/plugins/.timon.clipboard.bak.20261123 ]] && echo "ok   Omarchy's plugin backup folder removed too" || { echo "FAIL backup left"; fail=1; }
[[ -z $(command ls "$t" | grep nice-clipboard-uninstall) ]] && echo "ok   temp copy cleaned up" || { echo "FAIL temp copy left"; fail=1; }
exit $fail
