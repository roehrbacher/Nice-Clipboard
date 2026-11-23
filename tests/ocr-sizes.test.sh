#!/bin/bash
# Run: bash tests/ocr-sizes.test.sh  (fake pacman; never calls the real one)
# scan.sh --sizes (1.30.0): language pack sizes from `pacman -Si`.
set -u
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
cat > "$t/pacman" <<'P'
#!/bin/bash
[[ $LC_ALL == C ]] || { echo "not C locale" >&2; exit 9; }
case $1 in
  -Ssq) printf 'tesseract-data-deu\ntesseract-data-deu_frak\ntesseract-data-osd\n' ;;
  -Si) shift; for p in "$@"; do case $p in
    tesseract-data-deu) printf 'Repository      : extra\nName            : tesseract-data-deu\nVersion         : 2:4.1.0-4\nDownload Size   : 5.94 MiB\nInstalled Size  : 14.72 MiB\n\n' ;;
    tesseract-data-deu_frak) printf 'Name            : tesseract-data-deu_frak\nDownload Size   : 752.64 KiB\nInstalled Size  : 1932.36 KiB\n\n' ;;
    tesseract-data-osd) printf 'Name            : tesseract-data-osd\nDownload Size   : 4.03 MiB\nInstalled Size  : 10.08 MiB\n\n' ;;
  esac; done ;;
esac
P
chmod +x "$t/pacman"
out=$(NICE_CLIPBOARD_PACMAN="$t/pacman" bash "$here/../scan.sh" --sizes)
want='{"deu":{"download":"5.94 MiB","installed":"14.72 MiB"},"deu_frak":{"download":"752.64 KiB","installed":"1932.36 KiB"},"osd":{"download":"4.03 MiB","installed":"10.08 MiB"}}'
[[ $out == "$want" ]] && echo "ok   sizes from pacman -Si" || { echo "FAIL sizes: $out"; fail=1; }
out=$(NICE_CLIPBOARD_PACMAN="$t/none" bash "$here/../scan.sh" --sizes)
[[ $out == '{}' ]] && echo "ok   no pacman: {}" || { echo "FAIL no pacman: $out"; fail=1; }
printf '#!/bin/bash\nexit 1\n' > "$t/empty"; chmod +x "$t/empty"
out=$(NICE_CLIPBOARD_PACMAN="$t/empty" bash "$here/../scan.sh" --sizes)
[[ $out == '{}' ]] && echo "ok   no packages: {}" || { echo "FAIL empty: $out"; fail=1; }
exit $fail
