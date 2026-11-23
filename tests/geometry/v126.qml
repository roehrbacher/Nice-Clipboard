import Quickshell
import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui
// 1.26.0 on the real Clipboard.qml (stub helpers): Alt+1 pastes the first
// history row (pins skipped), row hints, clear count with 4 pins + 3 history,
// phone glyph per Flux state, settings in the popup and in the window.
// Saves PNGs to $V126_PNG_DIR (offscreen, software).
ShellRoot {
  id: shell
  property var clip: null
  property var flick: null
  property int shot: 0
  readonly property string pngDir: Quickshell.env("V126_PNG_DIR") || ""
  function find(item, name, out) {
    if (!item) return
    if (item.objectName === name && out.indexOf(item) < 0) out.push(item)
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) find(kids[i], name, out)
    if (item.contentItem && item.contentItem !== item) find(item.contentItem, name, out)
  }
  function texts(item, pre, out) { if (!item) return; if (item.text !== undefined && String(item.text).indexOf(pre) === 0 && item.visible) out.push(item); var k = item.children || []; for (var i = 0; i < k.length; i++) texts(k[i], pre, out); if (item.contentItem && item.contentItem !== item) texts(item.contentItem, pre, out) }
  function all(name) { var o = []; for (var w = 0; w < clip.children.length; w++) find(clip.children[w], name, o); return o }
  function allText(pre) { var o = []; for (var w = 0; w < clip.children.length; w++) texts(clip.children[w], pre, o); return o }
  Window { id: win; width: 462; height: 630; visible: true; color: "black" }
  // The settings window's content is moved here for the PNG: an offscreen
  // Quickshell FloatingWindow does not render, so grabToImage never returns.
  Window { id: win2; width: 900; height: 650; visible: true; color: clip ? clip.background : "black" }
  Component.onCompleted: {
    var c = Qt.createComponent("clip/Clipboard.qml")
    if (c.status !== Component.Ready) { console.log("V126 ERR " + c.errorString()); Qt.quit(); return }
    clip = c.createObject(win.contentItem, {})
    var bg = Quickshell.env("V126_BG") || "#1e1e2e", fg = Quickshell.env("V126_FG") || "#cdd6f4", ac = Quickshell.env("V126_ACCENT") || "#89b4fa"
    clip.background = bg; clip.foreground = fg; clip.accent = ac; clip.border = ac; clip.scrim = "transparent"
    clip.selectedBackground = Qt.rgba(Qt.color(fg).r, Qt.color(fg).g, Qt.color(fg).b, 0.12); clip.selectedText = fg
    clip.open("{}")
    t.start()
  }
  Timer { id: t; interval: 3000; onTriggered: shell.step1() }
  Timer { id: t2; interval: 1500; onTriggered: shell.step2() }
  Timer { id: t3; interval: 1500; onTriggered: shell.step3() }
  Timer { id: tShot; interval: 600; onTriggered: shell.takeShot() }
  Timer { id: tWin; interval: 1500; onTriggered: shell.windowShot() }
  Timer { id: tEnd; interval: 800; onTriggered: { console.log("V126 done"); Qt.quit() } }
  function step1() {
    var now = Date.now()
    clip.history = [
      { type: "text", text: "h1 newest", at: now }, { type: "text", text: "pin one", pinned: true, at: now - 5 },
      { type: "text", text: "pin two", pinned: true, at: now - 6 }, { type: "text", text: "h2", at: now - 1000 },
      { type: "text", text: "pin three", pinned: true, at: now - 7 }, { type: "text", text: "pin four", pinned: true, at: now - 8 },
      { type: "text", text: "h3", at: now - 2000 }
    ]
    clip.fluxPresent = true; clip.fluxState = "on"; clip.phoneOnline = true; clip.phoneName = "Pixel"
    clip.rebuildDisplay(false)
    t2.start()
  }
  function step2() {
    var rows = []; for (var i = 0; i < clip.displayModelCount(); i++) { var r = clip.displayModelGet(i); rows.push(r.previewText + (r.pinned ? "(pin)" : "")) }
    console.log("V126 rows: " + rows.join(", "))
    var hints = all("clipSlotHint").filter(function(x) { return x.visible && x.parent.visible }).map(function(x) { return x.text })
    console.log("V126 hints: " + hints.join(" "))
    var cl = allText("󰩺  Clear history ("); console.log("V126 footer: '" + (cl.length ? cl[0].text : "?") + "' unpinnedCount=" + clip.unpinnedCount)
    var g = all("phoneGlyph")[0]; console.log("V126 phone online glyph U+" + g.text.codePointAt(0).toString(16).toUpperCase())
    clip.phoneOnline = false; console.log("V126 phone no-phone glyph U+" + g.text.codePointAt(0).toString(16).toUpperCase())
    clip.phoneOnline = true
    // Alt+1 then Alt released: the helper must be asked to paste "h1 newest" (history index 0).
    clip.handleSearchKey({ key: Qt.Key_1, modifiers: Qt.AltModifier, text: "1", accepted: false })
    clip.handleSearchKeyRelease({ key: Qt.Key_Alt, modifiers: 0, text: "", accepted: false })
    console.log("V126 after Alt+1: opened=" + clip.opened)
    clip.open("{}")
    clip.handleSearchKey({ key: Qt.Key_3, modifiers: Qt.AltModifier, text: "3", accepted: false })
    clip.handleSearchKeyRelease({ key: Qt.Key_Alt, modifiers: 0, text: "", accepted: false })
    clip.open("{}"); clip.rebuildDisplay(false)
    t3.start()
  }
  function step3() {
    // Popup row list with hints, then the popup settings page.
    win.contentItem.grabToImage(function(r) {
      if (pngDir) r.saveToFile(pngDir + "/popup-list.png")
      clip.openInfo()
      flick = all("infoFlick")[0]
      shot = 0; flick.contentY = 0; tShot.start()
    })
  }
  function takeShot() {
    var n = shot
    win.contentItem.grabToImage(function(r) {
      if (pngDir) r.saveToFile(pngDir + "/popup-settings-" + n + ".png")
      var maxY = Math.max(0, flick.contentHeight - flick.height)
      if (n === 0) { var fp = flick.mapToItem(win.contentItem, 0, 0); console.log("V126 popup settings height " + Math.round(flick.contentHeight) + " view " + Math.round(flick.height) + " at y " + Math.round(fp.y)) }
      console.log("V126 popup shot " + n + " at contentY " + Math.round(flick.contentY))
      if (flick.contentY >= maxY - 1 || shot >= 6) { clip.closeInfo(); clip.openSettingsWindow(); tWin.start(); return }
      shot++
      flick.contentY = Math.min(maxY, flick.contentY + flick.height * 0.85)
      tShot.start()
    })
  }
  function windowShot() {
    var w = clip.settingsWindowRef
    console.log("V126 window visible=" + w.visible + " title='" + w.title + "' size " + w.width + "x" + w.height + " popup opened=" + clip.opened)
    var o = [], k = w.contentItem
    find(k, "settingsLeft", o); find(k, "settingsRight", o)
    var wf = []; find(k, "settingsWindowFlick", wf)
    console.log("V126 window columns: " + o.map(function(c) { return c.objectName + " w" + Math.round(c.width) + " h" + Math.round(c.height) }).join(", ") + " view h" + Math.round(wf[0].height))
    var content = []; find(k, "settingsWindowContent", content)
    win2.color = clip.background
    content[0].parent = win2.contentItem
    content[0].anchors.fill = win2.contentItem
    tWin2.start()
  }
  Timer { id: tWin2; interval: 800; onTriggered: shell.windowShot2() }
  function windowShot2() {
    var w = clip.settingsWindowRef
    win2.contentItem.grabToImage(function(r) {
      if (pngDir) r.saveToFile(pngDir + "/window-settings.png")
      console.log("V126 window shot " + r.image.width + "x" + r.image.height)
      w.visible = false
      tEnd.start()
    })
  }
}
