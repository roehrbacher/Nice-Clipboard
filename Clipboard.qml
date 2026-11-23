// timon.clipboard: clipboard history popup with the UX of GNOME Clipboard
// History (pinned items, incognito mode, regex search, Alt+N), built on
// Omarchy's stock clipboard overlay (shell/plugins/clipboard/Clipboard.qml).
//
// History lives only in ~/.local/share/timon.clipboard/ (folder 0700, files
// 0600). Clipboard contents are never logged and never leave this machine.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import qs.Ui
import "ClipboardHistory.js" as ClipboardHistory
import "Bridge.js" as Bridge

Item {
  id: root

  // 1.25.0: section heading for the settings view, built from the stock
  // Display panel's own pieces (qs.Ui PanelSeparator: 1px, foreground at
  // 12%; PanelSectionHeader: caption, bold, foreground darkened 1.4x) with
  // the same gaps (14 px around the rule, 6 px from header to content).
  // ---- settings (edit here) --------------------------------------------
  // Unpinned entries are deleted keepDays days after they were copied
  // (1, 2, 5, 10 or 20, picked in settings, saved in state.json). Pinned
  // entries are never deleted. historyLimit is only a safety cap.
  property int keepDays: ClipboardHistory.DEFAULT_KEEP_DAYS
  // 1.18.0 setting: what a left click on a row does ("paste" = select,
  // paste and close; "copy" = only put it on the clipboard, popup stays).
  property string clickAction: "paste"
  // After a copy-only click the entry moves to the top; keep it selected.
  property string reselectKey: ""
  property int historyLimit: 2000
  // Rows rendered per search (the rest is a search away).
  property int displayLimit: 200

  // ---- state ------------------------------------------------------------
  property bool opened: false
  property bool ready: false
  property string filterText: ""
  // Header: "Clipboard Manager" + search button; the search field only shows
  // while expanded (button click, or typing, which goes to the hidden field).
  property bool searchExpanded: false
  readonly property bool searchShown: ClipboardHistory.searchShown(filterText, searchExpanded)
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool clearConfirmOpen: false
  // Settings view (gear icon in the footer).
  // Keyboard order = on-screen order (1.25.0 sections).
  // Flux details for the settings view (from `flux-cli status --json`).
  property string phoneName: ""
  property int lastSync: 0
  property int nowSec: Math.floor(Date.now() / 1000)
  // Header phone icon: "online", "paused" (incognito) or "" (hidden).
  // flux-pause.sh's last answer: absent, running, paused or off.
  property string fluxState: ""
  // Footer phone button: "online", "nophone", "paused", "off" or "" (hidden).
  // 1.26.0: Clear history counts (and deletes) unpinned items only.
  readonly property int unpinnedCount: ClipboardHistory.unpinnedCount(root.history)
  readonly property int pinnedCount: ClipboardHistory.pinnedCount(root.history)
  readonly property string phoneIcon: ClipboardHistory.phoneIconState(root.fluxState, root.phoneOnline)
  readonly property string fluxStatusText: !root.fluxPresent ? "not installed"
    : (root.fluxPaused ? "paused (incognito)"
    : (root.phoneOnline ? "running · phone connected" : "running · no phone connected"))
  property bool privateMode: false
  // Flux (fluxd) clipboard sync: paused by flux-pause.sh while private mode is on.
  property bool fluxPresent: false
  property bool fluxPaused: false
  property bool fluxResync: false
  property bool hasPinned: false
  property var history: []
  // Ctrl/Alt+N: display index waiting for the modifier release (-1 = none).
  // Keyboard focus on a row action of the selected row (-1 = the row itself).
  property int actionFocus: -1
  readonly property var selectedActions: root.rowActions(root.selectedIndex, root.armedDeleteIndex, root.phoneOnline, displayModel.count)
  readonly property string focusedAction: root.actionFocus >= 0 && root.actionFocus < selectedActions.length ? selectedActions[root.actionFocus] : ""
  // Pinned entry (history index) armed by a first Del (-1 = none).
  property int armedDeleteIndex: -1
  // Flux: a paired phone is online (checked when the popup opens).
  property bool phoneOnline: false
  // Texts captured a moment ago, waiting for the Flux "from phone" check.
  property var originQueue: []

  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")
  readonly property string dataDir: dataHome + "/timon.clipboard"
  readonly property string historyPath: dataDir + "/history.json"
  readonly property string statePath: dataDir + "/state.json"
  readonly property string captureScript: pluginDir + "/capture.sh"
  readonly property string helper: pluginDir + "/clipboard.sh"
  readonly property string fluxScript: pluginDir + "/flux-pause.sh"
  readonly property string scanScript: pluginDir + "/scan.sh"
  readonly property string queueScript: pluginDir + "/queue.sh"
  readonly property string queuePath: dataDir + "/queue.json"

  // ---- paste queue (1.17.0) ------------------------------------------------
  // Ctrl+click (or Ctrl+Space) rows: they get 1, 2, 3 badges in click order.
  // "Paste N in order" (footer button or Ctrl+Enter) hands them to queue.sh,
  // closes the popup, and every Super+V / Ctrl+V then pastes the next one. Keys are
  // row keys (type + path + text), so a new copy while the popup is open
  // does not shift the selection. Cleared when the popup closes.
  property var queueKeys: []
  // The armed queue (queue.json): { pos, count } or null.
  property var queueRunning: null
  // 1.19.0: no start button. 2+ selected rows start the queue as soon as
  // the popup closes (any way except Esc, which clears the selection first);
  // a single Ctrl-selected row is just a normal pick.
  onOpenedChanged: {
    if (root.opened) { if (root.ocrDemo) root.ocrDemoShown = true; return }
    if (root.ocrDemoShown) { root.ocrDemoArg = ""; root.ocrDemoShown = false }
    if (ClipboardHistory.queueOnPick(root.queueKeys.length)) root.startQueue()
    else if (root.queueKeys.length) root.queueKeys = []
  }
  // Keys (history entry keys) of the running queue, for the badges.
  property var runningKeys: []
  // 1.19.0: what is on the system clipboard ("text:<md5>" / "image:<sha256>"),
  // from each captured copy (live) and `clipboard.sh current` on open.
  property string currentClipKey: ""
  // OCR languages for the settings view (scan.sh --langs).
  property var ocrInfo: ({ installed: [], used: "", env: "", hints: [] })
  // 1.30.0: language pack sizes from the local pacman database (scan.sh
  // --sizes), read once per settings window; {} = show no sizes.
  property var ocrSizes: ({})
  // 1.27.0: "Looks like you also use German, install OCR for it?" Languages
  // come from the locale, keyboard layouts and dictionaries (scan.sh
  // --langs "hints"); dismissed ones are kept in state.json.
  property var ocrDismissed: []
  readonly property var ocrSuggestReal: root.ocrInfo.installed.length ? ClipboardHistory.ocrSuggestions(root.ocrInfo.hints, root.ocrInfo.installed, root.ocrDismissed) : []
  // 1.29.0, dev only: `omarchy-shell shell call timon.clipboard ocrBannerDemo x`
  // shows a demo suggestion in the popup until it is dismissed or the popup
  // closes after showing it. Nothing is written to state.json.
  property string ocrDemoArg: ""
  readonly property var ocrDemo: root.ocrDemoArg !== "" && root.ocrInfo.installed.length ? ClipboardHistory.ocrDemoSuggestion(root.ocrInfo.installed, root.ocrDemoArg) : null
  property bool ocrDemoShown: false
  readonly property var ocrSuggest: root.ocrDemo ? [root.ocrDemo].concat(root.ocrSuggestReal.filter(function(x) { return x.code !== root.ocrDemo.code })) : root.ocrSuggestReal
  // A click installs a language in Omarchy's floating terminal through
  // ocr-install.sh (1.29.0): it shows the exact pacman command and waits for
  // Enter before sudo asks for the password. The plugin never holds root. Installed languages
  // are re-read every 3 s (up to 10 min) until the new one shows up.
  property string ocrInstalling: ""
  property string ocrInstallingName: ""
  // 1.31.0: languages switched off in Settings (state.json "ocrOff"; scan.sh
  // reads it too), and the one being removed in the terminal.
  property var ocrOff: []
  property string ocrRemoving: ""
  property string ocrRemovingName: ""
  function toggleOcrUse(code) {
    root.ocrOff = ClipboardHistory.toggleOcrOff(root.ocrOff, code, root.ocrInfo.installed)
    root.writeState()
    if (!ocrLangProc.running) ocrLangProc.running = true
  }
  function removeOcrLanguage(lang) {
    if (!lang || lang.protect) return
    var argv = ClipboardHistory.ocrInstallArgv(lang.code, root.pluginDir + "/ocr-install.sh", lang.name, true)
    if (!argv.length) return
    root.ocrRemoving = lang.code
    root.ocrRemovingName = lang.name
    root.ocrWatchTicks = 0
    Quickshell.execDetached(argv)
    ocrWatchTimer.restart()
  }
  property int ocrWatchTicks: 0
  function installOcrLanguage(lang) {
    if (!lang || lang.installed) return
    var argv = ClipboardHistory.ocrInstallArgv(lang.code, root.pluginDir + "/ocr-install.sh", lang.name)
    if (!argv.length) return
    root.ocrInstalling = lang.code
    root.ocrInstallingName = lang.name
    root.ocrWatchTicks = 0
    // The popup holds the keyboard; close it so the password can be typed.
    if (root.opened) root.close()
    Quickshell.execDetached(argv)
    root.notify("󰗊", "Installing " + lang.name + " (OCR)", "Check the command in the terminal and press Enter. Nice Clipboard picks it up when it is done.", 5000)
    ocrWatchTimer.restart()
  }
  property string ocrInstalledSeen: ""
  function ocrInfoUpdated() {
    // Installed set changed: sizes / "needed by" again.
    var seen = root.ocrInfo.installed.join(",")
    if (root.ocrInstalledSeen !== "" && seen !== root.ocrInstalledSeen && !ocrSizesProc.running) ocrSizesProc.running = true
    root.ocrInstalledSeen = seen
    if (root.ocrRemoving !== "" && root.ocrInfo.installed.indexOf(root.ocrRemoving) < 0) {
      root.notify("󰩺", root.ocrRemovingName + " text recognition removed", "", 5000)
      root.ocrRemoving = ""
      if (root.ocrInstalling === "") ocrWatchTimer.stop()
    }
    if (root.ocrInstalling === "" || root.ocrInfo.installed.indexOf(root.ocrInstalling) < 0) return
    ocrWatchTimer.stop()
    root.notify("󰄬", root.ocrInstallingName + " text recognition installed", "Screenshots and images copied from now on are read in " + root.ocrInstallingName + " too.", 6000)
    root.ocrInstalling = ""
  }
  function dismissOcrSuggestion(code) {
    if (root.ocrDemo && root.ocrDemo.code === code) { root.ocrDemoArg = ""; return }
    if (root.ocrDismissed.indexOf(code) >= 0) return
    root.ocrDismissed = root.ocrDismissed.concat([code])
    root.writeState()
  }
  function toggleQueueIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    root.queueKeys = ClipboardHistory.toggleQueued(root.queueKeys, root.rowKey(displayModel.get(index)))
  }
  function startQueue() {
    var entries = []
    for (var q = 0; q < root.queueKeys.length; q++) {
      for (var i = 0; i < displayModel.count; i++) {
        var r = displayModel.get(i)
        if (root.rowKey(r) === root.queueKeys[q]) { entries.push(root.history[r.historyIndex]); break }
      }
    }
    var items = ClipboardHistory.queueItems(entries)
    root.queueKeys = []
    if (!items.length) return
    queueProc.payload = JSON.stringify(items)
    queueProc.running = true
  }
  // 1.21.0: any normal pick or row action while a queue is armed (or rows
  // are Ctrl-selected) forgets that queue silently and does the new thing.
  function dropQueue() {
    root.queueKeys = []
    if (root.queueRunning) {
      root.queueRunning = null
      root.runningKeys = []
      Quickshell.execDetached([root.queueScript, "cancel", "quiet"])
    }
  }
  function queueButtonClicked() {
    if (root.queueKeys.length === 0 && root.queueRunning) Quickshell.execDetached([root.queueScript, "cancel"])
  }
  function applyQueueFile(raw) {
    var st = null
    try { st = JSON.parse(String(raw || "")) } catch (e) { st = null }
    root.queueRunning = st && Array.isArray(st.items) && st.items.length ? { pos: Number(st.pos || 0), count: st.items.length } : null
    root.runningKeys = root.queueRunning ? ClipboardHistory.queueItemKeys(st.items) : []
  }
  // Badge number of a row: the selection while picking, else its place in
  // the running queue (rows already pasted are dimmed).
  function queueBadge(row, keys, running, runKeys, history) {
    var n = ClipboardHistory.queueNumber(keys, root.rowKey(row))
    if (n > 0 || keys.length > 0 || !running) return { n: n, done: false }
    var e = history[row.historyIndex]
    var k = e ? ClipboardHistory.entryKey(e) : ""
    var at = runKeys.indexOf(k)
    return { n: at + 1, done: at >= 0 && at < running.pos }
  }

  // Same [menu] surface tokens as the stock clipboard, so every theme styles it.
  // Popup surface tokens, same as the stock Wi-Fi popup (KeyboardPanel).
  // Heading that gets the separator (first one after Pinned), set on rebuild.
  property string firstHistorySection: ""
  property color background: Color.popups.background
  property color foreground: Color.popups.text
  property color border: Color.popups.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Style.selectedFillFor(foreground, Color.accent)
  property color selectedText: foreground
  property color accent: Color.accent
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int footerRowHeight: Math.max(Style.space(26), Style.font.body + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  // Small extra gap between the list and the footer.
  property int footerGap: Style.space(4)
  // Scales with the screen's logical height: unchanged from 1080 px up,
  // 20% smaller on a small laptop screen (ClipboardHistory.popupScale).
  readonly property real popupScale: ClipboardHistory.popupScale(panel.screenH)
  // List only (no preview column): half the old 875 px width.
  property int cardWidth: panel.fittedContentWidth(Math.round(Style.space(462) * popupScale))
  property int cardHeight: panel.cappedContentHeight(Math.round(Style.space(630) * popupScale))
  // Bar icon the popup hangs from (set by BarWidget.qml through Bridge.js).
  property Item anchorButton: null
  property QtObject anchorBar: null
  property Item anchorWidget: null
  function setAnchor(button, bar, widget) { root.anchorButton = button; root.anchorBar = bar; root.anchorWidget = widget || null }
  // Secondary text: same size and contrast as the stock Wi-Fi panel's
  // smallest text (foreground darkened 1.4x, no opacity); hints use the count size (Style.font.body).
  readonly property color dimText: Qt.darker(foreground, 1.4)
  property color urgent: Color.urgent
  // Compact rows like the Wi-Fi list: one line plus a small padding.
  property int rowHeight: Math.max(Style.space(30), Style.font.title + Style.spacing.rowPaddingX + Style.space(6))

  // ---- open / close (shell host API) ------------------------------------
  function open(payloadJson) {
    if (root.ready) { queueFile.reload(); if (!queueStatusProc.running) queueStatusProc.running = true }
    if (root.ready && !clipKeyProc.running) clipKeyProc.running = true
    // Paths may have appeared/vanished since last time.
    root.pathInfo = ({})
    root.pathSingle = false
    mapsCheckProc.running = true
    // 1.28.0: the OCR banner needs the languages on every open (cheap).
    if (!ocrLangProc.running) ocrLangProc.running = true
    root.maybeCheckUpdate()
    root.opened = true
    root.filterText = ""
    root.searchExpanded = false
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
    if (root.fluxPresent && !root.fluxPaused && !statusProc.running) statusProc.running = true
    else if (!root.fluxPresent || root.fluxPaused) root.phoneOnline = false
    Qt.callLater(function() { searchInput.forceActiveFocus() })
  }

  // Settings live only in their own window (1.29.0; the gear opens it). A
  // normal toplevel, so Hyprland tiles it like Flux. The window is made by
  // a Loader and dropped when it is closed (Esc, or Super+W = Hyprland
  // killactive, which emits closed() but leaves visible = true: 1.26-1.28
  // then could not show it again), so every open after a close gets a fresh one.
  function openSettingsWindow(section) {
    root.disarmDelete()
    root.nowSec = Math.floor(Date.now() / 1000)
    if (root.fluxPresent && !root.fluxPaused && !statusProc.running) statusProc.running = true
    if (!ocrLangProc.running) ocrLangProc.running = true
    if (Object.keys(root.ocrSizes).length === 0 && !ocrSizesProc.running) ocrSizesProc.running = true
    if (section !== undefined) {
      var i = root.settingsSections.map(function(x) { return x.key }).indexOf(section)
      if (i >= 0) root.settingsSection = i
    }
    if (root.opened) root.close()
    if (settingsWindowLoader.item && !settingsWindowLoader.item.visible) settingsWindowLoader.active = false
    settingsWindowLoader.active = true
    if (settingsWindowLoader.item) settingsWindowLoader.item.visible = true
    Qt.callLater(function() { if (root.settingsKeysRef) root.settingsKeysRef.forceActiveFocus() })
  }
  function closeSettingsWindow() {
    root.settingsKeysRef = null
    root.settingsPaneFlickRef = null
    root.uninstallArmed = ""
    settingsWindowLoader.active = false
  }

  // Footer phone button: open Flux's own window (flux-cli open: its shell
  // plugin, else flux-gui) and close the popup; without flux-cli, the Flux
  // section of the settings view.
  function openFlux() {
    if (root.fluxPresent) {
      root.close()
      Quickshell.execDetached(["flux-cli", "open"])
    } else root.openSettingsWindow("flux")
  }

  // Send what is on the clipboard now to the phone (flux-cli clip).
  function sendCurrentClipboard() {
    if (!root.phoneOnline || root.fluxPaused) return
    Quickshell.execDetached(["flux-cli", "clip"])
    root.lastSync = Math.floor(Date.now() / 1000)
    root.nowSec = root.lastSync
  }

  // Left/Right walk the auto-delete presets (clamped); Enter cycles.
  function stepKeepDays(dir, wrap) {
    var list = ClipboardHistory.KEEP_DAYS
    var i = list.indexOf(root.keepDays) + dir
    if (wrap) i = (i + list.length) % list.length
    else i = Math.max(0, Math.min(list.length - 1, i))
    root.setKeepDays(list[i])
  }

  // The public project page (settings sidebar, Feedback description).
  readonly property string repoUrl: "https://github.com/roehrbacher/Nice-Clipboard"
  // Kept equal to manifest.json by tests/version.test.sh.
  readonly property string pluginVersion: "1.31.0"
  property string feedbackNote: ""
  // True after the Worker confirmed; the note then gets Omarchy's check
  // (nf-md-check, the shell's own Nerd Font icon) in the theme accent.
  property bool feedbackSent: false
  // Direct feedback (1.27.0, on since 1.28.0): Send posts the text to the
  // Nice Clipboard feedback Worker, which files it as an issue in a private
  // repo (rate limited, no IP kept). No browser, no GitHub account; only
  // when Send (or Enter) is pressed. 1.30.0: the "open a GitHub issue"
  // fallback (Ctrl+Shift+Enter) is gone.
  readonly property string feedbackEndpoint: "https://feedback.roehrbacher.com/feedback"
  property var feedbackPendingInput: null
  // input: the feedback field in the settings window.
  function sendFeedback(input) {
    var t = input ? input.text.trim() : ""
    if (t === "") { root.feedbackNote = "Write something first"; root.feedbackSent = false; return false }
    if (feedbackProc.running) return false
    feedbackProc.payload = ClipboardHistory.feedbackPayload(t, root.pluginVersion)
    root.feedbackPendingInput = input
    root.feedbackNote = "Sending…"
    root.feedbackSent = false
    feedbackProc.running = true
    return true
  }
  // 1.31.0: Settings > Uninstall. First click arms a button (red, Omarchy's
  // check icon), a second click within 3 s opens uninstall.sh in the
  // terminal, which shows the commands and waits for Enter.
  property string uninstallArmed: ""
  Timer { id: uninstallArmTimer; interval: 3000; onTriggered: root.uninstallArmed = "" }
  function requestUninstall(kind) {
    if (root.uninstallArmed !== kind) { root.uninstallArmed = kind; uninstallArmTimer.restart(); return false }
    root.uninstallArmed = ""
    uninstallArmTimer.stop()
    Quickshell.execDetached(ClipboardHistory.uninstallArgv(root.pluginDir + "/uninstall.sh", kind === "languages"))
    return true
  }
  function openUrl(url) {
    if (!/^https:\/\//.test(String(url))) return
    Quickshell.execDetached(["xdg-open", String(url)])
  }

  // 1.30.0: optional update check, OFF by default (state "updateCheck"):
  // at most once a day, when the popup opens, update-check.sh asks the
  // public GitHub API for the newest release (anonymous, nothing personal
  // sent). Newer than pluginVersion = a small notice above the list. While
  // the repository is private nothing is found and nothing is shown.
  property bool updateCheck: false
  property real updateLastCheck: 0
  property string updateLatest: ""
  property bool updateGit: false
  property string updateDismissed: ""
  readonly property string updateScript: pluginDir + "/update-check.sh"
  readonly property bool updateAvailable: root.updateCheck && root.updateLatest !== ""
      && root.updateLatest !== root.updateDismissed && ClipboardHistory.versionNewer(root.updateLatest, root.pluginVersion)
  function maybeCheckUpdate() {
    if (!root.updateCheck || updateProc.running) return
    var now = Math.floor(Date.now() / 1000)
    if (!ClipboardHistory.updateCheckDue(root.updateLastCheck, now)) return
    root.updateLastCheck = now
    root.writeState()
    updateProc.running = true
  }
  Process {
    id: updateProc
    command: [root.updateScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var st = null
        try { st = JSON.parse(String(text)) } catch (e) { st = null }
        if (!st) return
        root.updateGit = st.git === true
        root.updateLatest = /^[0-9]+\.[0-9]+\.[0-9]+$/.test(String(st.latest || "")) ? String(st.latest) : ""
        root.writeState()
      }
    }
  }

  // Clickable settings rows (incognito, clear history) in the window.
  // Clear history asks in the popup (its confirm lives there).
  function runSettingsAction(name) {
    if (name === "globalKeys") { root.globalKeys = !root.globalKeys; root.writeState(); root.applyGlobalKeys(); return }
    if (name === "updateCheck") { root.updateCheck = !root.updateCheck; if (!root.updateCheck) root.updateLatest = ""; root.writeState(); root.maybeCheckUpdate(); return }
    if (name === "incognito") root.setPrivate(!root.privateMode, false)
    else if (name === "clear") { root.open("{}"); root.requestClearHistory() }
  }

  // 1.29.0: global shortcuts from the plugin itself (global-keys.sh): Alt+V
  // and Alt+Shift+1…9, 0 are added to the running Hyprland on load and after
  // every Hyprland config reload (which drops runtime binds), only where the
  // key is still free; removed when switched off or when the plugin unloads.
  // No config file is touched. Setting: Settings > Shortcuts (state.json
  // "globalKeys", on by default).
  property bool globalKeys: true
  property bool globalKeysApplied: false
  property var globalKeysInfo: ({ active: [], taken: [], errors: [], text: "" })
  readonly property string globalKeysScript: pluginDir + "/global-keys.sh"
  function applyGlobalKeys() {
    root.globalKeysApplied = true
    if (globalKeysProc.running) { globalKeysProc.again = true; return }
    globalKeysProc.command = [root.globalKeysScript, root.globalKeys ? "apply" : "remove"]
    globalKeysProc.running = true
  }
  Process {
    id: globalKeysProc
    property bool again: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.globalKeysInfo = root.globalKeys ? ClipboardHistory.globalKeysSummary(String(text)) : ({ active: [], taken: [], errors: [], text: "" })
        if (globalKeysProc.again) { globalKeysProc.again = false; Qt.callLater(root.applyGlobalKeys) }
      }
    }
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name) === "configreloaded" && root.globalKeys) globalKeysReapply.restart()
    }
  }
  Timer { id: globalKeysReapply; interval: 400; onTriggered: root.applyGlobalKeys() }
  // First run without a state.json: loadState never runs, so apply anyway.
  Timer { interval: 4000; running: root.ready && !root.globalKeysApplied; onTriggered: if (!root.globalKeysApplied) root.applyGlobalKeys() }
  // Unloaded: a shell restart or hot reload loads us again right away (and
  // re-applies), so only remove our keys when the plugin is really disabled
  // or removed. The script is read first because removal deletes its folder.
  function removeGlobalKeysIfGone() {
    if (!root.globalKeysApplied || !root.globalKeys) return
    Quickshell.execDetached(["bash", "-c",
      'src=$(cat "$0") || exit 0; sleep 3; '
      + 'if omarchy-plugin-list --json 2>/dev/null | jq -e \'any(.[]; .id == "timon.clipboard" and .enabled == true)\' >/dev/null; then exit 0; fi; '
      + 'exec bash -c "$src" global-keys.sh remove', root.globalKeysScript])
  }

  function close() {
    root.disarmDelete()
    root.cancelClearHistory()
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  // ---- IPC: omarchy-shell shell call timon.clipboard <method> x ----------
  function togglePrivate(arg) {
    root.setPrivate(!root.privateMode, !root.opened)
    return root.privateMode ? "private" : "recording"
  }

  function setPrivateMode(arg) {
    root.setPrivate(String(arg) === "true" || String(arg) === "on", !root.opened)
    return root.privateMode ? "private" : "recording"
  }

  // Same as togglePrivate / setPrivateMode (the UI calls it "Incognito").
  function toggleIncognito(arg) { return root.togglePrivate(arg) }
  function setIncognito(arg) { return root.setPrivateMode(arg) }

  // Dev only (1.29.0): force the first-run OCR banner. Arg: a Tesseract code
  // (e.g. fra) or anything else for the first language not installed; "off"
  // removes it. Open the popup to see it.
  function ocrBannerDemo(arg) {
    root.ocrDemoShown = false
    root.ocrDemoArg = String(arg) === "off" ? "" : (/^[a-z_]{3,8}$/.test(String(arg)) ? String(arg) : "any")
    if (root.ocrDemoArg === "") return "off"
    if (root.opened) root.ocrDemoShown = true
    if (!ocrLangProc.running) ocrLangProc.running = true
    return "demo banner on: open the popup"
  }

  function status(arg) {
    return JSON.stringify({ private: root.privateMode, incognito: root.privateMode, fluxPaused: root.fluxPaused, open: root.opened, entries: root.history.length, shown: displayModel.count })
  }

  // 1.20.0: every notification goes through omarchy-notification-send with a
  // glyph (the omarchy-glyph hint) and a body line, so it gets the same large
  // icon as Omarchy's own notifications (a summary-only toast shrinks it).
  function notify(glyph, summary, body, ms) {
    Quickshell.execDetached(["omarchy-notification-send", "--app-name", "Clipboard", "-g", glyph, "-t", String(ms || 2500), summary, body || ""])
  }

  // ---- incognito (private) mode -------------------------------------------
  function setPrivate(value, notify) {
    var fluxWasPaused = root.fluxPaused
    root.privateMode = value
    root.writeState()
    root.syncFlux()
    // 1.21.0: no incognito on/off notification (the popup and the bar icon
    // already show it); `notify` is kept for the callers' signature.
  }

  function writeState() {
    stateFile.setText(JSON.stringify({ private: root.privateMode, keepDays: root.keepDays, clickAction: root.clickAction, ocrDismissed: root.ocrDismissed, ocrOff: root.ocrOff, globalKeys: root.globalKeys,
      updateCheck: root.updateCheck, updateLastCheck: root.updateLastCheck, updateLatest: root.updateLatest, updateGit: root.updateGit, updateDismissed: root.updateDismissed }) + "\n")
  }

  function loadState(raw) {
    var st = {}
    try { st = JSON.parse(String(raw || "{}")) || {} } catch (e) { st = {} }
    root.privateMode = st.private === true
    root.clickAction = ClipboardHistory.clickActionOf(st.clickAction)
    root.ocrDismissed = ClipboardHistory.ocrDismissedOf(st.ocrDismissed)
    root.ocrOff = ClipboardHistory.ocrDismissedOf(st.ocrOff)
    root.updateCheck = st.updateCheck === true
    root.updateLastCheck = Number(st.updateLastCheck) || 0
    root.updateLatest = root.updateCheck && /^[0-9]+\.[0-9]+\.[0-9]+$/.test(String(st.updateLatest || "")) ? String(st.updateLatest) : ""
    root.updateGit = st.updateGit === true
    root.updateDismissed = String(st.updateDismissed || "")
    var gk = st.globalKeys !== false
    if (gk !== root.globalKeys || !root.globalKeysApplied) { root.globalKeys = gk; root.applyGlobalKeys() }
    var days = ClipboardHistory.keepDaysOf(st.keepDays)
    if (days !== root.keepDays) { root.keepDays = days; root.pruneOld() }
    // Also runs at shell start: resumes Flux if private mode ended while the
    // shell was down, pauses it again if private mode is still on.
    root.syncFlux()
  }

  // Make Flux match private mode (pause or resume fluxd via flux-pause.sh).
  function syncFlux() {
    if (fluxProc.running) root.fluxResync = true
    else fluxProc.running = true
  }

  // ---- history ----------------------------------------------------------
  function loadHistory(raw) {
    var stamped = ClipboardHistory.stampMissing(ClipboardHistory.parseHistory(raw), Date.now())
    root.history = ClipboardHistory.pruneToLimit(stamped.history, root.historyLimit)
    root.historyLoaded = true
    if (!root.pruneOld() && stamped.changed) root.saveHistory()
    if (root.opened) root.rebuildDisplay(true)
    root.queueScans()
  }

  // ---- text and QR codes in images (1.16.0) --------------------------------
  // One image at a time, niced, in the background: scan.sh reads the text
  // (tesseract) and QR codes (zbarimg); the result is stored on the entry so
  // it is searchable and the copy-text / open-link buttons appear. Images
  // are tried once per shell session; with a tool missing they are tried
  // again after the next shell start.
  property var scanQueue: []
  property var scanTried: ({})
  function queueScans() {
    for (var i = 0; i < root.history.length; i++) {
      var e = root.history[i]
      if (!ClipboardHistory.needsScan(e) || root.scanTried[e.path] || root.scanQueue.indexOf(e.path) >= 0) continue
      root.scanQueue.push(e.path)
    }
    if (root.scanQueue.length && !scanProc.running) scanTimer.restart()
  }
  function applyScan(path, raw) {
    var res = null
    try { res = JSON.parse(String(raw || "")) } catch (e) { res = null }
    if (!res) return
    var changed = false
    var next = root.history.slice()
    for (var i = 0; i < next.length; i++) {
      var e = next[i]
      if (!e || e.type !== "image" || e.path !== path) continue
      var u = Object.assign({}, e)
      if (res.ocr) u.ocr = String(res.ocr); else delete u.ocr
      if (res.qr) u.qr = String(res.qr); else delete u.qr
      if (res.complete === true) { u.scanned = true; u.scanv = ClipboardHistory.SCAN_VERSION }
      next[i] = u
      changed = true
    }
    if (!changed) return
    root.history = next
    root.saveHistory()
    if (root.opened && root.dragRow < 0) root.rebuildDisplay(true)
  }
  Timer {
    id: scanTimer
    interval: 1500
    onTriggered: {
      if (scanProc.running || root.scanQueue.length === 0) return
      // Never rescan in the middle of a drag; try again shortly.
      if (root.dragRow >= 0) { restart(); return }
      var path = root.scanQueue.shift()
      root.scanTried[path] = true
      scanProc.path = path
      scanProc.command = [root.scanScript, path]
      scanProc.running = true
    }
  }
  Process {
    id: scanProc
    property string path: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyScan(scanProc.path, text)
    }
    onExited: if (root.scanQueue.length) scanTimer.restart()
  }

  // Deletes unpinned entries older than keepDays; true when it saved.
  property bool historyLoaded: false
  function pruneOld() {
    if (!root.historyLoaded) return false
    var kept = ClipboardHistory.pruneByAge(root.history, root.keepDays, Date.now())
    if (kept.length === root.history.length) return false
    root.history = kept
    root.saveHistory()
    if (root.opened) root.rebuildDisplay(true)
    return true
  }

  function setClickAction(v) {
    root.clickAction = ClipboardHistory.clickActionOf(v)
    root.writeState()
  }
  // Left click on a row, per the "Click action" setting.
  function clickIndex(index) {
    if (root.clickAction !== "copy" || ClipboardHistory.queueOnPick(root.queueKeys.length)) { root.activateIndex(index); return }
    if (index < 0 || index >= displayModel.count) return
    var r = displayModel.get(index)
    root.reselectKey = root.rowKey(r)
    root.dropQueue()
    Quickshell.execDetached([root.helper, "copy", String(r.historyIndex)])
  }

  function setKeepDays(days) {
    root.keepDays = ClipboardHistory.keepDaysOf(days)
    root.writeState()
    root.pruneOld()
  }

  function saveHistory() {
    historyFile.setText(JSON.stringify(root.history) + "\n")
    // Image files of deleted items stay while Ctrl+Z can bring them back.
    if (!root.undoStack.some(function(u) { return u.entry && u.entry.type === "image" })) pruneTimer.restart()
  }

  function addClipboardJson(line) {
    if (root.privateMode) return
    var entry = ClipboardHistory.parseEntryJson(line)
    if (!entry) return
    root.currentClipKey = ClipboardHistory.clipKeyOf(entry, Qt.md5)
    entry.at = Date.now()  // copy time: day headings and auto-delete
    root.history = ClipboardHistory.pruneByAge(ClipboardHistory.addEntry(root.history, entry, root.historyLimit), root.keepDays, Date.now())
    root.saveHistory()
    if (root.opened) root.rebuildDisplay(true)
    if (entry.type === "image") root.queueScans()
    if (entry.type === "text" && root.fluxPresent && !root.fluxPaused) {
      root.originQueue = root.originQueue.concat([entry.text]).slice(-5)
      originTimer.restart()
    }
  }

  // Flux records a copy from the phone (dir "in") before it puts it on the
  // clipboard, so `flux-cli status --json` read just after the capture tells
  // whether the new text came from the phone. Read over stdout only.
  function applyFluxStatus(raw) {
    var st = null
    try { st = JSON.parse(String(raw || "")) } catch (e) { st = null }
    if (!st) return
    root.phoneOnline = ClipboardHistory.fluxPhoneOnline(st)
    root.phoneName = ClipboardHistory.fluxPhoneName(st)
    root.lastSync = Math.max(root.lastSync, ClipboardHistory.fluxLastSync(st))
    var queue = root.originQueue
    root.originQueue = []
    var now = Math.floor(Date.now() / 1000)
    var changed = false
    for (var i = 0; i < queue.length; i++) {
      if (ClipboardHistory.fluxOrigin(st, queue[i], now) === "phone") {
        root.history = ClipboardHistory.setOrigin(root.history, queue[i], "phone")
        changed = true
      }
    }
    if (changed) {
      root.saveHistory()
      if (root.opened) root.rebuildDisplay(true)
    }
  }

  // ---- delete confirmation for pinned entries ------------------------------
  function disarmDelete() {
    if (root.armedDeleteIndex !== -1) root.armedDeleteIndex = -1
    armTimer.stop()
  }

  // The delete button (1.31.0): the first click arms it (red, Omarchy's
  // check icon), a second click within 3 s deletes. It disarms when the
  // mouse leaves it or the popup closes. Del on the keyboard: pinned rows
  // arm first, unpinned ones go at once. Ctrl+Z brings deleted items back.
  function requestDelete(index, byClick) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    var armed = root.armedDeleteIndex === row.historyIndex
    if (ClipboardHistory.deleteAction(row.pinned || byClick === true, armed) === "arm") {
      root.selectAbsolute(index)
      root.armedDeleteIndex = row.historyIndex
      armTimer.restart()
      return
    }
    root.disarmDelete()
    root.removeDisplayIndex(index)
  }

  function requestClearHistory() {
    if (root.unpinnedCount === 0) return
    clearConfirm.selectedIndex = 1
    root.clearConfirmOpen = true
  }

  function cancelClearHistory() {
    root.clearConfirmOpen = false
    root.disarmPointer()
    Qt.callLater(function() { searchInput.forceActiveFocus() })
  }

  function confirmClearHistory() {
    var currentWasUnpinned = root.history.length > 0 && !root.history[0].pinned
    root.history = ClipboardHistory.clearHistory(root.history)
    root.saveHistory()
    if (currentWasUnpinned && !root.privateMode) Quickshell.execDetached([root.helper, "clear"])
    root.selectedIndex = 0
    root.cursorActive = false
    root.disarmPointer()
    root.clearConfirmOpen = false
    root.rebuildDisplay()
    Qt.callLater(function() { searchInput.forceActiveFocus() })
  }

  // 1.31.0: Ctrl+Z in the popup restores the last deleted items (up to 10,
  // this session only), at their place and with their pin.
  property var undoStack: []
  function undoDelete() {
    if (!root.undoStack.length) return false
    var item = root.undoStack[root.undoStack.length - 1]
    root.undoStack = root.undoStack.slice(0, -1)
    var r = ClipboardHistory.restoreEntry(root.history, item)
    root.history = r.history
    root.saveHistory()
    root.rebuildDisplay(true)
    for (var i = 0; i < displayModel.count; i++) if (displayModel.get(i).historyIndex === r.index) { root.selectAbsolute(i); break }
    return true
  }

  function removeDisplayIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.undoStack = ClipboardHistory.pushUndo(root.undoStack, root.history[row.historyIndex], row.historyIndex)
    // Only the history changes; the system clipboard is left as it is.
    root.history = ClipboardHistory.removeEntryAt(root.history, row.historyIndex)
    root.saveHistory()

    if (displayModel.count <= 1) {
      root.selectedIndex = 0
      root.cursorActive = false
    } else if (root.selectedIndex >= displayModel.count - 1) {
      root.selectedIndex = displayModel.count - 2
    }
    root.disarmPointer()
    root.rebuildDisplay(true)
  }

  function togglePinDisplayIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    var historyIndex = row.historyIndex
    // The entry jumps between sections; the cursor stays where the eye is:
    // on the row that followed it (or preceded it, at the end).
    var neighbour = index + 1 < displayModel.count ? index + 1 : index - 1
    var neighbourKey = neighbour >= 0 ? root.rowKey(displayModel.get(neighbour)) : ""
    root.history = ClipboardHistory.togglePinAt(root.history, historyIndex)
    root.saveHistory()
    root.rebuildDisplay(true, historyIndex)
    for (var i = 0; neighbourKey !== "" && i < displayModel.count; i++) {
      if (root.rowKey(displayModel.get(i)) === neighbourKey) { root.selectedIndex = i; break }
    }
  }

  // Stable identity of a display row (history indexes shift on delete).
  function rowKey(r) { return r ? r.entryType + "\n" + r.path + "\n" + r.fullText : "" }

  // ---- reorder pinned rows by dragging --------------------------------------
  // Pressing a pinned row stops the list from scrolling under the mouse; once
  // the pointer moves past the threshold the row follows it within the
  // pinned section. Release saves the order (Alt+N follows it). A press
  // without movement is still a normal click. Wheel/touchpad scroll as before.
  property int dragRow: -1          // display index being dragged (-1 = none)
  property bool dragMoved: false
  property int dragHistoryIndex: -1 // history index of the dragged entry (stable while rows move)
  // 1.18.0: any row can be dragged; over Pinned it becomes pinned at that
  // slot, a pinned row dragged below Pinned is unpinned on drop.
  property bool dragOrigPinned: false
  property int dragOrigIndex: -1
  property string dragOrigSection: ""
  function dragStart(index) {
    var r = displayModel.get(index)
    root.dragRow = index
    root.dragHistoryIndex = r.historyIndex
    root.dragOrigPinned = r.pinned
    root.dragOrigIndex = index
    root.dragOrigSection = r.sectionName
    root.dragMoved = false
  }

  function pinnedDisplayCount() {
    var n = 0
    for (var i = 0; i < displayModel.count; i++) if (displayModel.get(i).pinned) n++
    return n
  }

  function dragMoveTo(target) {
    if (root.dragRow < 0) return
    var cur = displayModel.get(root.dragRow)
    var others = root.pinnedDisplayCount() - (cur.pinned ? 1 : 0)
    var plan = ClipboardHistory.dragPlan(target, others, displayModel.count, root.dragOrigPinned, root.dragOrigIndex)
    if (plan.index === root.dragRow && plan.pinned === cur.pinned) return
    // The highlight follows the dragged entry by identity (hasCursor), so
    // move() never leaves it on a neighbour for a frame and the 60 ms colour
    // fade of the stock row never starts on the rows being passed.
    if (plan.index !== root.dragRow) displayModel.move(root.dragRow, plan.index, 1)
    root.dragRow = plan.index
    root.selectedIndex = plan.index
    root.dragMoved = true
    if (plan.pinned !== cur.pinned) {
      // Section follows: "Pinned" inside, the neighbour's heading below.
      var below = plan.index + 1 < displayModel.count ? displayModel.get(plan.index + 1).sectionName : "History"
      displayModel.setProperty(plan.index, "pinned", plan.pinned)
      displayModel.setProperty(plan.index, "sectionName", plan.pinned ? "Pinned" : (root.dragOrigPinned ? (below === "Pinned" ? "History" : below) : root.dragOrigSection))
    }
    // Alt+N numbers follow the new order live, so nothing jumps on drop.
    for (var i = 0; i < displayModel.count; i++) if (displayModel.get(i).slot !== i + 1) displayModel.setProperty(i, "slot", i + 1)
  }

  function dragFinish() {
    if (root.dragRow < 0) return
    var moved = root.dragMoved
    var historyIndex = displayModel.get(root.dragRow).historyIndex
    root.dragRow = -1
    root.dragMoved = false
    root.dragHistoryIndex = -1
    if (!moved) return
    var nowPinned = false
    var order = []
    for (var i = 0; i < displayModel.count; i++) {
      var r = displayModel.get(i)
      if (r.historyIndex === historyIndex) nowPinned = r.pinned
      if (r.pinned) order.push(r.historyIndex)
    }
    var next = root.history
    // Pinned or unpinned by the drag: flip it first, then apply the order.
    var unpinned = root.dragOrigPinned && !nowPinned
    if (nowPinned && !root.dragOrigPinned) next = ClipboardHistory.togglePinAt(next, historyIndex)
    next = ClipboardHistory.reorderPinned(next, order)
    // 1.19.0: unpinned by dragging = the newest History item (top, now).
    if (unpinned) next = ClipboardHistory.unpinToTop(next, historyIndex, Date.now())
    root.history = next
    root.saveHistory()
    root.rebuildDisplay(true)
    // reorderPinned keeps each slot's history position, so the dragged
    // entry now sits at the old index of whichever pinned row took its place.
    for (var j = 0; j < order.length; j++) {
      if (order[j] === historyIndex) { root.selectAbsolute(j); break }
    }
  }

  // keepScroll: after pin, delete, drag or a new entry, stay where the list
  // was scrolled (only nudging the cursor row into view), instead of jumping.
  function rebuildDisplay(keepScroll, movedHistoryIndex) {
    // Anchor: the first rows on screen (not the moved one) and their offset
    // from the top of the view; after the rebuild the same entry goes back
    // to the same spot, so rows moving elsewhere don't shift the viewport.
    var anchors = []
    if (keepScroll === true) {
      var top = resultList.indexAt(Style.space(10), resultList.contentY + 1)
      for (var a = Math.max(0, top); a >= 0 && a < displayModel.count && anchors.length < 4; a++) {
        var ar = displayModel.get(a)
        if (ar.historyIndex === movedHistoryIndex) continue
        var it = resultList.itemAtIndex(a)
        if (it) anchors.push({ key: root.rowKey(ar), pinned: ar.pinned, offset: it.y - resultList.contentY })
      }
    }
    var rows = ClipboardHistory.displayRows(root.history, root.filterText, root.displayLimit)
    var pinnedCount = 0
    for (var p = 0; p < rows.length; p++) if (rows[p].pinned) pinnedCount++
    root.hasPinned = pinnedCount > 0
    var now = Date.now()
    var multiDay = ClipboardHistory.spansDays(rows, now)

    var items = []
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      var t = row.entryType === "text" ? ClipboardHistory.rowTarget(row.fullText, root.homeDir) : (row.entryType === "image" ? row.imageActions.link : null)
      var pathCand = t && t.kind === "path?" ? t.target : ""
      if (pathCand) {
        var known = root.pathInfo[pathCand]
        t = known === "d" || known === "f" ? { kind: "path", target: ClipboardHistory.pathOpenTarget(pathCand, known) } : null
        if (known === undefined) root.queuePathCheck(pathCand)
      }
      items.push({
        entryType: row.entryType,
        fullText: row.fullText,
        previewText: row.previewText,
        previewImage: row.previewImage ? Util.fileUrl(row.previewImage) : "",
        path: row.path,
        mime: row.mime,
        pinned: row.pinned,
        slot: row.slot,
        sectionName: ClipboardHistory.sectionName(row.pinned, pinnedCount, root.filterText !== "", rows.length, row.at, now, multiDay),
        fromPhone: row.fromPhone === true,
        linkKind: t ? t.kind : "",
        linkTarget: t ? t.target : "",
        linkLabel: t && t.label ? t.label : "",
        pathCandidate: pathCand,
        copyText: row.imageActions ? row.imageActions.copy : "",
        copyTip: row.imageActions ? row.imageActions.copyTip : "",
        copyWifi: row.imageActions ? row.imageActions.wifi === true : false,
        ocrText: row.imageActions ? row.imageActions.ocr : "",
        ocrTip: row.imageActions ? row.imageActions.ocrTip : "",
        clipKey: ClipboardHistory.clipKeyOf(root.history[row.index], Qt.md5),
        hasMarkdown: row.hasMarkdown === true,
        historyIndex: row.index
      })
    }
    // The separator goes above the first heading after Pinned.
    var firstDay = ""
    for (var f = 0; f < items.length; f++) if (!items[f].pinned) { firstDay = items[f].sectionName; break }
    root.firstHistorySection = pinnedCount > 0 && root.filterText === "" ? firstDay : ""
    root.syncModel(items)

    if (root.reselectKey !== "") {
      for (var rs = 0; rs < displayModel.count; rs++) if (root.rowKey(displayModel.get(rs)) === root.reselectKey) { selectedIndex = rs; root.reselectKey = ""; break }
    }
    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count === 0) return
      if (keepScroll === true && root.restoreAnchor(anchors)) return
      resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  // Incremental update instead of clear()+append(): rows that stay keep
  // their delegate (no flicker, no re-layout); only removed/new/moved rows
  // change. Rows are matched by pinned state + content.
  function syncKey(r) { return (r.pinned ? "P" : "H") + root.rowKey(r) }
  function syncModel(items) {
    var want = {}
    for (var w = 0; w < items.length; w++) want[root.syncKey(items[w])] = (want[root.syncKey(items[w])] || 0) + 1
    for (var d = displayModel.count - 1; d >= 0; d--) {
      var k = root.syncKey(displayModel.get(d))
      if (want[k] > 0) want[k]--
      else displayModel.remove(d, 1)
    }
    for (var i = 0; i < items.length; i++) {
      var key = root.syncKey(items[i])
      var found = -1
      for (var j = i; j < displayModel.count; j++) if (root.syncKey(displayModel.get(j)) === key) { found = j; break }
      if (found < 0) { displayModel.insert(i, items[i]); continue }
      if (found !== i) displayModel.move(found, i, 1)
      var cur = displayModel.get(i)
      for (var prop in items[i]) if (cur[prop] !== items[i][prop]) displayModel.setProperty(i, prop, items[i][prop])
    }
    while (displayModel.count > items.length) displayModel.remove(displayModel.count - 1, 1)
  }

  // ---- path existence (4th button only for paths that exist) ------------
  readonly property string homeDir: Quickshell.env("HOME") || ""
  property var pathInfo: ({})
  property var pathQueue: []
  property bool mapsWebApp: false
  function queuePathCheck(p) {
    if (root.pathQueue.indexOf(p) < 0) root.pathQueue.push(p)
    pathCheckTimer.restart()
  }
  Timer {
    id: pathCheckTimer
    interval: 1
    onTriggered: {
      if (pathCheckProc.running || root.pathQueue.length === 0) { if (root.pathQueue.length) restart(); return }
      var n = root.pathSingle ? 1 : 200
      pathCheckProc.batch = root.pathQueue.slice(0, n)
      root.pathQueue = root.pathQueue.slice(n)
      pathCheckProc.command = ["stat", "-L", "--printf", "%F\n"].concat(["--"]).concat(pathCheckProc.batch)
      pathCheckProc.out = ""
      pathCheckProc.running = true
    }
  }
  Process {
    id: pathCheckProc
    property var batch: []
    property string out: ""
    // stat prints one line per existing path; missing ones only go to
    // stderr, so each path is checked on its own when the batch has gaps.
    stdout: SplitParser { onRead: function(line) { pathCheckProc.out += line + "\n" } }
    onExited: function(code) {
      var lines = pathCheckProc.out.split("\n").filter(function(x) { return x !== "" })
      var info = root.pathInfo
      if (code === 0 && lines.length === batch.length) {
        for (var i = 0; i < batch.length; i++) info[batch[i]] = lines[i] === "directory" ? "d" : "f"
      } else if (batch.length === 1) {
        info[batch[0]] = code === 0 ? (lines[0] === "directory" ? "d" : "f") : "-"
      } else {
        for (var j = 0; j < batch.length; j++) root.pathQueue.push(batch[j])
        root.pathSingle = true
      }
      root.pathInfo = info
      root.applyPathInfo()
      if (root.pathQueue.length) pathCheckTimer.restart()
    }
  }
  property bool pathSingle: false
  onPathSingleChanged: if (pathSingle) pathCheckTimer.interval = 1
  function applyPathInfo() {
    for (var i = 0; i < displayModel.count; i++) {
      var r = displayModel.get(i)
      if (!r.pathCandidate) continue
      var known = root.pathInfo[r.pathCandidate]
      var kind = known === "d" || known === "f" ? "path" : ""
      var target = kind ? ClipboardHistory.pathOpenTarget(r.pathCandidate, known) : ""
      if (r.linkKind !== kind) displayModel.setProperty(i, "linkKind", kind)
      if (r.linkTarget !== target) displayModel.setProperty(i, "linkTarget", target)
    }
  }
  Process {
    id: mapsCheckProc
    command: ["stat", "-L", "--printf", "x", "--", root.homeDir + "/.local/share/applications/Google Maps.desktop"]
    onExited: function(code) { root.mapsWebApp = code === 0 }
  }

  function restoreAnchor(anchors) {
    for (var k = 0; k < anchors.length; k++) {
      for (var j = 0; j < displayModel.count; j++) {
        var r = displayModel.get(j)
        if (r.pinned !== anchors[k].pinned || root.rowKey(r) !== anchors[k].key) continue
        resultList.positionViewAtIndex(j, ListView.Beginning)
        var it = resultList.itemAtIndex(j)
        if (!it) return false
        var maxY = resultList.originY + Math.max(0, resultList.contentHeight - resultList.height)
        resultList.contentY = Math.max(resultList.originY, Math.min(maxY, it.y - anchors[k].offset))
        return true
      }
    }
    return false
  }

  // ---- cursor -----------------------------------------------------------
  function select(delta) {
    root.disarmDelete()
    if (displayModel.count === 0) return
    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    if (root.armedDeleteIndex !== -1 && displayModel.get(root.selectedIndex).historyIndex !== root.armedDeleteIndex) root.disarmDelete()
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  // Alt+Shift+1…9, 0 (1.29.0): slot N = pins first, then the newest
  // history items (ClipboardHistory.slotHistoryIndex, the same mapping as
  // the global bind's paste-slot.sh), whatever the search shows. Pastes at
  // once through clipboard.sh, which sends Shift+Insert via Hyprland with
  // explicit mods, so the held Alt+Shift do not merge in (1.28.0 fix).
  function activateSlot(slot) {
    var hi = ClipboardHistory.slotHistoryIndex(root.history, slot)
    if (hi < 0) return
    if (ClipboardHistory.queueOnPick(root.queueKeys.length)) { root.close(); return }
    root.dropQueue()
    root.opened = false
    Quickshell.execDetached([root.helper, "paste", String(hi)])
  }

  function setFilter(nextFilter) {
    // Typing expands the field; only Esc collapses it (not an empty search).
    if (nextFilter !== "") root.searchExpanded = true
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function disarmPointer() { pointerGate.reset() }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    if (root.armedDeleteIndex !== -1 && index !== root.selectedIndex) root.disarmDelete()
    root.cursorActive = true
    root.selectedIndex = index
  }

  // ---- actions ----------------------------------------------------------
  function runOnIndex(index, action) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.dropQueue()
    root.opened = false
    Quickshell.execDetached([root.helper, action, String(row.historyIndex)])
  }

  // With 2+ rows selected, Enter / click / Alt+N close the popup, which
  // starts the queue (the selection is what gets pasted, in order).
  function activateIndex(index) {
    if (ClipboardHistory.queueOnPick(root.queueKeys.length)) { root.close(); return }
    root.runOnIndex(index, "paste")
  }
  function sendIndex(index) {
    if (index < 0 || index >= displayModel.count || displayModel.get(index).entryType !== "text" || !root.phoneOnline) return
    root.runOnIndex(index, "send")
  }
  // Link / e-mail rows: open in the default browser (new tab) or mail app,
  // detached so the shell never waits, then close the popup.
  function openLinkIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var r = displayModel.get(index)
    if (!r.linkTarget) return
    // Colour swatch: copy the code again (nothing to open).
    if (r.linkKind === "color") { root.copyIndex(index); return }
    root.dropQueue()
    root.close()
    if (r.linkKind === "maps") {
      var url = ClipboardHistory.mapsUrl(r.linkTarget)
      Quickshell.execDetached(root.mapsWebApp ? ["omarchy-launch-webapp", url] : ["xdg-open", url])
    } else {
      Quickshell.execDetached(["xdg-open", r.linkTarget])
    }
  }
  function copyIndex(index) { root.runOnIndex(index, "copy") }
  // Text read from an image / QR content: over stdin to wl-copy (never argv).
  function copyImageText(index) {
    if (index < 0 || index >= displayModel.count) return
    var r = displayModel.get(index)
    if (!r.copyText) return
    root.dropQueue()
    root.copyText(r.copyText)
    root.close()
    root.notify(r.copyWifi ? "󰌾" : "󰐲", r.copyTip.replace(/^Copy/, "Copied"), "Paste it with Super+V.", 2500)
  }
  function copyOcrText(index) {
    if (index < 0 || index >= displayModel.count) return
    var r = displayModel.get(index)
    if (!r.ocrText) return
    root.dropQueue()
    root.copyText(r.ocrText)
    root.close()
    // 1.25.0: show what was recognised, so a bad scan is caught before
    // pasting: one line, whitespace collapsed, cut with "…", markup escaped.
    // (1.28.0 tried a shorter preview with the hint in the title; 1.29.0 is
    // back to the 1.25–1.27 toast: 120 characters, hint on its own line.)
    root.notify("󰆏", r.ocrTip.replace(/^Copy/, "Copied"), ClipboardHistory.ocrPreview(r.ocrText) + "\nPaste it with Super+V.", 6000)
  }
  function openIndex(index) { root.runOnIndex(index, "open") }
  // Settings: copy one language's pacman command (the user runs it).
  function copyOcrInstall(lang) {
    if (!lang || !lang.cmd || lang.installed) return
    root.copyText(lang.cmd)
    root.notify("󰆍", "Copied: install " + lang.name + " (OCR)", "Paste it in a terminal with Ctrl+Shift+V, press Enter and type your password. Then reopen the clipboard.", 6000)
  }

  // Actions shown on a selected row, left to right (the extra arguments only
  // make the binding update).
  function rowActions(index, armedIndex, phone, count) {
    if (index < 0 || index >= displayModel.count) return []
    var row = displayModel.get(index)
    return ClipboardHistory.rowActionNames(row.historyIndex === root.armedDeleteIndex, root.phoneOnline, row.entryType === "text", row.linkKind, row.copyText !== "", row.hasMarkdown, row.ocrText !== "")
  }

  function runRowAction(name, index, byClick) {
    if (name === "link") root.openLinkIndex(index)
    else if (name === "copytext") root.copyImageText(index)
    else if (name === "markdown") root.runOnIndex(index, "paste-md")
    else if (name === "plaintext") root.runOnIndex(index, "paste")
    else if (name === "ocrtext") root.copyOcrText(index)
    else if (name === "send") root.sendIndex(index)
    else if (name === "pin") root.togglePinDisplayIndex(index)
    else if (name === "delete") root.requestDelete(index, byClick === true)
  }

  onSelectedIndexChanged: root.actionFocus = -1

  // ---- search field keys --------------------------------------------------
  // The search line is a real text field. Popup shortcuts are taken first
  // (ClipboardHistory.searchKeyAction); every other key edits the text, so
  // Ctrl+A, Ctrl+C/X/V, Shift+arrows and Ctrl+Backspace behave as usual.
  function handleSearchKey(event) {
    if (root.clearConfirmOpen) {
      clearConfirm.handleKey(event)
      event.accepted = true
      return
    }

    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var alt = (event.modifiers & Qt.AltModifier) !== 0
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0

    // 1.31.0: Ctrl+Z undoes the last delete (else it edits the search text).
    if (event.key === Qt.Key_Z && ctrl && !alt && !shift && root.undoDelete()) { event.accepted = true; return }

    // Left/Right walk the selected row's actions, Enter presses the focused one.
    if (root.cursorActive && displayModel.count > 0) {
      var step = ClipboardHistory.actionFocusStep(root.actionFocus, root.selectedActions.length, {
        key: event.key, ctrl: ctrl, alt: alt, shift: shift,
        atTextEnd: searchInput.cursorPosition === searchInput.text.length && searchInput.selectedText.length === 0
      })
      var pressed = step.trigger ? root.focusedAction : ""
      root.actionFocus = step.focus
      // Enter on a focused button = a click (delete arms first).
      if (pressed) root.runRowAction(pressed, root.selectedIndex, true)
      if (step.consumed) { event.accepted = true; return }
    }
    var slot = ClipboardHistory.slotFromKey(event.nativeScanCode, event.key)
    var action = ClipboardHistory.searchKeyAction({
      key: event.key, ctrl: ctrl, alt: alt, shift: shift, slot: slot,
      hasSelection: searchInput.selectedText.length > 0,
      queued: root.queueKeys.length
    })
    // Any key other than Del cancels an armed pinned delete.
    if (action !== "delete" && !ClipboardHistory.isModifierKey(event.key)) root.disarmDelete()

    switch (action) {
    case "escape":
      // Esc: clear the search, then collapse the field, then close.
      var esc = ClipboardHistory.escapeAction(root.filterText, root.searchExpanded)
      if (esc === "clear") root.setFilter("")
      else if (esc === "collapse") root.searchExpanded = false
      else root.close()
      break
    case "slot": root.activateSlot(slot); break
    case "ignore": break
    case "queueToggle": if (root.cursorActive) root.toggleQueueIndex(root.selectedIndex); break
    case "queueStart": root.startQueue(); break
    case "queueClear": root.queueKeys = []; break
    case "copySelection": root.copyText(searchInput.selectedText); break
    case "cutSelection":
      root.copyText(searchInput.selectedText)
      searchInput.remove(searchInput.selectionStart, searchInput.selectionEnd)
      break
    case "clearSearch": root.setFilter(""); break
    case "pin": if (root.cursorActive) root.togglePinDisplayIndex(root.selectedIndex); break
    case "private": root.setPrivate(!root.privateMode, false); break
    case "clear": root.requestClearHistory(); break
    case "delete": if (root.cursorActive) root.requestDelete(root.selectedIndex); break
    case "send": if (root.cursorActive) root.sendIndex(root.selectedIndex); break
    case "up": root.select(-1); break
    case "down": root.select(1); break
    case "pageUp": root.select(-6); break
    case "pageDown": root.select(6); break
    case "home": root.selectAbsolute(0); break
    case "end": root.selectAbsolute(displayModel.count - 1); break
    case "enter":
      if (root.cursorActive && alt) root.openIndex(root.selectedIndex)
      else if (root.cursorActive && shift) root.copyIndex(root.selectedIndex)
      else if (root.cursorActive) root.activateIndex(root.selectedIndex)
      else if (displayModel.count > 0) root.cursorActive = true
      break
    default:
      return
    }
    event.accepted = true
  }

  // Ctrl+C / Ctrl+X in the search field. The text goes to wl-copy over stdin
  // (never argv, never a file), so the copy outlives the popup and even a
  // shell restart, and the capture watcher records it like any other copy.
  function copyText(text) {
    if (!text) return
    copyProc.nextText = text
    if (!copyProc.running) copyProc.startCopy()
  }

  onFilterTextChanged: {
    root.actionFocus = -1
    if (searchInput.text !== root.filterText) searchInput.text = root.filterText
  }

  Process {
    id: copyProc
    property string nextText: ""
    property string sending: ""
    command: ["wl-copy"]
    function startCopy() {
      sending = nextText
      nextText = ""
      stdinEnabled = true
      running = true
    }
    onStarted: {
      write(sending)
      sending = ""
      stdinEnabled = false
    }
    onExited: if (nextText) startCopy()
  }

  Process {
    id: ocrLangProc
    command: [root.scanScript, "--langs"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var st = null
        try { st = JSON.parse(String(text)) } catch (e) { st = null }
        if (st && Array.isArray(st.installed)) { root.ocrInfo = { installed: st.installed, used: String(st.used || ""), env: String(st.env || ""), hints: Array.isArray(st.hints) ? st.hints : [] }; root.ocrInfoUpdated() }
      }
    }
  }
  Process {
    id: ocrSizesProc
    command: [root.scanScript, "--sizes"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var st = null
        try { st = JSON.parse(String(text)) } catch (e) { st = null }
        if (st && typeof st === "object" && !Array.isArray(st)) root.ocrSizes = st
      }
    }
  }
  Timer {
    id: ocrWatchTimer
    interval: 3000
    repeat: true
    onTriggered: {
      if (++root.ocrWatchTicks > 200) { stop(); root.ocrInstalling = ""; root.ocrRemoving = ""; return }
      if (!ocrLangProc.running) ocrLangProc.running = true
    }
  }

  Process {
    id: clipKeyProc
    command: [root.helper, "current"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var k = String(text).trim()
        if (k === "empty") { root.currentClipKey = ""; root.fillEmptyClipboard() }
        else root.currentClipKey = k
      }
    }
  }

  // 1.20.0: the clipboard is empty (nothing copied since login, or the app
  // that owned it closed) and the popup just opened: put the top pinned item
  // on it, so Ctrl+V works right away. Copy only, never pasted; nothing
  // happens without a pinned item.
  function fillEmptyClipboard() {
    if (!root.opened) return
    var i = ClipboardHistory.firstPinnedIndex(root.history)
    if (i < 0) return
    Quickshell.execDetached([root.helper, "copy", String(i)])
    root.currentClipKey = ClipboardHistory.clipKeyOf(root.history[i], Qt.md5)
  }

  // 1.27.0: direct feedback POST (only with feedbackEndpoint set). The text
  // goes over stdin, never argv; the reply is the Worker's JSON plus curl's
  // exit code on the last line.
  Process {
    id: feedbackProc
    property string payload: ""
    command: ["curl", "-sS", "--max-time", "10", "-H", "Content-Type: application/json",
              "--data-binary", "@-", "-w", "\n%{exitcode}", root.feedbackEndpoint]
    stdinEnabled: true
    onStarted: { write(payload); payload = ""; stdinEnabled = false }
    onExited: stdinEnabled = true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = ClipboardHistory.feedbackResultFromCurl(text)
        if (r.ok && root.feedbackPendingInput) root.feedbackPendingInput.text = ""
        root.feedbackPendingInput = null
        root.feedbackNote = r.note
        root.feedbackSent = r.ok
      }
    }
  }

  // queue.sh start: the items go over stdin (never argv).
  Process {
    id: queueProc
    property string payload: ""
    command: [root.queueScript, "start"]
    stdinEnabled: true
    onStarted: { write(payload); payload = ""; stdinEnabled = false }
    onExited: stdinEnabled = true
  }

  // Also asked on every open: the file watch can miss a file created later.
  Process {
    id: queueStatusProc
    command: [root.queueScript, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text).trim()
        var st = null
        try { st = t ? JSON.parse(t) : null } catch (e) { st = null }
        root.queueRunning = st && st.count > 0 ? { pos: Number(st.pos || 0), count: Number(st.count) } : null
      }
    }
  }

  FileView {
    id: queueFile
    path: root.ready ? root.queuePath : ""
    watchChanges: true
    printErrors: false
    onLoaded: root.applyQueueFile(text())
    onLoadFailed: root.queueRunning = null
    onFileChanged: reload()
  }

  // ---- startup ----------------------------------------------------------
  Component.onCompleted: {
    Bridge.setOverlay(root)
    initProc.running = true
  }
  Component.onDestruction: { Bridge.clearOverlay(root); root.removeGlobalKeysIfGone() }

  ListModel { id: displayModel }

  PointerMoveGate {
    id: pointerGate
    referenceItem: resultList
  }

  FileView {
    id: historyFile
    path: root.ready ? root.historyPath : ""
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadHistory(text())
    onLoadFailed: root.loadHistory("[]")
  }

  // Auto-delete also runs hourly while the shell is up.
  Timer {
    interval: 3600000
    running: root.historyLoaded
    repeat: true
    onTriggered: root.pruneOld()
  }

  FileView {
    id: stateFile
    path: root.ready ? root.statePath : ""
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
    onFileChanged: reload()
  }


  Timer {
    id: armTimer
    interval: 3000
    onTriggered: root.armedDeleteIndex = -1
  }

  Timer {
    id: originTimer
    interval: 400
    onTriggered: if (!statusProc.running) statusProc.running = true; else restart()
  }

  Process {
    id: statusProc
    command: ["flux-cli", "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyFluxStatus(text)
    }
  }

  // Images nobody points to any more (deleted, cleared, over the limit).
  Timer {
    id: pruneTimer
    interval: 3000
    onTriggered: Quickshell.execDetached([root.helper, "prune"])
  }

  // Data dir first (0700, one-time import of the stock history), then reap
  // watchers of a previous shell, then start ours. pdeathsig makes the kernel
  // kill the watchers whenever the shell exits.
  Process {
    id: initProc
    command: ["bash", "-c", "\"$1\" init; pkill -f 'wl-paste .*--watch .*/timon\\.clipboard/capture\\.sh' || true", "init", root.helper]
    onExited: {
      root.ready = true
      currentProc.running = true
      textWatchProc.running = true
      imageWatchProc.running = true
    }
  }

  Process {
    id: fluxProc
    // Pass the wanted state instead of "sync": state.json is written
    // asynchronously, so a quick on→off could read the old value and leave
    // Flux paused.
    command: [root.fluxScript, root.privateMode ? "pause" : "resume"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var s = String(text).trim()
        root.fluxState = s
        root.fluxPresent = s !== "" && s !== "absent"
        root.fluxPaused = s === "paused"
      }
    }
    onExited: {
      if (root.fluxResync) {
        root.fluxResync = false
        Qt.callLater(function() { fluxProc.running = true })
      }
    }
  }

  Process {
    id: currentProc
    command: [root.captureScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.addClipboardJson(text)
    }
  }

  Process {
    id: textWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "text", "--watch", root.captureScript, "text"]
    onExited: watchRestartTimer.restart()
    stdout: SplitParser {
      onRead: function(data) { root.addClipboardJson(data) }
    }
  }

  Process {
    id: imageWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "image/png", "--watch", root.captureScript, "image/png"]
    onExited: watchRestartTimer.restart()
    stdout: SplitParser {
      onRead: function(data) { root.addClipboardJson(data) }
    }
  }

  Timer {
    id: watchRestartTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (!textWatchProc.running) textWatchProc.running = true
      if (!imageWatchProc.running) imageWatchProc.running = true
    }
  }

  // ---- UI ---------------------------------------------------------------
  // Same popup as the stock Wi-Fi panel: Omarchy's KeyboardPanel, anchored
  // under the bar icon (also when opened with the keyboard shortcut), with
  // its look, outside-click dismissal and one-popup-at-a-time coordination.
  // Without the bar icon it opens at the top-left corner.
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorButton
    bar: root.anchorBar
    // The bar widget owns the popout (stock underline under the icon); its
    // close() closes this overlay.
    owner: root.anchorWidget || root
    open: root.opened
    focusTarget: searchInput
    contentWidth: root.cardWidth
    contentHeight: root.cardHeight

    Item {
      anchors.fill: parent

      Item {
        id: confirmLayer
        anchors.fill: parent
        z: root.clearConfirmOpen ? 20 : 0

        ConfirmDialog {
          id: clearConfirm
          anchors.fill: parent
          opened: root.clearConfirmOpen
          z: 10
          message: "Delete " + root.unpinnedCount + (root.unpinnedCount === 1 ? " history item" : " history items") + "? Pinned items stay."
          confirmText: "Delete"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelClearHistory()
          onConfirmed: root.confirmClearHistory()
        }
      }

      Column {
        anchors.fill: parent
        spacing: root.contentSpacing

        // Search line + entry count
        Item {
          width: parent.width
          height: root.headerHeight

          // Field box styled like the stock Wi-Fi password field
          // (qs.Ui TextField: Style.controlFill + Border.controlSpec, focus state).
          // Collapsed header: title in the stock panel title style
          // (PanelHero: Style.font.title, bold) and the stock icon button.
          Text {
            id: headerTitle
            objectName: "headerTitle"
            visible: !root.searchShown
            anchors.left: parent.left
            // Same inset as the row text (row leftMargin, stock Style.space(10)).
            anchors.leftMargin: Style.space(10)
            anchors.right: incognitoBadge.visible ? incognitoBadge.left : (searchButton.visible ? searchButton.left : parent.right)
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Clipboard Manager"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }
          // Square, styled exactly like the expanded search field (same
          // fill, border and radius as searchBox), icon centred.
          BorderSurface {
            id: searchButton
            objectName: "searchButton"
            visible: !root.searchShown
            // Above searchInput: the (invisible while collapsed) text field
            // spans the whole row and is declared later, so without this it
            // took most clicks meant for the button.
            z: 2
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: height
            color: searchBox.color
            borderSpec: searchBox.spec
            radius: searchBox.radius

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "󰍉"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.icon
            }

            MouseArea {
              id: searchButtonMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.searchExpanded = true
                searchInput.forceActiveFocus()
              }
            }
          }

          BorderSurface {
            id: searchBox
            visible: root.searchShown
            anchors.left: parent.left
            anchors.right: incognitoBadge.visible ? incognitoBadge.left : parent.right
            anchors.rightMargin: incognitoBadge.visible ? Style.space(12) : 0
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            // The stock focus tokens (fill 0.08, border 0.25) barely show on the
            // popup background, so: a clearly lighter fill and the stock
            // normal control border (0.4), same radius and insets.
            readonly property var spec: Border.controlSpec("normal", root.foreground, root.accent)
            color: Util.alpha(root.foreground, 0.12)
            borderSpec: spec
            radius: Style.cornerRadius
          }

          // Always holds the keyboard focus, so typing while collapsed lands
          // here and expands the field; invisible (no caret) while collapsed.
          TextInput {
            id: searchInput
            opacity: root.searchShown ? 1 : 0
            cursorVisible: root.searchShown && activeFocus
            anchors.left: searchBox.left
            anchors.right: searchBox.right
            anchors.leftMargin: Style.spacing.controlPaddingX + Border.left(searchBox.spec)
            anchors.rightMargin: Style.spacing.controlPaddingX + Border.right(searchBox.spec)
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            verticalAlignment: TextInput.AlignVCenter
            focus: true
            clip: true
            selectByMouse: true
            persistentSelection: false
            color: root.foreground
            selectionColor: root.selectedBackground
            selectedTextColor: root.selectedText
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) { root.handleSearchKey(event) }
            onTextChanged: if (text !== root.filterText) root.setFilter(text)

            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              visible: searchInput.text === ""
              textFormat: Text.PlainText
              text: "Search clipboard…"
              color: root.foreground
              opacity: 0.58
              font: searchInput.font
              elide: Text.ElideRight
            }
          }

          // Small badge, only while incognito is on.
          Rectangle {
            id: incognitoBadge
            visible: root.privateMode
            anchors.right: searchButton.visible ? searchButton.left : parent.right
            anchors.rightMargin: searchButton.visible ? Style.space(8) : 0
            anchors.verticalCenter: parent.verticalCenter
            width: badgeText.implicitWidth + Style.space(12)
            height: badgeText.implicitHeight + Style.space(4)
            radius: root.cornerRadius
            color: Util.alpha(root.accent, 0.16)

            Text {
              id: badgeText
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "󰗹 Incognito"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          MouseArea {
            id: badgeMouse
            anchors.fill: incognitoBadge
            visible: incognitoBadge.visible
            hoverEnabled: true

            PanelToolTip {
              visible: badgeMouse.containsMouse
              text: root.fluxPaused ? "Incognito: copies not saved, Flux sync paused" : "Incognito: copies not saved"
            }
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - footer.implicitHeight - root.contentSpacing * 2

          // Settings sections (Components), one per page of the settings window.
          Component {
            id: secGeneral
            Column {
              id: sec
              width: parent ? parent.width : 0
              spacing: Style.space(2)

                // 1.25.0: sections like the stock Display panel (PanelSeparator +
                // PanelSectionHeader between them), most-used settings first.
                Repeater {
                  model: [
                    { key: "incognito", label: "󰗹  Incognito", value: root.privateMode ? "on" : "off", hint: "Ctrl+I" }
                  ]
                  delegate: infoActionRow
                }
                Text {
                  objectName: "incognitoHint"
                  x: Style.space(10)
                  bottomPadding: Style.space(8)
                  width: parent.width - Style.space(20)
                  wrapMode: Text.Wrap
                  textFormat: Text.PlainText
                  text: "Turn it on or off with Ctrl+I in the popup, or right-click the clipboard icon in the top bar. Nothing is saved while it is on."
                  color: root.dimText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Repeater {
                  model: [
                    { icon: "󰍽", label: "Left click action", value: root.clickAction === "copy" ? "stays open" : "closes the popup" }
                  ]
                  delegate: infoValueRow
                }

                // Stock pills, like the Display panel's SCALE row.
                Grid {
                  id: clickRow
                  objectName: "clipClickRow"
                  x: Style.space(10)
                  width: parent.width - Style.space(20)
                  columns: 2
                  spacing: Style.spacing.xs
                  readonly property real cellWidth: (width - spacing) / 2

                  Repeater {
                    model: [
                      { key: "copy", label: "Select (copy only)" },
                      { key: "paste", label: "Select, paste & close" }
                    ]

                    Button {
                      required property var modelData
                      objectName: "clipClickPill"
                      width: clickRow.cellWidth
                      text: modelData.label
                      fontSize: Style.font.caption
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      horizontalPadding: Style.spacing.sm
                      verticalPadding: Style.spacing.controlPaddingY
                      bordered: true
                      active: root.clickAction === modelData.key
                      onClicked: root.setClickAction(modelData.key)
                    }
                  }
                }

                // 1.30.0: update check, off by default.
                Item { width: 1; height: Style.space(8) }
                Repeater {
                  model: [
                    { key: "updateCheck", label: "󰚰  Check for updates: " + (root.updateCheck ? "on" : "off"), value: "", hint: "" }
                  ]
                  delegate: infoActionRow
                }
                Text {
                  objectName: "updateCheckStatus"
                  x: Style.space(10)
                  bottomPadding: Style.space(8)
                  width: parent.width - Style.space(20)
                  wrapMode: Text.Wrap
                  textFormat: Text.PlainText
                  text: !root.updateCheck
                    ? "Off. When on, Nice Clipboard asks GitHub once a day for the newest published version (an anonymous request, nothing about you or this computer is sent) and shows a note in the popup when there is one."
                    : (root.updateAvailable ? "Version " + root.updateLatest + " is available (you have " + root.pluginVersion + ")."
                      : (root.updateLatest !== "" ? "Up to date (" + root.pluginVersion + "). Checked once a day."
                        : "On: checked once a day when the popup opens. No published version found yet."))
                  color: root.dimText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
            }
          }

          Component {
            id: secHistory
            Column {
              id: sec
              width: parent ? parent.width : 0
              // 1.31.0: laid out like the stock display panel: section
              // header + pills (10 apart), separator, next section, 14 apart.
              spacing: Style.space(14)

              Column {
                width: parent.width
                spacing: Style.space(10)
                PanelSectionHeader {
                  objectName: "clipKeepHeader"
                  x: Style.space(10)
                  text: "Automatically delete items after"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                // Auto-delete presets: the stock display panel's SCALE pills
                // (Button, caption size, bordered, same padding and spacing).
                Grid {
                  id: keepRow
                  objectName: "clipKeepRow"
                  x: Style.space(10)
                  width: parent.width - Style.space(20)
                  columns: ClipboardHistory.KEEP_DAYS.length
                  spacing: Style.spacing.xs
                  readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

                  Repeater {
                    model: ClipboardHistory.KEEP_DAYS

                    Button {
                      required property int modelData
                      objectName: "clipKeepPill"
                      width: keepRow.cellWidth
                      text: ClipboardHistory.keepDaysLabel(modelData)
                      fontSize: Style.font.caption
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      horizontalPadding: Style.spacing.sm
                      verticalPadding: Style.spacing.controlPaddingY
                      bordered: true
                      active: root.keepDays === modelData
                      onClicked: root.setKeepDays(modelData)
                    }
                  }
                }
              }

                PanelSeparator { width: parent.width; foreground: root.foreground }

                Repeater {
                  model: [
                    { key: "clear", label: "󰩺  Clear history (pins stay)", value: "", hint: "Shift+Del" }
                  ]
                  delegate: infoActionRow
                }
            }
          }

          Component {
            id: secFlux
            Column {
              id: sec
              width: parent ? parent.width : 0
              spacing: Style.space(2)

                // Flux section (the footer phone button opens the view here).
                Repeater {
                  model: [
                    { icon: "󰄜", label: root.phoneOnline ? (root.phoneName || "Phone") : "No phone connected", value: root.fluxStatusText },
                    { icon: "󰓦", label: "Last sync", value: ClipboardHistory.agoLabel(root.lastSync, root.nowSec) }
                  ]
                  delegate: infoValueRow
                }

                Rectangle {
                  id: sendRow
                  readonly property bool enabled: root.phoneOnline && !root.fluxPaused
                  width: parent.width
                  height: root.rowHeight
                  radius: root.cornerRadius
                  color: sendMouse.containsMouse && enabled ? Util.alpha(root.foreground, 0.08) : "transparent"
                  opacity: enabled ? 1 : 0.5

                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: "󰒊  Send current clipboard"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  Text {
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: "Ctrl+S"
                    color: root.dimText
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    id: sendMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: sendRow.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.sendCurrentClipboard()
                  }
                }
            }
          }

          Component {
            id: secOcr
            Column {
              id: sec
              width: parent ? parent.width : 0
              // 1.31.0: installed languages as rows (in use, size on disk,
              // Remove), then "Add language" pills for the others. Sections
              // like the stock display panel: header + content 10 apart,
              // separator, 14 apart. Only installed packs are ever used;
              // OMARCHY_OCR_LANGS, if set, decides like in Omarchy's own text
              // capture (Super+Ctrl+Print).
              spacing: Style.space(14)
              readonly property var installedRows: ClipboardHistory.ocrInstalledRows(root.ocrInfo.installed, root.ocrSizes, root.ocrOff, root.ocrInfo.env)
              readonly property var availableRows: ClipboardHistory.ocrAvailableRows(root.ocrInfo.installed, root.ocrSizes)

              Column {
                width: parent.width
                spacing: Style.space(10)
                PanelSectionHeader {
                  x: Style.space(10)
                  text: "Installed languages"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }
                Text {
                  objectName: "clipOcrNone"
                  visible: sec.installedRows.length === 0
                  x: Style.space(10)
                  width: parent.width - Style.space(20)
                  wrapMode: Text.WordWrap
                  textFormat: Text.PlainText
                  text: "None: tesseract is not installed (sudo pacman -S tesseract tesseract-data-eng)."
                  color: root.dimText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Column {
                  width: parent.width
                  spacing: Style.space(2)
                  Repeater {
                    model: sec.installedRows
                    delegate: Rectangle {
                      id: langRow
                      required property var modelData
                      objectName: "clipOcrInstalled"
                      readonly property string code: modelData.code
                      readonly property bool canToggle: modelData.toggleNote === ""
                      width: parent.width
                      height: root.rowHeight
                      radius: root.cornerRadius
                      color: langMouse.containsMouse ? Util.alpha(root.foreground, 0.05) : "transparent"
                      MouseArea { id: langMouse; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

                      Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Style.space(10)
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: langRow.modelData.name
                        color: langRow.modelData.inUse ? root.foreground : root.dimText
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                      }
                      Row {
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(10)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(14)
                        Text {
                          objectName: "clipOcrSize"
                          anchors.verticalCenter: parent.verticalCenter
                          textFormat: Text.PlainText
                          text: langRow.modelData.size
                          color: root.dimText
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                        // In use: the stock-looking switch from the
                        // incognito row; clicking it switches the language.
                        Item {
                          objectName: "clipOcrUse"
                          readonly property bool on: langRow.modelData.inUse
                          anchors.verticalCenter: parent.verticalCenter
                          width: useLabel.implicitWidth + Style.space(6) + useSwitch.width
                          height: root.rowHeight
                          opacity: langRow.canToggle ? 1 : 0.45
                          Text {
                            id: useLabel
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: "in use"
                            color: root.dimText
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                          }
                          Rectangle {
                            id: useSwitch
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.round(Style.font.body * 2.2)
                            height: Math.round(Style.font.body * 1.2)
                            radius: height / 2
                            color: parent.on ? root.accent : Util.alpha(root.foreground, 0.22)
                            Rectangle {
                              width: parent.height - Style.space(4)
                              height: width
                              radius: width / 2
                              y: Style.space(2)
                              x: parent.parent.on ? parent.width - width - Style.space(2) : Style.space(2)
                              color: parent.parent.on ? root.background : root.foreground
                              Behavior on x { NumberAnimation { duration: 120 } }
                            }
                          }
                          MouseArea {
                            anchors.fill: parent
                            enabled: langRow.canToggle
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleOcrUse(langRow.code)
                          }
                        }
                        Button {
                          objectName: "clipOcrRemove"
                          visible: langRow.modelData.protect === ""
                          anchors.verticalCenter: parent.verticalCenter
                          text: root.ocrRemoving === langRow.code ? "Removing…" : "Remove"
                          iconText: "󰩺"
                          fontSize: Style.font.caption
                          iconSize: Style.font.caption
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          horizontalPadding: Style.spacing.sm
                          verticalPadding: Style.spacing.controlPaddingY
                          bordered: true
                          tooltipText: "Opens a terminal: sudo pacman -R tesseract-data-" + langRow.code
                          onClicked: root.removeOcrLanguage(langRow.modelData)
                        }
                        Text {
                          objectName: "clipOcrProtected"
                          visible: langRow.modelData.protect !== ""
                          anchors.verticalCenter: parent.verticalCenter
                          textFormat: Text.PlainText
                          text: langRow.modelData.protect
                          color: root.dimText
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                      }
                    }
                  }
                }
                Text {
                  objectName: "clipOcrUseNote"
                  visible: sec.installedRows.length > 0
                  x: Style.space(10)
                  width: parent.width - Style.space(20)
                  wrapMode: Text.WordWrap
                  textFormat: Text.PlainText
                  text: root.ocrInfo.env
                    ? "OMARCHY_OCR_LANGS=" + root.ocrInfo.env + " is set, so it decides which languages are used."
                    : "Screenshots and images are read in every language that is in use (at least one stays on); each extra one makes reading a little slower. Sizes are the space on disk (pacman)."
                  color: root.dimText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

                // 1.27.0: suggestions from the locale / keyboard layout /
                // dictionaries. Copy puts the pacman command on the
                // clipboard (never run here: it needs sudo); ✕ hides it for good.
                Repeater {
                  model: root.ocrSuggest
                  delegate: Column {
                    required property var modelData
                    objectName: "clipOcrSuggest"
                    readonly property string code: modelData.code
                    x: Style.space(10)
                    width: sec.width - Style.space(20)
                    spacing: Style.spacing.xs
                    topPadding: Style.space(6)

                    Text {
                      objectName: "clipOcrSuggestText"
                      width: parent.width
                      wrapMode: Text.WordWrap
                      textFormat: Text.PlainText
                      text: "󰗊  " + modelData.text
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                    Row {
                      spacing: Style.spacing.xs
                      Button {
                        objectName: "clipOcrSuggestInstall"
                        text: "Install " + modelData.name
                        iconText: "󰇚"
                        fontSize: Style.font.caption
                        iconSize: Style.font.caption
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        horizontalPadding: Style.spacing.sm
                        verticalPadding: Style.spacing.controlPaddingY
                        bordered: true
                        active: true
                        tooltipText: "Opens a terminal: " + modelData.cmd.replace("sudo pacman -S", "sudo pacman -S --needed")
                        onClicked: root.installOcrLanguage({ code: modelData.code, name: modelData.name, installed: false })
                      }
                      Button {
                        objectName: "clipOcrSuggestDismiss"
                        text: "Not now"
                        iconText: "󰅖"
                        fontSize: Style.font.caption
                        iconSize: Style.font.caption
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        horizontalPadding: Style.spacing.sm
                        verticalPadding: Style.spacing.controlPaddingY
                        bordered: true
                        tooltipText: "Don't suggest " + modelData.name + " again"
                        onClicked: root.dismissOcrSuggestion(modelData.code)
                      }
                    }
                  }
                }

              PanelSeparator { width: parent.width; foreground: root.foreground; visible: sec.availableRows.length > 0 }

              Column {
                width: parent.width
                spacing: Style.space(10)
                visible: sec.availableRows.length > 0
                PanelSectionHeader {
                  x: Style.space(10)
                  text: "Add language"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }
                Text {
                  objectName: "clipOcrHelp"
                  x: Style.space(10)
                  width: parent.width - Style.space(20)
                  wrapMode: Text.WordWrap
                  textFormat: Text.PlainText
                  text: "Click one to install it: a terminal opens, shows the command and asks for your password (official Arch package)."
                        + (Object.keys(root.ocrSizes).length ? " Sizes are the download (pacman)." : "")
                  color: root.dimText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Grid {
                  id: ocrLangGrid
                  objectName: "clipOcrLangGrid"
                  x: Style.space(10)
                  width: parent.width - Style.space(20)
                  columns: 3
                  spacing: Style.spacing.xs
                  readonly property real cellWidth: (width - spacing * (columns - 1)) / columns
                  Repeater {
                    model: sec.availableRows
                    Button {
                      required property var modelData
                      objectName: "clipOcrLang"
                      readonly property string code: modelData.code
                      width: ocrLangGrid.cellWidth
                      text: modelData.name + (modelData.size !== "" ? " · " + modelData.size : "")
                      iconText: root.ocrInstalling === code ? "󰔟" : "󰇚"
                      fontSize: Style.font.caption
                      iconSize: Style.font.caption
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      horizontalPadding: Style.spacing.sm
                      verticalPadding: Style.spacing.controlPaddingY
                      bordered: true
                      tooltipText: root.ocrInstalling === code ? "Installing… (see the terminal)" : "Install: sudo pacman -S --needed tesseract-data-" + code
                      onClicked: root.installOcrLanguage({ code: modelData.code, name: modelData.name, installed: false })
                    }
                  }
                }
              }
            }
          }

          Component {
            id: secUninstall
            Column {
              id: sec
              width: parent ? parent.width : 0
              spacing: Style.space(10)
              Repeater {
                model: [
                  { kind: "plugin", label: "Uninstall plugin", text: "Removes Nice Clipboard, the shortcuts it added, its clipboard history and settings. Omarchy's own clipboard comes back." },
                  { kind: "languages", label: "Uninstall plugin and languages", text: "The same, plus the text recognition languages Nice Clipboard installed. Languages that were there before, or that something else needs (like English for Omarchy's screenshot text), stay." }
                ]
                delegate: Column {
                  required property var modelData
                  x: Style.space(10)
                  width: sec.width - Style.space(20)
                  spacing: Style.space(6)
                  bottomPadding: Style.space(8)
                  // Armed: red under the button, so it stays red while hovered
                  // (the stock Button swaps its fill for the hover fill).
                  Item {
                    width: uninstallBtn.width
                    height: uninstallBtn.height
                    Rectangle {
                      objectName: "uninstallArmedFill"
                      anchors.fill: parent
                      radius: Style.cornerRadius
                      color: root.urgent
                      visible: uninstallBtn.armed
                    }
                    Button {
                      id: uninstallBtn
                      objectName: "uninstallButton"
                      readonly property bool armed: root.uninstallArmed === modelData.kind
                      text: armed ? "Click again to uninstall" : modelData.label
                      iconText: armed ? "󰄬" : "󰆴"
                      fontSize: Style.font.body
                      iconSize: Style.font.body
                      foreground: armed ? "#ffffff" : root.foreground
                      background: "transparent"
                      fontFamily: root.fontFamily
                      horizontalPadding: Style.spacing.sm
                      verticalPadding: Style.spacing.controlPaddingY
                      bordered: true
                      onClicked: root.requestUninstall(modelData.kind)
                      onHovered: function(isHovered) { if (!isHovered && armed) root.uninstallArmed = "" }
                    }
                  }
                  Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    text: modelData.text
                    color: root.dimText
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          Component {
            id: secFilters
            Column {
              id: sec
              width: parent ? parent.width : 0
              spacing: Style.space(2)

                // Search filters: one row per filter, the example to type on
                // the right; combine them with text, e.g. "type:link github".
                Repeater {
                  id: filterRows
                  model: ClipboardHistory.SEARCH_FILTER_EXAMPLES.map(function(f) { return { icon: "󰍉", label: f.label, value: f.value } })
                  delegate: infoValueRow
                }
            }
          }

          Component {
            id: secShortcuts
            Column {
              id: sec
              width: parent ? parent.width : 0
              spacing: Style.space(2)

                Repeater {
                  model: [
                    { key: "globalKeys", label: "󰌌  Global shortcuts (Alt+V, Alt+Shift+1…9, 0): " + (root.globalKeys ? "on" : "off"), value: "", hint: "" }
                  ]
                  delegate: infoActionRow
                }
                Text {
                  objectName: "globalKeysStatus"
                  x: Style.space(10)
                  bottomPadding: Style.space(8)
                  width: parent.width - Style.space(20)
                  visible: text !== ""
                  wrapMode: Text.Wrap
                  textFormat: Text.PlainText
                  text: root.globalKeys ? (root.globalKeysInfo.text || "Checking…") : "Off: Nice Clipboard adds no keys. Keys from your own Hyprland config still work."
                  color: root.dimText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Repeater {
                  model: [
                    { icon: "󰅍", label: "Open clipboard", value: "Alt+V · Super+Ctrl+V" },
                    { icon: "󰐃", label: "Paste slot N: pinned items, then the newest history items", value: "Alt+Shift+1…9, 0" },
                    { icon: "󰒆", label: "Paste queue: pick rows, then paste in order", value: "Ctrl+click · Ctrl+Enter" }
                  ]
                  delegate: infoValueRow
                }
            }
          }

          Component {
            id: secFeedback
            Column {
              id: sec
              width: parent ? parent.width : 0
              spacing: Style.space(2)

                // Same box style as the search field.
                BorderSurface {
                  id: feedbackBox
                  objectName: "feedbackBox"
                  x: Style.space(10)
                  width: parent.width - Style.space(20)
                  height: Math.max(root.rowHeight * 2, feedbackInput.contentHeight + Style.space(8))
                  color: searchBox.color
                  borderSpec: searchBox.spec
                  radius: searchBox.radius

                  TextEdit {
                    id: feedbackInput
                    objectName: "feedbackInput"
                    anchors.fill: parent
                    anchors.margins: Style.spacing.controlPaddingX
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    color: root.foreground
                    selectionColor: root.selectedBackground
                    selectedTextColor: root.selectedText
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    onTextChanged: if (text !== "") { root.feedbackNote = ""; root.feedbackSent = false }
                    // 1.30.0: Enter sends, Shift+Enter is a new line, Esc
                    // leaves the field; other keys type.
                    Keys.onPressed: function(event) {
                      var k = ClipboardHistory.feedbackKey(event.key, event.modifiers & Qt.ShiftModifier, event.modifiers & Qt.ControlModifier)
                      if (k === "send") { root.sendFeedback(feedbackInput); event.accepted = true }
                      else if (k === "newline") { feedbackInput.insert(feedbackInput.cursorPosition, "\n"); event.accepted = true }
                      else if (event.key === Qt.Key_Escape) { if (root.settingsKeysRef) root.settingsKeysRef.forceActiveFocus(); event.accepted = true }
                    }

                    Text {
                      anchors.fill: parent
                      visible: feedbackInput.text === "" && !feedbackInput.activeFocus
                      text: "Idea, bug or wish…"
                      color: root.dimText
                      font: feedbackInput.font
                      wrapMode: Text.Wrap
                    }
                  }
                }

                Rectangle {
                  objectName: "feedbackSend"
                  width: parent.width
                  height: root.rowHeight
                  radius: root.cornerRadius
                  color: feedbackSendMouse.containsMouse ? Util.alpha(root.foreground, 0.08) : "transparent"

                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰆈  Send feedback"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: "Enter sends · Shift+Enter: new line"
                    color: root.dimText
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    visible: parent.width > Style.space(420)
                  }
                  MouseArea {
                    id: feedbackSendMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sendFeedback(feedbackInput)
                  }
                }

                // 1.30.0: the result on its own line under Send, wrapping,
                // so it fits at any window width (was cut off on the right).
                Row {
                  objectName: "feedbackNoteRow"
                  visible: root.feedbackNote !== ""
                  x: Style.space(10)
                  width: parent.width - Style.space(20)
                  spacing: Style.space(6)
                  topPadding: Style.space(2)
                  Text {
                    id: feedbackSentIcon
                    objectName: "feedbackSentIcon"
                    visible: root.feedbackSent
                    textFormat: Text.PlainText
                    text: "󰄬"
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    objectName: "feedbackNote"
                    width: parent.width - (feedbackSentIcon.visible ? feedbackSentIcon.width + parent.spacing : 0)
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: root.feedbackNote
                    color: root.feedbackSent ? root.foreground : root.dimText
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                }
            }
          }

          // Clickable settings row (incognito, clear history): icon + label,
          // shortcut hint right, stock hover/cursor fill.
          Component {
            id: infoActionRow
            Rectangle {
              required property var modelData
              required property int index
              width: parent ? parent.width : 0
              height: root.rowHeight
              radius: root.cornerRadius
              color: infoRowMouse.containsMouse ? Util.alpha(root.foreground, 0.08) : "transparent"

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: parent.modelData.label
                color: parent.modelData.key === "incognito" && root.privateMode ? root.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Row {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: parent.parent.modelData.hint
                  color: root.dimText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Rectangle {
                  visible: parent.parent.modelData.key === "incognito"
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.round(Style.font.body * 2.2)
                  height: Math.round(Style.font.body * 1.2)
                  radius: height / 2
                  color: root.privateMode ? root.accent : Util.alpha(root.foreground, 0.22)

                  Rectangle {
                    width: parent.height - Style.space(4)
                    height: width
                    radius: width / 2
                    y: Style.space(2)
                    x: root.privateMode ? parent.width - width - Style.space(2) : Style.space(2)
                    color: root.privateMode ? root.background : root.foreground
                    Behavior on x { NumberAnimation { duration: 120 } }
                  }
                }
              }

              MouseArea {
                id: infoRowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.runSettingsAction(parent.modelData.key)
              }
            }
          }
          // Read-only settings row, styled like a list row (icon + label, value right).
          Component {
            id: infoValueRow
            Item {
              required property var modelData
              width: parent ? parent.width : 0
              height: root.rowHeight

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.right: valueText.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: parent.modelData.icon + "  " + parent.modelData.label
                color: root.foreground
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                id: valueText
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: parent.modelData.value
                color: root.dimText
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          Item {
            anchors.fill: parent

            Item {
              width: parent.width
              height: parent.height
              clip: true

              // "Top" button (like Telegram): shows once scrolled down a bit,
              // stock control fill/border, scrolls smoothly back to the top.
              BorderSurface {
                id: topButton
                z: 3
                readonly property bool hot: topMouse.containsMouse
                visible: opacity > 0
                opacity: resultList.contentY - resultList.originY > root.rowHeight * 4 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(8)
                width: topLabel.implicitWidth + Style.spacing.controlPaddingX * 2
                height: topLabel.implicitHeight + Style.spacing.controlPaddingY * 2
                radius: Style.cornerRadius
                color: Qt.tint(Color.popups.background, Style.controlFill(false, hot, root.foreground, root.accent))
                borderSpec: Border.controlSpec(hot ? "hover" : "normal", root.foreground, root.accent)

                Text {
                  id: topLabel
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: "󰁝  Top"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  id: topMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    resultList.cancelFlick()
                    toTopAnim.from = resultList.contentY
                    toTopAnim.to = resultList.originY
                    toTopAnim.restart()
                  }
                }
              }

              NumberAnimation {
                id: toTopAnim
                target: resultList
                property: "contentY"
                duration: 300
                easing.type: Easing.OutCubic
              }

              ListView {
                id: resultList
                objectName: "resultList"
                anchors.fill: parent
                model: displayModel
                clip: true
                spacing: Style.space(4)
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: 2500
                maximumFlickVelocity: 6000

                KineticScroll {
                  flickable: resultList
                  wheelStep: root.rowHeight * 3
                }

                // 1.28.0: first-run hint above the list: a missing OCR
                // language matching the locale / keyboard layout. Install
                // or Not now (Not now = the same dismissal as in settings).
                header: Column {
                  objectName: "clipListHeader"
                  width: ListView.view ? ListView.view.width : 0

                // 1.30.0: "New update available" (only with the update check on).
                Item {
                  id: updateNotice
                  objectName: "updateNotice"
                  readonly property bool show: root.updateAvailable && root.filterText === ""
                  width: parent.width
                  height: show ? updateBox.height + Style.space(8) : 0
                  visible: show
                  Rectangle {
                    id: updateBox
                    width: parent.width
                    height: updateCol.implicitHeight + Style.space(16)
                    radius: root.cornerRadius
                    color: Util.alpha(root.accent, 0.10)
                    border.width: 1
                    border.color: Util.alpha(root.accent, 0.35)
                    Column {
                      id: updateCol
                      x: Style.space(10)
                      y: Style.space(8)
                      width: parent.width - Style.space(20)
                      spacing: Style.space(4)
                      Text {
                        objectName: "updateNoticeText"
                        width: parent.width
                        wrapMode: Text.WordWrap
                        textFormat: Text.PlainText
                        text: "󰚰  New update available: Nice Clipboard " + root.updateLatest + " (you have " + root.pluginVersion + ")"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                      }
                      Text {
                        objectName: "updateNoticeHow"
                        width: parent.width
                        wrapMode: Text.WordWrap
                        textFormat: Text.PlainText
                        text: ClipboardHistory.updateHowTo(root.updateGit)
                        color: root.dimText
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                      Row {
                        spacing: Style.spacing.xs
                        topPadding: Style.space(4)
                        Button {
                          objectName: "updateNoticeOpen"
                          text: "GitHub page"
                          iconText: "󰊤"
                          fontSize: Style.font.caption
                          iconSize: Style.font.caption
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          horizontalPadding: Style.spacing.sm
                          verticalPadding: Style.spacing.controlPaddingY
                          bordered: true
                          onClicked: root.openUrl(root.repoUrl)
                        }
                        Button {
                          objectName: "updateNoticeDismiss"
                          text: "Hide"
                          iconText: "󰅖"
                          fontSize: Style.font.caption
                          iconSize: Style.font.caption
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          horizontalPadding: Style.spacing.sm
                          verticalPadding: Style.spacing.controlPaddingY
                          bordered: true
                          tooltipText: "Hide until the next version"
                          onClicked: { root.updateDismissed = root.updateLatest; root.writeState() }
                        }
                      }
                    }
                  }
                }

                Item {
                  id: ocrBanner
                  objectName: "ocrBanner"
                  readonly property var sug: root.ocrSuggest.length && root.filterText === "" ? root.ocrSuggest[0] : null
                  width: parent.width
                  height: sug ? bannerBox.height + Style.space(8) : 0
                  visible: sug !== null
                  Rectangle {
                    id: bannerBox
                    width: parent.width
                    height: bannerCol.implicitHeight + Style.space(16)
                    radius: root.cornerRadius
                    color: Util.alpha(root.accent, 0.10)
                    border.width: 1
                    border.color: Util.alpha(root.accent, 0.35)
                    Column {
                      id: bannerCol
                      x: Style.space(10)
                      y: Style.space(8)
                      width: parent.width - Style.space(20)
                      spacing: Style.space(8)
                      Text {
                        objectName: "ocrBannerText"
                        width: parent.width
                        wrapMode: Text.WordWrap
                        textFormat: Text.PlainText
                        text: ocrBanner.sug ? "󰗊  Based on " + ocrBanner.sug.source + ": install text recognition (OCR) for " + ocrBanner.sug.name + "?" : ""
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                      }
                      Row {
                        spacing: Style.spacing.xs
                        Button {
                          objectName: "ocrBannerInstall"
                          text: "Install"
                          iconText: "󰇚"
                          fontSize: Style.font.caption
                          iconSize: Style.font.caption
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          horizontalPadding: Style.spacing.sm
                          verticalPadding: Style.spacing.controlPaddingY
                          bordered: true
                          active: true
                          tooltipText: ocrBanner.sug ? "Opens a terminal: sudo pacman -S --needed tesseract-data-" + ocrBanner.sug.code : ""
                          onClicked: if (ocrBanner.sug) root.installOcrLanguage({ code: ocrBanner.sug.code, name: ocrBanner.sug.name, installed: false })
                        }
                        Button {
                          objectName: "ocrBannerDismiss"
                          text: "Not now"
                          iconText: "󰅖"
                          fontSize: Style.font.caption
                          iconSize: Style.font.caption
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          horizontalPadding: Style.spacing.sm
                          verticalPadding: Style.spacing.controlPaddingY
                          bordered: true
                          tooltipText: "Don't suggest it again (Settings > Text recognition still lists it)"
                          onClicked: if (ocrBanner.sug) root.dismissOcrSuggestion(ocrBanner.sug.code)
                        }
                      }
                    }
                  }
                }
                }

                section.property: "sectionName"
                section.criteria: ViewSection.FullString
                section.delegate: Item {
                  required property string section
                  width: ListView.view.width
                  height: section ? Style.font.caption + Style.space(12) : 0
                  // Thin stock separator above the first heading after Pinned.
                  PanelSeparator {
                    objectName: "clipSep"
                    visible: parent.section !== "" && parent.section === root.firstHistorySection
                    anchors.top: parent.top
                    anchors.topMargin: Style.space(2)
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(10)
                    foreground: root.foreground
                  }
                  Text {
                    visible: parent.section !== ""
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(12)
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Style.space(3)
                    objectName: "clipSectionHeading"
                    text: parent.section.toUpperCase()
                    color: root.dimText
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1.2
                  }
                }

                // Stock row surface (network panel): CursorSurface, hover fill
                  // + hover-cursor border on the cursor row, 60 ms colour fade.
                delegate: CursorSurface {
                  id: row
                  required property int index
                  required property string entryType
                  required property string previewText
                  required property string fullText
                  required property string previewImage
                  required property bool pinned
                  required property int slot
                  required property bool fromPhone
                  required property int historyIndex
                  required property string linkKind
                  required property string linkTarget
                  required property string linkLabel
                  required property string copyText
                  required property string copyTip
                  required property bool copyWifi
                  required property string ocrText
                  required property string ocrTip
                  required property string clipKey
                  // 1.19.0: this entry is what is on the clipboard right now.
                  readonly property bool onClipboard: clipKey !== "" && clipKey === root.currentClipKey
                  required property string path
                  required property bool hasMarkdown
                  readonly property var queueInfo: root.queueBadge(row, root.queueKeys, root.queueRunning, root.runningKeys, root.history)
                  readonly property int queueNo: queueInfo.n

                  readonly property bool hasCursor: root.cursorActive && (root.dragRow >= 0 && root.dragHistoryIndex >= 0 ? historyIndex === root.dragHistoryIndex : index === root.selectedIndex)
                  readonly property bool armed: root.armedDeleteIndex !== -1 && historyIndex === root.armedDeleteIndex
                  readonly property bool showActions: hasCursor || rowMouse.containsMouse

                  width: ListView.view.width
                  height: root.rowHeight
                  objectName: "clipRow"
                  foreground: root.foreground
                  accent: root.accent
                  color: hasCursor ? fill : "transparent"

                  // On the clipboard now: a small accent bar at the left edge.
                  Rectangle {
                    objectName: "clipCurrentMark"
                    visible: row.onClipboard
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(3)
                    height: parent.height - Style.space(10)
                    radius: width / 2
                    color: root.accent
                  }

                  MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.dragRow === row.index && root.dragMoved ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                    // Pinned rows: the press belongs to the row (drag = reorder),
                    // so the ListView must not turn it into a scroll.
                    preventStealing: root.filterText === ""
                    property real pressY: 0
                    onPressed: function(mouse) {
                      dropped = false
                      if (root.filterText !== "" || (mouse.modifiers & Qt.ControlModifier)) return
                      pressY = mouse.y
                      root.dragStart(row.index)
                      resultList.interactive = false
                    }
                    onPositionChanged: function(mouse) {
                      if (pressed && root.dragRow === row.index) {
                        if (!root.dragMoved && Math.abs(mouse.y - pressY) < Qt.styleHints.startDragDistance) return
                        var p = rowMouse.mapToItem(resultList.contentItem, mouse.x, mouse.y)
                        var t = resultList.indexAt(Style.space(10), p.y)
                        if (t < 0) {
                          // In the gap between two rows: stay put (1.15.1 sent the
                          // row to the top/bottom for a frame = the flicker).
                          if (resultList.indexAt(Style.space(10), p.y - resultList.spacing - 1) >= 0) return
                          // Over a section heading (e.g. "History" under
                          // Pinned): count as the row above it, so crossing
                          // the heading moves one step, never to the end.
                          var above = -1
                          for (var dy = 4; dy <= root.rowHeight * 2 && above < 0; dy += 4) above = resultList.indexAt(Style.space(10), p.y - dy)
                          t = above >= 0 ? above : (p.y < resultList.contentItem.mapFromItem(row, 0, 0).y ? 0 : displayModel.count - 1)
                        }
                        if (!root.dragMoved) { root.dragMoved = true; root.cursorActive = true; root.selectedIndex = row.index }
                        root.dragMoveTo(t)
                        return
                      }
                      root.selectFromPointer(row.index, row, mouse)
                    }
                    property bool dropped: false
                    onReleased: {
                      resultList.interactive = true
                      dropped = root.dragMoved
                      if (root.dragMoved) root.dragFinish()
                      else { root.dragRow = -1; root.dragHistoryIndex = -1 }
                    }
                    onCanceled: {
                      resultList.interactive = true
                      root.dragFinish()
                    }
                    onClicked: function(mouse) {
                      // A drop is not a click (1.15.1 pasted the row and closed the popup).
                      if (root.dragMoved || dropped) { dropped = false; return }
                      root.cursorActive = true
                      root.selectedIndex = row.index
                      // Ctrl+click: add to / take out of the paste queue.
                      if (mouse.modifiers & Qt.ControlModifier) { root.toggleQueueIndex(row.index); return }
                      root.clickIndex(row.index)
                    }
                  }

                  Row {
                    id: rowContent
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(10)
                    anchors.topMargin: Style.space(2)
                    anchors.bottomMargin: Style.space(2)
                    spacing: Style.space(10)

                    Image {
                      visible: row.previewImage.length > 0
                      width: visible ? parent.height : 0
                      height: parent.height
                      source: row.previewImage
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      smooth: true
                    }

                    // Cut-off text scrolls right to left on hover and on the
                    // keyboard-highlighted row (timon.media's marquee).
                    MarqueeLabel {
                      objectName: "clipRowText"
                      width: parent.width - actions.width - parent.spacing - (row.previewImage.length > 0 ? parent.height + parent.spacing : 0)
                      height: parent.height
                      text: row.previewText
                      color: root.foreground
                      fontFamily: root.fontFamily
                      pixelSize: Style.font.body
                      running: !root.dragMoved && (rowMouse.containsMouse || row.hasCursor)
                      opacity: row.entryType === "image" || row.entryType === "file" ? 0.72 : 1.0
                    }

                    // Pin + delete buttons (on hover/cursor), shortcut hint otherwise.
                    Row {
                      id: actions
                      height: parent.height
                      spacing: Style.space(2)

                      // "From phone" label (Flux), on text that arrived from the phone.
                      Item {
                        visible: row.fromPhone
                        width: visible ? phoneLabel.implicitWidth + Style.space(8) : 0
                        height: actions.height

                        Text {
                          id: phoneLabel
                          anchors.left: parent.left
                          anchors.verticalCenter: parent.verticalCenter
                          textFormat: Text.PlainText
                          text: "From phone"
                          color: root.dimText
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }
                      }

                      // Detected-type buttons (link/colour) sit left of the
                      // Alt+N hint; send/delete/pin stay right of it.
                      Repeater {
                        model: [
                          { glyph: row.linkKind === "mail" ? "󰇮" : row.linkKind === "phone" ? "󰏲" : row.linkKind === "path" ? "󰉋" : row.linkKind === "maps" ? "󰍎" : row.linkKind === "github" ? "󰊤" : "󰏌",
                            tip: "link", show: row.showActions && row.linkKind !== "" && row.linkKind !== "color",
                            text: ClipboardHistory.targetTooltip(row.linkKind, row.linkLabel) },
                          { glyph: "", tip: "link", swatch: true, show: row.linkKind === "color", text: ClipboardHistory.targetTooltip("color", row.linkLabel) },
                          { glyph: row.copyWifi ? "󰌾" : "󰆏", tip: "copytext", show: row.showActions && row.copyText !== "", text: row.copyTip },
                          { glyph: "󰆏", tip: "ocrtext", show: row.showActions && row.ocrText !== "", text: row.ocrTip },
                          { glyph: "\uf48a", tip: "markdown", show: row.showActions && row.hasMarkdown, text: "Paste as Markdown" },
                          { glyph: "󰦨", tip: "plaintext", show: row.showActions && row.hasMarkdown, text: "Paste as plain text" }
                        ]
                        delegate: actionDelegate
                      }

                      // Paste queue position (1, 2, 3 …), accent badge.
                      Item {
                        objectName: "clipQueueBadge"
                        visible: row.queueNo > 0
                        width: visible ? queueBadge.width + Style.space(6) : 0
                        height: actions.height

                        Rectangle {
                          id: queueBadge
                          anchors.verticalCenter: parent.verticalCenter
                          width: Math.max(height, queueNoText.implicitWidth + Style.space(8))
                          height: Math.round(Style.font.body * 1.5)
                          radius: height / 2
                          color: root.accent
                          opacity: row.queueInfo.done ? 0.4 : 1

                          Text {
                            id: queueNoText
                            objectName: "clipQueueNumber"
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: String(row.queueNo)
                            color: root.background
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                          }
                        }
                      }

                      Item {
                        readonly property string hint: ClipboardHistory.slotHint(root.history, row.historyIndex)
                        visible: !row.showActions && row.queueNo === 0 && hint !== ""
                        width: visible ? slotHint.implicitWidth + Style.space(6) : 0
                        height: actions.height

                        Text {
                          id: slotHint
                          objectName: "clipSlotHint"
                          anchors.left: parent.left
                          anchors.verticalCenter: parent.verticalCenter
                          text: parent.hint
                          color: Qt.darker(root.foreground, 1.5)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body
                        }
                      }

                      Repeater {
                        model: [
                          { glyph: "󰄜", tip: "send", show: row.showActions && root.phoneOnline && row.entryType === "text", text: "Send via Flux" },
                          { glyph: row.armed ? "󰄬" : "󰩺", tip: "delete", show: row.showActions || row.armed, text: row.armed ? "Click again to delete" : "Delete" },
                          { glyph: row.pinned ? "󰐃" : "󰤱", tip: "pin", show: (row.showActions || row.pinned), text: row.pinned ? "Unpin" : "Pin" }
                        ]
                        delegate: actionDelegate
                      }

                      Component {
                        id: actionDelegate

                        Item {
                          id: actionSlot
                          required property var modelData
                          visible: modelData.show
                          width: visible ? actionButton.size : 0
                          height: actions.height
                          readonly property bool keyFocused: row.hasCursor && root.focusedAction === modelData.tip

                          // Stock icon button: hover fill/border and stock tooltip.
                          // 1.31.0: an armed delete is a red button with
                          // Omarchy's check icon; a second click deletes.
                          Rectangle {
                            objectName: "clipDeleteArmed"
                            visible: actionSlot.modelData.tip === "delete" && row.armed
                            anchors.centerIn: actionButton
                            width: actionButton.width
                            height: actionButton.height
                            radius: actionButton.radius
                            color: root.urgent
                          }
                          PanelActionButton {
                            id: actionButton
                            objectName: "clipAction"
                            visible: !actionSlot.modelData.swatch
                            anchors.verticalCenter: parent.verticalCenter
                            iconText: actionSlot.modelData.glyph
                            tooltipText: actionSlot.modelData.text
                            fontFamily: root.fontFamily
                            fontSize: Style.font.subtitle
                            readonly property bool armedDelete: actionSlot.modelData.tip === "delete" && row.armed
                            foreground: armedDelete ? "#ffffff" : (actionSlot.modelData.tip === "pin" && row.pinned ? root.accent : root.foreground)
                            hoverColor: armedDelete ? "#ffffff" : root.foreground
                            // Leaving the armed button disarms it.
                            onHovered: function(isHovered) { if (!isHovered && armedDelete) root.disarmDelete() }
                            hasCursor: actionSlot.keyFocused
                            bordered: actionSlot.keyFocused
                            onClicked: root.runRowAction(actionSlot.modelData.tip, row.index, true)
                          }

                          // Colour code: the button is the colour (stock-sized
                          // rounded square, contrast border); click copies it.
                          BorderSurface {
                            objectName: "clipSwatch"
                            visible: actionSlot.modelData.swatch === true
                            anchors.centerIn: parent
                            width: actionButton.size - Style.space(6)
                            height: width
                            radius: Style.cornerRadius
                            color: row.linkKind === "color" ? row.linkTarget : "transparent"
                            borderSpec: Border.controlSpec(actionSlot.keyFocused || swatchMouse.containsMouse ? "hover-cursor" : "normal", root.foreground, root.accent)

                            MouseArea {
                              id: swatchMouse
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: root.runRowAction("link", row.index)
                            }

                            PanelToolTip {
                              visible: swatchMouse.containsMouse
                              text: actionSlot.modelData.text
                              fontFamily: root.fontFamily
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

          }

          Column {
            anchors.centerIn: parent
            // Explicit width: the texts use parent.width, so without it the
            // column had width 0 and "No matches" never showed.
            width: parent.width - Style.space(24)
            spacing: Style.space(8)
            visible: displayModel.count === 0

            Text {
              text: root.privateMode && root.history.length === 0 ? "󰗹" : "󰅌"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.history.length === 0 ? "Copy something to start" : "No matches"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }
          }
        }

        // Footer, one row: Clear history left; Incognito switch and gear right.
        Item {
          id: footer
          width: parent.width
          implicitHeight: root.footerRowHeight + root.footerGap
          height: implicitHeight

          Item {
            y: root.footerGap
            width: parent.width
            height: root.footerRowHeight

              // Paste queue: replaces Clear history while rows are queued
              // ("Paste 3 in order") or a queue is armed ("Pasting 2 of 5 · Cancel").
              Rectangle {
                id: queueButton
                objectName: "clipQueueButton"
                readonly property string label: ClipboardHistory.queueButtonLabel(root.queueKeys.length, root.queueRunning)
                // 2+ selected: a plain info line (not a button); a running
                // queue: the Cancel button.
                readonly property bool info: root.queueKeys.length >= 2
                visible: label !== ""
                anchors.left: parent.left
                width: Math.min(queueLabel.implicitWidth + Style.space(16), Math.max(0, incognitoSwitch.x - Style.space(8)))
                // 1.21.0: the info line is a pill in the queue badges' accent.
                height: info ? Math.round(Style.font.body * 1.6) : root.footerRowHeight
                anchors.verticalCenter: parent.verticalCenter
                radius: info ? height / 2 : root.cornerRadius
                color: info ? root.accent : (queueMouse.containsMouse ? Util.alpha(root.accent, 0.28) : Util.alpha(root.accent, 0.16))

                Text {
                  id: queueLabel
                  objectName: "clipQueueLabel"
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: queueButton.label
                  width: Math.min(implicitWidth, queueButton.width - Style.space(16))
                  elide: Text.ElideRight
                  color: queueButton.info ? root.background : root.foreground
                  font.bold: queueButton.info
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  id: queueMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: !queueButton.info
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.queueButtonClicked()
                }

                PanelToolTip {
                  visible: queueMouse.containsMouse
                  text: "Stop the paste queue"
                }
              }

              Rectangle {
                visible: !queueButton.visible
                anchors.left: parent.left
                width: clearLabel.implicitWidth + Style.space(16)
                height: root.footerRowHeight
                radius: root.cornerRadius
                color: clearMouse.containsMouse ? Util.alpha(root.foreground, 0.10) : Util.alpha(root.foreground, 0.04)

                Text {
                  id: clearLabel
                  anchors.centerIn: parent
                  // "Clear history (162 items)" when it fits next to the
                  // incognito/phone/gear buttons with room to spare, else
                  // "Clear history (162)"; see ClipboardHistory.clearLabel.
                  text: ClipboardHistory.clearLabel(root.unpinnedCount, clearLongMetrics.advanceWidth,
                    Math.max(0, (phoneButton.visible ? phoneButton.x : gearButton.x) - incognitoSwitch.width - Style.space(8) - Style.space(16)),
                    Style.space(24))
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                TextMetrics {
                  id: clearLongMetrics
                  font: clearLabel.font
                  text: ClipboardHistory.clearLabelText(root.unpinnedCount, true)
                }

                MouseArea {
                  id: clearMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.requestClearHistory()
                }
              }

              // Incognito on/off switch (also Ctrl+I, or right-click the bar icon).
              Rectangle {
                id: incognitoSwitch
                anchors.right: phoneButton.visible ? phoneButton.left : gearButton.left
                anchors.rightMargin: Style.space(8)
                width: incognitoRow.implicitWidth + Style.space(16)
                height: root.footerRowHeight
                radius: root.cornerRadius
                color: incognitoMouse.containsMouse ? Util.alpha(root.foreground, 0.10)
                  : (root.privateMode ? Util.alpha(root.accent, 0.16) : Util.alpha(root.foreground, 0.04))

                Row {
                  id: incognitoRow
                  anchors.centerIn: parent
                  spacing: Style.space(8)

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: "󰗹"
                    color: root.privateMode ? root.accent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(Style.font.body * 2.2)
                    height: Math.round(Style.font.body * 1.2)
                    radius: height / 2
                    color: root.privateMode ? root.accent : Util.alpha(root.foreground, 0.22)

                    Rectangle {
                      width: track.height - Style.space(4)
                      height: width
                      radius: width / 2
                      y: Style.space(2)
                      x: root.privateMode ? track.width - width - Style.space(2) : Style.space(2)
                      color: root.privateMode ? root.background : root.foreground
                      Behavior on x { NumberAnimation { duration: 120 } }
                    }
                  }

                }

                MouseArea {
                  id: incognitoMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setPrivate(!root.privateMode, false)
                }
              }

            // Flux phone button: state as icon + tooltip; click opens Flux.
            Rectangle {
              id: phoneButton
              visible: root.phoneIcon !== ""
              anchors.right: gearButton.left
              anchors.rightMargin: Style.space(8)
              anchors.top: parent.top
              width: root.footerRowHeight
              height: root.footerRowHeight
              radius: root.cornerRadius
              color: phoneMouse.containsMouse ? Util.alpha(root.foreground, 0.10) : Util.alpha(root.foreground, 0.04)

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                // 1.26.0: connected = phone with a check (nf-md-cellphone_check),
                // else the crossed-out phone; colour as before.
                objectName: "phoneGlyph"
                text: ClipboardHistory.phoneGlyph(root.phoneIcon)
                color: root.phoneIcon === "paused" ? root.accent
                  : (root.phoneIcon === "online" ? root.foreground : root.dimText)
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }

              MouseArea {
                id: phoneMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openFlux()
              }

              PanelToolTip {
                visible: phoneMouse.containsMouse
                text: ClipboardHistory.phoneTooltip(root.phoneIcon, root.phoneName)
              }
            }

            // Settings (opens the settings window).
            Rectangle {
              id: gearButton
              anchors.right: parent.right
              anchors.top: parent.top
              width: root.footerRowHeight
              height: root.footerRowHeight
              radius: root.cornerRadius
              color: gearMouse.containsMouse ? Util.alpha(root.foreground, 0.10) : Util.alpha(root.foreground, 0.04)

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "󰒓"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }

              MouseArea {
                id: gearMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openSettingsWindow()
              }

              PanelToolTip {
                visible: gearMouse.containsMouse
                text: "Settings"
              }
            }
          }
        }
      }
    }
  }

  // Settings window (1.28.0 redesign): about 900 x 650, laid out like a
  // settings app: a sidebar of sections on the left (title + version on
  // top), one section at a time in the content pane on the right, with its
  // title, a one-line description and the stock divider. The sections are
  // the same Components the popup page uses (their own small headings are
  // hidden here). ↑ ↓ / Tab pick a section, PgUp/PgDn scroll, Esc closes.
  // Tiles like Flux's window (xdg toplevel, class org.quickshell).
  readonly property var settingsWindowRef: settingsWindowLoader.item
  property var settingsKeysRef: null
  property var settingsPaneFlickRef: null
  property int settingsSection: 0
  readonly property var settingsSections: [
    { key: "general", icon: "󰒓", label: "General", desc: "Incognito and what a click on an item does.", comp: secGeneral },
    { key: "history", icon: "󰋚", label: "History", desc: "How long items are kept, and clearing the history. Pinned items always stay.", comp: secHistory },
    { key: "flux", icon: "󰄜", label: "Flux (phone)", desc: "Clipboard sync with your phone through Flux.", comp: secFlux },
    { key: "ocr", icon: "󰗊", label: "Text recognition (OCR)", title: "Languages for text recognition (OCR)", desc: "Languages used to read text in screenshots and images: switch them on or off, remove them, or add new ones.", comp: secOcr },
    { key: "filters", icon: "󰍉", label: "Search filters", desc: "Type these in the search field; combine them with text, e.g. type:link github.", comp: secFilters },
    { key: "shortcuts", icon: "󰌌", label: "Shortcuts", desc: "Keys in the popup and everywhere.", comp: secShortcuts },
    { key: "feedback", icon: "󰆈", label: "Feedback", desc: "Send feedback straight to the developer from here, or check out the <a href=\"https://github.com/roehrbacher/Nice-Clipboard\">GitHub page</a>.", comp: secFeedback },
    { key: "uninstall", icon: "󰆴", label: "Uninstall", desc: "Remove Nice Clipboard from this computer. A terminal shows every command before anything runs.", comp: secUninstall }
  ]
  function showSettingsSection(i) {
    var n = root.settingsSections.length
    root.settingsSection = ((i % n) + n) % n
    if (root.settingsPaneFlickRef) root.settingsPaneFlickRef.contentY = 0
  }
  LazyLoader {
    id: settingsWindowLoader
    active: false
  FloatingWindow {
    id: settingsWindow
    objectName: "settingsWindow"
    visible: true
    title: "Nice Clipboard settings"
    // Super+W (killactive) / the compositor closing it: drop it, so the
    // next open makes a new one. Esc does the same.
    onClosed: Qt.callLater(root.closeSettingsWindow)
    onVisibleChanged: if (!visible) Qt.callLater(root.closeSettingsWindow)
    implicitWidth: 900
    implicitHeight: 650
    color: root.background

    Item {
      id: settingsKeys
      objectName: "settingsWindowContent"
      anchors.fill: parent
      focus: true
      Component.onCompleted: { root.settingsKeysRef = settingsKeys; root.settingsPaneFlickRef = settingsPaneFlick }
      Keys.onPressed: function(event) {
        var k = event.key
        if (k === Qt.Key_Escape) Qt.callLater(root.closeSettingsWindow)
        else if (k === Qt.Key_Down || k === Qt.Key_Tab) root.showSettingsSection(root.settingsSection + 1)
        else if (k === Qt.Key_Up || k === Qt.Key_Backtab) root.showSettingsSection(root.settingsSection - 1)
        else if (k === Qt.Key_PageDown) settingsPaneFlick.contentY = Math.min(Math.max(0, settingsPaneFlick.contentHeight - settingsPaneFlick.height), settingsPaneFlick.contentY + settingsPaneFlick.height * 0.85)
        else if (k === Qt.Key_PageUp) settingsPaneFlick.contentY = Math.max(0, settingsPaneFlick.contentY - settingsPaneFlick.height * 0.85)
        else if ((event.modifiers & Qt.ControlModifier) && k === Qt.Key_S) root.sendCurrentClipboard()
        else return
        event.accepted = true
      }

      // ---- sidebar ----
      Rectangle {
        id: settingsSidebar
        objectName: "settingsSidebar"
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Style.space(230)
        color: Util.alpha(root.foreground, 0.04)

        Column {
          id: sidebarHead
          x: Style.spacing.panelPadding
          y: Style.spacing.panelPadding
          width: parent.width - 2 * Style.spacing.panelPadding
          spacing: Style.space(2)
          Row {
            spacing: Style.space(8)
            Text {
              objectName: "settingsWindowTitle"
              textFormat: Text.PlainText
              text: "Settings"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              objectName: "settingsWindowVersion"
              anchors.baseline: parent.children[0].baseline
              textFormat: Text.PlainText
              text: root.pluginVersion
              color: root.dimText
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          Text {
            textFormat: Text.PlainText
            text: "Nice Clipboard"
            color: root.dimText
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Column {
          id: sidebarNav
          objectName: "settingsNav"
          anchors.top: sidebarHead.bottom
          anchors.topMargin: Style.space(18)
          x: Style.space(8)
          width: parent.width - Style.space(16)
          spacing: Style.space(2)
          Repeater {
            model: root.settingsSections
            Rectangle {
              required property var modelData
              required property int index
              objectName: "settingsNavItem"
              readonly property bool current: root.settingsSection === index
              width: sidebarNav.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: current ? root.selectedBackground : (navMouse.containsMouse ? Util.alpha(root.foreground, 0.06) : "transparent")
              Rectangle {
                visible: parent.current
                width: Style.space(3)
                height: parent.height - Style.space(14)
                radius: width / 2
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                color: root.accent
              }
              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: modelData.icon + "   " + modelData.label
                color: parent.current ? root.foreground : Util.alpha(root.foreground, 0.8)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: parent.current
                elide: Text.ElideRight
              }
              MouseArea {
                id: navMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.showSettingsSection(index); settingsKeys.forceActiveFocus() }
              }
            }
          }
        }

        // 1.30.0: the project page, at the bottom of the sidebar.
        Rectangle {
          id: sidebarGithub
          objectName: "settingsGithubLink"
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.bottom: sidebarHint.top
          anchors.bottomMargin: Style.space(8)
          height: root.rowHeight
          radius: root.cornerRadius
          color: githubMouse.containsMouse ? Util.alpha(root.foreground, 0.08) : "transparent"
          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "󰊤   GitHub"
            color: Util.alpha(root.foreground, 0.8)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          MouseArea {
            id: githubMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openUrl(root.repoUrl)
          }
        }
        Text {
          id: sidebarHint
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.panelPadding
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.panelPadding
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.spacing.panelPadding
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: "↑ ↓ sections · Esc closes"
          color: root.dimText
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      Rectangle {
        anchors.left: settingsSidebar.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: Util.alpha(root.foreground, 0.12)
      }

      // ---- content pane ----
      Item {
        id: settingsPane
        objectName: "settingsPane"
        anchors.left: settingsSidebar.right
        anchors.leftMargin: Style.space(32)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(32)
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        readonly property var section: root.settingsSections[root.settingsSection]

        Column {
          id: paneHead
          y: Style.spacing.panelPadding
          width: parent.width
          spacing: Style.space(6)
          Text {
            objectName: "settingsPaneTitle"
            textFormat: Text.PlainText
            text: settingsPane.section.title || settingsPane.section.label
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Text {
            objectName: "settingsPaneDesc"
            width: parent.width
            wrapMode: Text.WordWrap
            // Descriptions are our own constants; StyledText for the one link.
            textFormat: Text.StyledText
            linkColor: root.accent
            onLinkActivated: function(link) { root.openUrl(link) }
            text: settingsPane.section.desc
            // 1.31.0: like the vanilla shell's window header description
            // (dev gallery): bodySmall, foreground darkened 1.4.
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Item { width: 1; height: Style.space(6) }
          PanelSeparator { width: parent.width; foreground: root.foreground }
        }

        Flickable {
          id: settingsPaneFlick
          objectName: "settingsWindowFlick"
          anchors.top: paneHead.bottom
          anchors.topMargin: Style.space(12)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.spacing.panelPadding
          clip: true
          contentWidth: width
          contentHeight: settingsPaneLoader.height
          boundsBehavior: Flickable.StopAtBounds

          KineticScroll {
            flickable: settingsPaneFlick
            wheelStep: root.rowHeight * 3
          }

          Loader {
            id: settingsPaneLoader
            objectName: "settingsPaneLoader"
            width: settingsPaneFlick.width
            sourceComponent: settingsPane.section.comp
          }
        }
      }
    }
  }
  }
}
