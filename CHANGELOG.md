# Changelog

Newest first. Older history is in the git log.

## 1.32.2

Release checks: a security audit and a review of hidden state machines.

- Fix: picking an item while editing another one, or pressing Alt+Shift+1–0 while the "Clear history?" question or an armed delete was showing, left that mode on. The next time you opened the popup, the edit field or the question was still there. Every way of closing the popup now ends edit mode, the question and an armed delete.
- Fix: cancelling an OCR language install or removal in the terminal (or closing the terminal, or a refused removal) left "Installing…" or "Removing…" on for up to 10 minutes. `ocr-install.sh` now reports how it ended, and the plugin stops waiting within 3 seconds. Closing the terminal during the countdown after a good install still counts as installed.

## 1.32.1

Code quality pass.

- Fix: a copy that arrived while you edited an item rebuilt the list and threw away the edit. The draft now survives the rebuild.
- About 130 version-history notes ("1.29.0: ...", "was ... before") are gone from code comments. The CHANGELOG keeps the history.
- Removed a leftover hover area on the OCR language rows.
- Tests check behaviour: no test for a removed function any more, and the undo limit is checked against the number 10, not the constant.

## 1.32.0

- Edit an item. Text rows get a pencil button. It turns the row into a text field with the whole text, and the row grows to fit. Enter or the check button saves into the same item, so its pin, place and copy time stay. Shift+Enter adds a line, Esc cancels. Empty or unchanged text is not saved.
- The popup header uses the stock `PanelHero` and `PanelSeparator`, like the Wi-Fi, Bluetooth and Display popups. It shows the clipboard icon, "Clipboard" in the title size, and a caps line such as `4 items · 1 pinned`. While you search, the search field takes the title's place.
- Settings content lines up with the page heading. Help texts use `Style.font.bodySmall`, the size of the page description and of the dev gallery header description. They used `caption`, one size smaller.
- Incognito, Check for updates and System-wide shortcuts use the stock `ToggleSwitch` with a label and a one-line hint. Only the switch reacts to clicks.
- General: the Incognito hint says that Flux pauses too. "When you left-click an item" has three options: Copy only, Copy, paste and close (the default), and Copy, paste and keep open. The last one closes the popup for the paste and opens it again with the same search. A sentence under the options explains the chosen one. Saved settings keep their meaning.
- History: Clear history works inside the settings window. The button counts the unpinned items, turns red with a check on the first click and deletes on the second.
- "Flux (phone)" is now "Phone (Flux)". The page says what Nice Clipboard adds to Flux.
- Fix: text sent from the phone during incognito arrived when incognito ended. Incognito stops fluxd, and the phone delivers its queue when Flux is back. Now, after incognito ends, new text waits for `flux-cli status` until 5 s after the phone is online again, at most 10 minutes. Text from the phone is dropped and the clipboard is cleared. Flux itself is unchanged.
- Shortcuts read "Alt+Shift+1–0". "Global shortcuts" is now "System-wide shortcuts".
- Shorter settings texts.
- Tests: `run-harness.sh v132`. The harness stubs `flux-pause.sh` and `systemctl`, so no test can stop the real fluxd.

## 1.31.1

Code cleanup only; nothing you see or do should change.

- Removed functions nothing called any more: the old OCR copy-the-command fallback (`copyOcrInstall`, `ocrInstallCommand`), the pre-1.31 OCR list and size helpers (`ocrLanguageRows`, `ocrSizeLabel`, `ocrSizeTip`), the unused item count label (`countLabel`), the popup-settings remnants (`stepKeepDays`, `contentMargin`, orphan comments) and the unused `CLICK_ACTIONS` list. Their tests now check the code that replaced them.
- One on/off switch component (`SwitchTrack.qml`) for the footer Incognito switch, the General > Incognito row and the OCR "in use" switches (three copies before).
- One "what else needs this language pack" check: `ocr-install.sh --needed-by <code>`, used by its own Remove and by `uninstall.sh` (the same pacman parsing was in both).
- Tests: `run-v129.sh`, `run-v130.sh`, `run-v131.sh` are one `tests/geometry/run-harness.sh v129|v130|v131`; the update-check stub answers 99.0.0, so the v130 "update available" notice is really shown again (it stopped showing once the plugin itself reached 1.31.0). `run.sh` no longer starts clipboard watchers or stops the live ones (the other harnesses already did this).

## 1.31.0

- Delete button per row: the first click turns it red with Omarchy's check icon, a second click deletes. It resets after 3 s, when the mouse leaves it, or when the popup closes. The row itself no longer turns red and the other buttons stay where they are. Keyboard Del: unpinned at once, pinned arms first (as before).
- Undo delete: Ctrl+Z in the popup brings back the last deleted items (up to 10 per session), at their place and with their pin. Images of deleted items are kept on disk while they can still come back. Only inside the popup (no global Super+Z).
- General: "Left click action" (was "Click action"); a line under Incognito says it also toggles with a right-click on the bar icon.
- History: "Automatically delete items after" as a section header above the day pills (the "pinned items kept" value is gone), a separator before Clear history, spacing like the stock display panel (header 10 px above its pills, sections 14 px apart). The default stays 5 days (it already was; saved values are kept).
- Text recognition: all installed languages are used now (before, at most 3: a 4th installed one silently did nothing, so Settings said 4 installed, 3 used). Each installed language is a row with size on disk, an "in use" switch (state.json `ocrOff`, read by `scan.sh` too) and Remove (terminal, `sudo pacman -R`, waits for Enter). Packs something else needs (eng: omasnap) and the last language are kept and say why. "Add language" pills only list languages that are not installed, with their download size. `scan.sh --sizes` adds `requiredBy` and the installed size from `pacman -Qi`.
- Settings > Uninstall: "Uninstall plugin" and "Uninstall plugin and languages", both confirmed with a second click (red, check icon), then `uninstall.sh` in the terminal shows every command and waits for Enter. Languages: only packs `ocr-install.sh` installed (recorded in `ocr-installed` since 1.31.0), still installed, not needed by anything else, never the last one.
- Settings page descriptions use the vanilla shell's header description size (`Style.font.bodySmall`, was `caption`), colour unchanged (foreground darkened 1.4).
- `urgent` is now a normal property (the harness sets it like the other colours).
- Tests: `run-v131.sh`, `uninstall.test.sh`; `ocr-install.test.sh` (remove, record, protection; fake pacman and data dir), `ocr-sizes.test.sh` (`-Qi`), `scan.test.sh` (no cap, `ocrOff`), `history.test.js`.

## 1.30.0

- Text recognition: each OCR language shows its real size, read from the local pacman database (`scan.sh --sizes`, `pacman -Si`, when the settings window opens): space on disk when installed, download size otherwise (e.g. "German · 15 MB"; both in the tooltip). No size is shown when pacman has none. The sidebar entry is "Text recognition (OCR)", its page "Languages for text recognition (OCR)".
- Feedback: the confirmation sits on its own wrapping line under Send (it was cut off in a half-width window), with Omarchy's own check icon in the accent colour instead of a custom green one. Enter sends, Shift+Enter is a new line (Ctrl+Enter still sends). The Ctrl+Shift+Enter "open a GitHub issue" fallback is removed (code, hints, README). New description: "Send feedback straight to the developer from here, or check out the GitHub page." with the link.
- GitHub link at the bottom of the settings sidebar (github.com/roehrbacher/Nice-Clipboard).
- Check for updates (Settings > General), **off by default**: at most once a day, when the popup opens, `update-check.sh` asks the public GitHub API (anonymous, nothing personal sent) for the newest release or version tag; a newer one shows a small "New update available" note in the popup with how to update. Private repository, offline or no release: nothing shown. Omarchy menu > Update does not update third-party plugins (`omarchy-update` has no plugin step; `omarchy plugin update <id>` is CLI only and needs a git install); README > Update says so.
- OCR fix: a row of two icons read as "D le" (Italian / Spanish models installed) is dropped like other icon junk (`ocr-clean.awk`); `scan.test.sh` pins its sample cards to English + German so other installed languages don't change the expected text, plus a fixed TSV case for the icon row.
- README: the online demo link is removed.
- Tests: `run-v130.sh` (update check off by default / on against a stub, OCR sizes, sidebar link, feedback note at 940 and 620 px), `ocr-sizes.test.sh`, `update-check.test.sh` (local fake API, never GitHub), `tst_feedback.qml` (Enter / Shift+Enter).

## 1.29.0

- Alt+Shift+1…9 and Alt+Shift+0 are 10 slots, the same everywhere and in the popup: your pinned items first (in their order), then the newest history items fill the rest. With 9 pins Alt+Shift+0 is the newest history item; with 4 pins Alt+Shift+5…9, 0 are history items 1…6. Every slotted row shows its "Alt+Shift+N". Plain Alt+N in the popup no longer does anything. Keys are read by keycode, so the German layout's Shift+1 = "!" works.
- New `paste-slot.sh <1-9|0>` (and `clipboard.sh copy-slot <1-10>`) for the global bind; `paste-pinned.sh` still works and runs it, so the existing Alt+Shift+1…9 bind gets the new mapping. Alt+Shift+0 comes from the plugin's own global keys (below). `copy-pinned` is gone.
- Settings only in their window: the gear opens it (and closes the popup). The settings page inside the popup, its back arrow, the version in the popup header and the second "Settings in a window" button are gone.
- Fix: after closing the settings window with Super+W (or its close button) the gear could not open it again. The window is now created when needed and dropped when it closes.
- Global shortcuts without editing any config: the plugin adds Alt+V and Alt+Shift+1…9, 0 to the running Hyprland (`global-keys.sh`, `hyprctl eval` + `hl.bind`) when it loads and after each Hyprland config reload, only on keys that are free; keys your config already binds are left alone and listed in Settings > Shortcuts. Switching the setting off (state.json `globalKeys`) or disabling / removing the plugin removes them. On Timon's machines this adds only Alt+Shift+0 (the rest are in the shared config).
- Fix: "Send via Flux" on a row put the item on this computer's clipboard (and moved it to the top of the history) before sending. It now goes straight to fluxd's socket (`clipboard.send`, the text over the socket, never argv); the local clipboard and history are untouched.
- Feedback sent: a green check and "Feedback sent, thanks! Timon reads every message."
- OCR language install: the floating terminal runs the plugin's own `ocr-install.sh`, which first says "Nice Clipboard will install German text recognition:" with the exact `sudo pacman -S --needed tesseract-data-deu` command and waits for Enter (Ctrl+C cancels). Afterwards it says "Done, you can close this window" and closes after 5 s. `omarchy-pkg-add` is no longer used.
- OCR copy notification back to 1.25–1.27: up to 120 characters with "…", title "Copied text from screenshot", "Paste it with Super+V." on its own line.
- Developer test for the first-run OCR banner: `omarchy-shell shell call timon.clipboard ocrBannerDemo x` shows a demo suggestion until Not now or the popup closes (nothing saved).
- Tests: superseded offscreen harnesses v118–v128 removed (they drove the popup settings page; still in git history); new `run-v129.sh`, `slots.test.sh` (was copy-pinned), `ocr-install.test.sh`, `send.test.sh`, `global-keys.test.sh`. Every offscreen harness stubs `global-keys.sh` and sets `NICE_CLIPBOARD_NO_GLOBAL_KEYS=1`, so tests never change the live Hyprland.

## 1.28.0

- Feedback is sent directly: `feedbackEndpoint` is now the live Worker (`https://feedback.roehrbacher.com/feedback`), so Send posts the text (only when pressed) and shows "Sent, thanks!"; no browser or GitHub account. Ctrl+Shift+Enter still opens the prefilled GitHub issue. Test harnesses point it at a local fake Worker or a closed port, never the live one.
- Alt+1…9 in the popup pastes **pinned** item 1…9 (the same pin the global Alt+Shift+N pastes, also while searching); pinned rows show "Alt+N", history rows have no number. Pastes at once.
- Fix: Alt+number in the popup pasted nothing. The paste waited for an Alt release the popup often never saw (Alt held since Alt+V), fired after 1 s with Alt still down, and wtype's Shift+Insert merged with the held Alt into Alt+Shift+Insert. `clipboard.sh` now sends Shift+Insert through Hyprland with explicit mods (like `paste-pinned.sh`), wtype only as fallback.
- `paste-pinned.sh` closes the popup first when it is open (the paste used to land in its search field).
- OCR languages are sorted by name, and a click installs one: Omarchy's floating terminal runs `omarchy-pkg-add tesseract-data-<code>` (pacman `--needed`, signed package, password typed there). The plugin re-reads installed languages every 3 s (up to 10 min) and says when it is ready.
- First-run hint: a banner at the top of the popup suggests a missing OCR language from your locale / keyboard layout ("Based on your keyboard layout: install text recognition (OCR) for German?") with Install and Not now (same dismissal as settings).
- Settings window redesigned for its size: a sidebar of sections (Settings + version on top) and one section per page with title and description; ↑ ↓ switch sections. The popup settings page is unchanged except for the version next to "Settings".
- OCR copy notification: the preview is 72 characters (was 120) so Omarchy's 2-line toast shows it whole, ending with …”; "Super+V pastes" moved into the title.

## 1.27.0

- Text recognition suggests missing OCR languages: when your locale (LANG, LANGUAGE, LC_*, locale.conf), a Hyprland keyboard layout (`hyprctl getoption input:kb_layout`) or a hunspell dictionary points to a language without a tesseract pack, settings say e.g. "Looks like you also use German (your language settings). Install OCR for it?" with a **Copy: sudo pacman -S tesseract-data-deu** button and **Not now** (remembered in state.json as `ocrDismissed`). The plugin never runs sudo. Detection is read-only (`scan.sh --langs` now also prints `hints`); the mapping is tested in `tests/history.test.js` and `tests/ocr-hints.test.sh`.
- Direct feedback, switched off for now: with `feedbackEndpoint` in Clipboard.qml set to the feedback Worker's URL, Send posts the text there (over curl's stdin, never argv) and shows "Sent, thanks!"; no browser and no GitHub account. Empty (the default) keeps the prefilled GitHub issue. Ctrl+Shift+Enter always opens GitHub. Failed sends keep the text and say why.

## 1.26.0

- Alt+1…9 in the popup pastes history items 1…9; pinned items are skipped (they keep Alt+Shift+1…9, which works anywhere). Before, pins took the first numbers, so with 4 pins Alt+1 pasted a pin and the first history item was Alt+5. Row hints say Alt+N on history rows and Alt+Shift+N on pins.
- Clear history counts only what it deletes: unpinned items ("Clear history (3 items)" with 3 history + 4 pinned; was 7). The confirm says "Delete 3 history items? Pinned items stay." and does nothing when only pins are left.
- The Flux phone button shows the state itself: phone with a check (nf-md-cellphone_check) when connected, crossed-out phone otherwise.
- Try-out: a second button next to the gear, "Settings in a window" (󰏌), opens the same settings in their own window (about 900 × 650, two columns), tiled on the current workspace like Flux; Esc closes it. The gear ("Settings in this popup") still opens the page in the popup. The sections are now shared Components, so both show the same controls.

## 1.25.0

- Settings are easier to scan: sections with the stock Display panel's divider line and section headers (qs.Ui PanelSeparator / PanelSectionHeader, same gaps), most-used first: General (incognito, click action), History (delete after, clear history), Flux, Text recognition (OCR), Search filters, Shortcuts, Feedback. ↑ ↓ follow the new order.
- On the settings page the header says "Settings" and the search button is a back arrow (same as Esc or the gear); the "Back to the list" row is gone.
- OCR languages are stock pills, three per row (installed ones highlighted with a check, the pacman command in the tooltip) instead of one long row each; the help is one short sentence.
- "Copied text from screenshot" shows what was recognised: the text on one line, cut at 120 characters with "…" (markup escaped), and stays 6 s instead of 2.5 s.
- Feedback issues carry the real plugin version (was fixed at 1.24.0); `tests/version.test.sh` keeps it equal to manifest.json.

## 1.24.1

- Clipboard reads time out: `wl-paste --list-types` and `wl-paste --type text` in capture.sh now have a 2-second timeout (image and HTML reads already did), so a stuck clipboard cannot hang the watcher. Ported from the Omarchy 4.5 fix that had only landed in the shared-config copy.
- README paste-queue text now matches 1.22.0: notifications say Super+V, and Super+V as well as Ctrl+V advance the queue.

## 1.24.0

- Settings: a "Send feedback" box opens a prefilled GitHub issue (label `feedback`) in the browser. The plugin needs no token; GitHub uses the browser login. Includes `tst_feedback`.

## 1.23.0

- Renamed to Nice Clipboard (repo roehrbacher/Nice-Clipboard, display name). Plugin id stays timon.clipboard, so history, settings and key bindings keep working.
- README: short "TL;DR for humans" first, "Details for Agents" after it; Shortcuts moved after Flux.

## 1.22.0

- Paste queue works with Super+V (Omarchy's universal paste) as well as Ctrl+V. While a queue runs, the stock Super+V bind is swapped for "paste next"; when the queue ends (done, Esc, a new pick, the watchdog) Super+V gets Omarchy's universal paste back (same behaviour: Shift+Insert in terminals, Ctrl+V elsewhere). A Hyprland config reload also restores it.
- Notifications say Super+V: "Pasted 1 of 4. Super+V pastes 2 next. Esc cancels.", and "Paste it with Super+V." after copying a QR / Wi-Fi / screenshot text.

## 1.21.0

- The "Paste queue: N items in order" line sits on a pill in the same accent colour as the numbered queue circles (text in the circles' number colour).
- Queue notification: title "Paste queue ready:", body "Paste 1 of N. Esc cancels."
- A paste queue is forgotten silently as soon as you do anything else in the popup: a normal pick (click, Enter, Alt+N, Shift/Alt+Enter) or a row button (text from screenshot, QR text / Wi-Fi password, open link, Markdown / plain text, send). Ctrl-selected rows are dropped too, so a button never starts a queue. Selecting 2+ rows and closing still starts a new queue.
- OCR settings help is two lines: what a click does, and why there is no install button.
- "Copied text from screenshot" uses the copy icon (󰆏).
- No incognito on/off notifications any more: the popup and the bar icon show it.

## 1.20.0

- Paste queue info line is now just "Paste queue: N items in order" (the old "· Ctrl+V pastes them one by one" got cut off; the "Queue ready" notification still says it).
- OCR on screenshots: the QR code area (corners from ZXing) is painted over before tesseract runs, and tesseract's word confidences drop junk: symbols read from icons next to labels, low-confidence non-words and symbol-only lines (`ocr-clean.awk`). Older image scans are redone once.
- Notifications use `omarchy-notification-send` with a glyph and a body line, so they get the same large icon as Omarchy's own: Wi-Fi password (lock), QR code text (QR), text from screenshot/image (text recognition), incognito on/off, install command (terminal), paste queue (numbered list).
- Opening the popup while the clipboard is empty puts the top pinned item on the clipboard (copy only, never pasted; nothing happens without a pinned item; a password-manager copy doesn't count as empty).
- Settings: "Languages for text recognition (OCR)" lists 16 popular languages; installed ones are marked, a click copies `sudo pacman -S tesseract-data-<code>`. No install button on purpose: installing system packages needs your sudo password, and the plugin never runs root commands or downloads anything itself.

## 1.19.0

- Paste queue starts by itself: select 2+ items with Ctrl+click or Ctrl+Space and close the popup. Notification: "Queue ready: N items. Ctrl+V pastes 1 of N. Esc cancels." One Ctrl+clicked item is a normal pick. Reopening during a queue shows progress, badges and Cancel. A new 2+ selection replaces a running queue.
- The item currently on the clipboard has an accent bar on the left (updates live).
- Images with a QR code and text show both buttons. Wi-Fi QR uses a lock icon.
- Paste as Markdown (M glyph) always comes with Paste as plain text.
- Dragging a pinned item into History unpins it and puts it at the top of History.
- OCR languages: all installed tesseract packs are used (eng first, at most 3), or `OMARCHY_OCR_LANGS` (e.g. `eng+deu`, filtered to installed packs). Settings lists installed languages and shows a copyable install command such as `sudo pacman -S tesseract-data-deu`. Nothing is downloaded or installed automatically.

## 1.18.0

- **Click action** (settings): "Select, paste & close" (default) or
  "Select (copy only)": a click only puts the item on the clipboard and the
  popup stays open.
- **QR codes:** read with ZXing (`ZXingReader` from zxing-cpp) when it is
  installed, else zbar (also retried with a white border for tightly
  cropped screenshots). zbar alone missed light-on-dark, small/blurred and
  styled codes. Images scanned by older versions are scanned once more.
- **QR previews:** a QR image row shows what is in it instead of
  "Image": `Wi-Fi name: <network>` (button: Copy Wi-Fi password),
  `QR link: example.com/…` (Open link), `QR e-mail: …` (Send email),
  `QR phone: …`, `QR contact: …`, or `QR: <text>` (Copy QR code text).
- **OCR button:** "Copy text from screenshot" / "Copy text from image".
- **Drag between sections:** drag any row into Pinned to pin it at that
  spot; drag a pinned row below Pinned to unpin it (it then goes back to its
  place by copy time).
- **Paste as Markdown** no longer adds the Markdown as a new history item,
  and the original entry is put back on the clipboard afterwards.
- **Paste queue fix:** the 2nd Ctrl+V pasted nothing (wl-copy's background
  process held the queue's lock); fixed.
- Settings list every search filter with an example.

