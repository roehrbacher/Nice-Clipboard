# Development

`timon.clipboard` is a clone of Omarchy's stock `omarchy.clipboard` (`clonedFrom` in `manifest.json`). Enabling it switches the stock plugin off, so only one clipboard watcher runs. Your stock history is imported once on first start, from `~/.local/state/omarchy/clipboard-history.json`.

After an Omarchy update, diff its `shell/plugins/clipboard` against this plugin to see what changed upstream since this copy.

The popup is wider than the stock Bluetooth panel (`Style.space(462)`) so text and image previews fit.

## Layout

| File | Role |
|---|---|
| `Clipboard.qml` | Popup, settings, actions |
| `ClipboardHistory.js` | History model, search, slots, feedback payload |
| `BarWidget.qml` | Bar icon |
| `clipboard.sh` | Capture helper, paste, Markdown, init/import |
| `capture.sh` | Watch the clipboard, skip sensitive and incognito copies |
| `global-keys.sh` | Adds Alt+V and Alt+Shift+1 to 0 at runtime when those keys are free |
| `paste-slot.sh` | Paste slot N from anywhere |
| `queue.sh` | Paste queue (Super+V / Ctrl+V) |
| `scan.sh` | Local OCR (`tesseract`) and QR (`ZXingReader`, then `zbarimg`) |
| `flux-pause.sh` | Stop and start `fluxd.service` with incognito |
| `update-check.sh` | GitHub version check, once a day on open, on by default (Settings > General) |
| `uninstall.sh` | Uninstall, optionally language packs this plugin installed |

History lives in `~/.local/share/timon.clipboard/` (folder `0700`, files `0600`).

## IPC

```bash
omarchy-shell shell toggle timon.clipboard
omarchy-shell shell call timon.clipboard toggleIncognito x
omarchy-shell shell call timon.clipboard setIncognito on|off
omarchy-shell shell call timon.clipboard status x
```

`togglePrivate` and `setPrivateMode` still work.

## Tests

Run everything offscreen, with stubs. Nothing should touch a real clipboard, history, Flux or screen. Never start a GPU shell.

From the plugin directory. The geometry harness needs the Omarchy shell's `Commons` and `Ui`; set `OMARCHY_SHELL` if they are not in `/usr/share/omarchy/shell`.

```bash
node tests/history.test.js
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_searchfield.qml
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_kinetic.qml
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_feedback.qml
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_headerclick.qml
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_keepscroll.qml
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_dragflicker.qml
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_draggap.qml

bash tests/capture.test.sh
bash tests/current.test.sh
bash tests/flux-pause.test.sh
bash tests/queue.test.sh
bash tests/version.test.sh
bash tests/markdown.test.sh
bash tests/ocr-hints.test.sh
bash tests/ocr-install.test.sh
bash tests/ocr-sizes.test.sh
bash tests/paste-target.test.sh
bash tests/scan.test.sh
bash tests/global-keys.test.sh
bash tests/send.test.sh
bash tests/slots.test.sh
bash tests/topbutton.test.sh
bash tests/uninstall.test.sh
bash tests/update-check.test.sh
bash tests/v1341.test.sh
bash tests/barflux.test.sh

bash tests/geometry/run-harness.sh v129
bash tests/geometry/run-harness.sh v130
bash tests/geometry/run-harness.sh v131
bash tests/geometry/run-harness.sh v132
bash tests/geometry/run-harness.sh v1322
bash tests/geometry/run-harness.sh v133
bash tests/geometry/run-harness.sh v1331
bash tests/geometry/run-harness.sh v1332
bash tests/geometry/run-harness.sh v1333
bash tests/geometry/run-harness.sh v1334
bash tests/geometry/run-harness.sh v1335
bash tests/geometry/run-harness.sh v134
```

`version.test.sh` checks that the version in `Clipboard.qml`, `manifest.json` and `CHANGELOG.md` matches.
