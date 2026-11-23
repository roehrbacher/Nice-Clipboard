import Quickshell
import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui
// 1.29.0 on the real Clipboard.qml (stub helpers): Alt+Shift slot hints and
// keys, no settings page in the popup, settings window reopens after it was
// closed by the compositor (Super+W), feedback sent state, dev demo banner,
// install launch. PNGs to $HARNESS_PNG_DIR.
ShellRoot {
  id: shell
  property var clip: null
  property var firstWin: null
  readonly property string pngDir: Quickshell.env("HARNESS_PNG_DIR") || ""
  function find(item, name, out) {
    if (!item) return
    if (item.objectName === name && out.indexOf(item) < 0) out.push(item)
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) find(kids[i], name, out)
    if (item.contentItem && item.contentItem !== item) find(item.contentItem, name, out)
  }
  function all(name) { var o = []; for (var w = 0; w < clip.children.length; w++) find(clip.children[w], name, o); return o }
  function vis(name) { return all(name).filter(function(x) { return x.visible }) }
  function inWin(name) { var o = []; find(win2.contentItem, name, o); return o }
  Window { id: win; width: 462; height: 700; visible: true; color: "black" }
  // The settings window's content is moved here for the PNG: an offscreen
  // Quickshell FloatingWindow does not render, so grabToImage never returns.
  Window { id: win2; width: 900; height: 650; visible: true; color: clip ? clip.background : "black" }
  Component.onCompleted: {
    var c = Qt.createComponent("clip/Clipboard.qml")
    if (c.status !== Component.Ready) { console.log("V129 ERR " + c.errorString()); Qt.quit(); return }
    clip = c.createObject(win.contentItem, {})
    var bg = Quickshell.env("HARNESS_BG") || "#1e1e2e", fg = Quickshell.env("HARNESS_FG") || "#cdd6f4", ac = Quickshell.env("HARNESS_ACCENT") || "#89b4fa"
    clip.background = bg; clip.foreground = fg; clip.accent = ac; clip.border = ac; clip.scrim = "transparent"
    clip.selectedBackground = Qt.rgba(Qt.color(fg).r, Qt.color(fg).g, Qt.color(fg).b, 0.12); clip.selectedText = fg
    clip.open("{}")
    t1.start()
  }
  Timer { id: t1; interval: 2500; onTriggered: shell.step1() }
  Timer { id: t2; interval: 1200; onTriggered: shell.step2() }
  Timer { id: t3; interval: 1200; onTriggered: shell.step3() }
  Timer { id: t4; interval: 800; onTriggered: shell.step4() }
  Timer { id: t5; interval: 800; onTriggered: shell.step5() }
  Timer { id: t6; interval: 1500; onTriggered: shell.step6() }
  Timer { id: t7; interval: 2500; onTriggered: shell.step7() }
  Timer { id: tEnd; interval: 800; onTriggered: { console.log("V129 done"); Qt.quit() } }
  function key(code, scan, mods) { var e = { key: code, nativeScanCode: scan, modifiers: mods, text: "", accepted: false }; clip.handleSearchKey(e); return e.accepted }
  function step1() {
    var now = Date.now(), h = []
    // 4 pins among 8 history items: slots p1…p4, then h1…h6 (Alt+Shift+5…9, 0).
    for (var i = 1; i <= 8; i++) {
      h.push({ type: "text", text: "history item " + i, at: now - i * 1000 })
      if (i <= 4) h.push({ type: "text", text: "pin " + i, pinned: true, at: now - i * 1000 - 5 })
    }
    clip.history = h
    clip.rebuildDisplay(false)
    console.log("V129 global keys: on=" + clip.globalKeys + " '" + clip.globalKeysInfo.text + "'")
    console.log("V129 real banner suggestions (XPS-like): " + clip.ocrSuggest.length)
    console.log("V129 demo IPC: " + clip.ocrBannerDemo("x"))
    clip.open("{}")
    t2.start()
  }
  function step2() {
    var b = vis("ocrBannerText")
    console.log("V129 banner: " + (b.length ? "'" + b[0].text + "'" : "none"))
    var rows = vis("clipRow").sort(function(a, b) { return a.index - b.index })
    console.log("V129 row hints: " + rows.map(function(r) { var hh = []; find(r, "clipSlotHint", hh); hh = hh.filter(function(x) { return x.visible && x.parent.visible }); return r.previewText + "=" + (hh.length ? hh[0].text : "-") }).join(" | "))
    console.log("V129 popup settings page gone: infoFlick=" + all("infoFlick").length + " headerVersion=" + all("headerVersion").length)
    win.contentItem.grabToImage(function(r) {
      if (pngDir) r.saveToFile(pngDir + "/popup-slots-demo-banner.png")
      vis("ocrBannerInstall")[0].clicked()
      console.log("V129 after Install: opened=" + clip.opened + " installing=" + clip.ocrInstalling)
      clip.open("{}")
      console.log("V129 plain Alt+1 accepted=" + key(Qt.Key_1, 10, Qt.AltModifier) + " opened=" + clip.opened)
      key(Qt.Key_Exclam, 10, Qt.AltModifier | Qt.ShiftModifier)
      console.log("V129 Alt+Shift+1 (German '!') opened=" + clip.opened)
      clip.open("{}"); clip.setFilter("history item 8")
      key(Qt.Key_Equal, 19, Qt.AltModifier | Qt.ShiftModifier)
      console.log("V129 Alt+Shift+0 while searching: opened=" + clip.opened)
      clip.setFilter("")
      clip.open("{}")
      vis("ocrBannerDismiss").forEach(function(x) { x.clicked() })
      console.log("V129 demo dismissed: banner=" + vis("ocrBannerText").length + " ocrDismissed=" + JSON.stringify(clip.ocrDismissed))
      // The gear opens the window and closes the popup.
      clip.openSettingsWindow()
      t3.start()
    })
  }
  function step3() {
    firstWin = clip.settingsWindowRef
    console.log("V129 window 1 visible=" + (firstWin && firstWin.visible) + " popup opened=" + clip.opened)
    // Super+W: Hyprland closes the window; Quickshell emits closed().
    console.log("V129 closed signal exists=" + (typeof firstWin.closed === "function"))
    firstWin.closed()
    t4.start()
  }
  function step4() {
    console.log("V129 after Super+W: loader item=" + (clip.settingsLoaderItem() ? "still there" : "gone"))
    clip.openSettingsWindow("feedback")
    t5.start()
  }
  function step5() {
    var w = clip.settingsWindowRef
    console.log("V129 reopened: visible=" + (w && w.visible) + " new window=" + (w !== firstWin) + " section=" + clip.settingsSections[clip.settingsSection].key)
    // Hidden by other means (visible=false) works too.
    w.visible = false
    Qt.callLater(function() {
      clip.openSettingsWindow("feedback")
      var w2 = clip.settingsWindowRef
      console.log("V129 reopen after hide: visible=" + (w2 && w2.visible))
      var content = []; find(w2.contentItem, "settingsWindowContent", content)
      content[0].parent = win2.contentItem
      content[0].anchors.fill = win2.contentItem
      var fi = inWin("feedbackInput")[0]
      fi.text = "Hello from the v129 harness"
      console.log("V129 send returned " + clip.sendFeedback(fi) + " note='" + clip.feedbackNote + "'")
      t6.start()
    })
  }
  function step6() {
    var note = inWin("feedbackNote")[0], icon = inWin("feedbackSentIcon")[0]
    console.log("V129 feedback note='" + note.text + "' sent=" + clip.feedbackSent + " check visible=" + icon.visible + " color=" + icon.color + " input='" + inWin("feedbackInput")[0].text + "' truncated=" + note.truncated)
    win2.contentItem.grabToImage(function(r) {
      if (pngDir) r.saveToFile(pngDir + "/window-feedback-sent.png")
      clip.runSettingsAction("globalKeys")
      console.log("V129 global keys toggled: on=" + clip.globalKeys)
      clip.runSettingsAction("globalKeys")
      clip.showSettingsSection(5)
      t7.start()
    })
  }
  function step7() {
    var gs = inWin("settingSwitchStatus")
    console.log("V129 instances in window: paneLoader=" + inWin("settingsPaneLoader").length + " content=" + inWin("settingsWindowContent").length + " feedbackInput=" + inWin("feedbackInput").length)
    console.log("V129 shortcuts status: on=" + clip.globalKeys + " '" + (gs.length ? gs[0].text : "missing") + "'")
    win2.contentItem.grabToImage(function(r) {
      if (pngDir) r.saveToFile(pngDir + "/window-shortcuts.png")
      clip.showSettingsSection(0)
      Qt.callLater(function() { win2.contentItem.grabToImage(function(r2) { if (pngDir) r2.saveToFile(pngDir + "/window-general.png"); tEnd.start() }) })
    })
  }
}
