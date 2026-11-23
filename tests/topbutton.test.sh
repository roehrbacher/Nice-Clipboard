#!/bin/bash
# Run: bash tests/topbutton.test.sh  (offscreen, no GPU: Qt's OpenGL renderer
# on Mesa's software rasterizer, the same scene graph path as the shell, at
# scale 1 and 1.6 like the XPS)
# 1.33.4: rows scrolled under the floating "Top" button must not show
# through its border. The harness renders the popup scrolled to the end
# twice, with the rows' text and with the rows hidden; every pixel of the
# button (border included) must be the same in both.
set -u
here=$(cd "$(dirname "$0")" && pwd)
if ! python3 -c 'import PIL' 2>/dev/null; then echo "skip: python3 PIL missing"; exit 0; fi
fail=0
for scale in 1 1.6; do
  d=$(mktemp -d)
  out=$(QT_SCALE_FACTOR=$scale LIBGL_ALWAYS_SOFTWARE=1 QSG_RHI_BACKEND=opengl HARNESS_QUICK_BACKEND=rhi bash "$here/geometry/run-harness.sh" v1334 "$d" 2>&1)
  rect=$(sed -n 's/.*V1334 TOPRECT //p' <<<"$out" | head -1)
  if [[ -z $rect || ! -s $d/top-text.png || ! -s $d/top-blank.png ]]; then echo "FAIL scale $scale: no render"; fail=1; rm -rf "$d"; continue; fi
  # $rect is "x y w h window-width", one argument each.
  # shellcheck disable=SC2086
  python3 - "$d" $rect "$scale" <<'PY' || fail=1
import sys
from PIL import Image, ImageChops
d, x, y, w, h, winw, scale = sys.argv[1], *map(float, sys.argv[2:7]), sys.argv[7]
a = Image.open(d + "/top-text.png").convert("RGB"); b = Image.open(d + "/top-blank.png").convert("RGB")
s = a.width / winw
x0, y0, x1, y1 = int(x * s), int(y * s), int((x + w) * s + 0.999), int((y + h) * s + 0.999)
diff = ImageChops.difference(a.crop((x0, y0, x1, y1)), b.crop((x0, y0, x1, y1)))
bad = [(x0 + i, y0 + j) for j in range(diff.height) for i in range(diff.width) if max(diff.getpixel((i, j))) > 8]
cols = sorted(set(p[0] for p in bad))
# The list text must really reach under the button, or the test proves nothing.
under = ImageChops.difference(a.crop((x0 - 8, y0, x0, y1)), b.crop((x0 - 8, y0, x0, y1))).getbbox() is not None
ok = not bad and under
print(("ok  " if ok else "FAIL") + " scale %s: button %dx%d device px, %d pixels change with text under it%s%s" % (
    scale, x1 - x0, y1 - y0, len(bad), (" (columns %s)" % cols[:8]) if bad else "", "" if under else ", but no text next to it"))
sys.exit(0 if ok else 1)
PY
  grep -q "V1334 FAIL" <<<"$out" && { grep "V1334 FAIL" <<<"$out"; fail=1; }
  rm -rf "$d"
done
exit $fail
