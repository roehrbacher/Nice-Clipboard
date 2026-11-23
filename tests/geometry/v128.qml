import Quickshell
import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui
import "clip/ClipboardHistory.js" as CH
// 1.28.0 on the real Clipboard.qml (stub helpers): OCR banner, Alt+N = pins,
// version in the header, settings window with sidebar, click-to-install
// through stubs + re-detect, toast-sized OCR preview. PNGs to $V128_PNG_DIR.
ShellRoot {
  id: shell
  property var clip: null
  property var flick: null
  property int shot: 0
  readonly property string pngDir: Quickshell.env("V128_PNG_DIR") || ""
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
  // Toast stand-in with the Omarchy notification body's settings
  // (plugins/notifications/Toast.qml: card 380, Liberation Sans, title size,
  // StyledText, 2 lines, ElideRight).
  Window { id: win3; width: Style.space(400); height: Style.space(140); visible: true; color: "black" }
  Rectangle {
    id: toast
    parent: win3.contentItem
    x: Style.space(10); y: Style.space(10)
    width: Style.space(380); height: toastCol.implicitHeight + Style.space(24)
    radius: Style.space(8)
    color: clip ? clip.background : "#222"
    border.width: 1; border.color: clip ? clip.accent : "#888"
    Text { id: toastGlyph; x: Style.space(12); y: Style.space(12); text: "󰆏"; color: clip ? clip.foreground : "white"; font.pixelSize: Style.space(28) }
    Column {
      id: toastCol
      x: Style.space(12) + Style.space(40) + Style.space(12); y: Style.space(12)
      width: toast.width - x - Style.space(12)
      spacing: Style.space(3)
      Text { id: toastTitle; width: parent.width; text: ""; color: clip ? clip.foreground : "white"; font.family: "Liberation Sans"; font.pixelSize: Style.font.title; font.bold: true; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight }
      Text { id: toastBody; width: parent.width; textFormat: Text.StyledText; text: ""; color: clip ? clip.dimText : "#ccc"; font.family: "Liberation Sans"; font.pixelSize: Style.font.title; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
    }
  }
  Text { id: measure; parent: win3.contentItem; visible: false; width: toastBody.width; textFormat: Text.StyledText; font.family: "Liberation Sans"; font.pixelSize: Style.font.title; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
  readonly property var samples: [
    "Invoice number 2026-11-0042 due on 30 November. Please transfer the amount to the account below and quote the number as reference so we can match your payment.",
    "Sehr geehrte Damen und Herren, vielen Dank für Ihre Anfrage vom 12. November. Anbei finden Sie unser Angebot für die gewünschten Leistungen.",
    "MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM",
    "the quick brown fox jumps over the lazy dog the quick brown fox jumps over the lazy dog the quick brown fox jumps over the lazy dog"
  ]
  Component.onCompleted: {
    var c = Qt.createComponent("clip/Clipboard.qml")
    if (c.status !== Component.Ready) { console.log("V128 ERR " + c.errorString()); Qt.quit(); return }
    clip = c.createObject(win.contentItem, {})
    var bg = Quickshell.env("V128_BG") || "#1e1e2e", fg = Quickshell.env("V128_FG") || "#cdd6f4", ac = Quickshell.env("V128_ACCENT") || "#89b4fa"
    clip.background = bg; clip.foreground = fg; clip.accent = ac; clip.border = ac; clip.scrim = "transparent"
    clip.selectedBackground = Qt.rgba(Qt.color(fg).r, Qt.color(fg).g, Qt.color(fg).b, 0.12); clip.selectedText = fg
    clip.open("{}")
    t1.start()
  }
  Timer { id: t1; interval: 2500; onTriggered: shell.step1() }
  Timer { id: t2; interval: 1200; onTriggered: shell.step2() }
  Timer { id: t3; interval: 1200; onTriggered: shell.step3() }
  Timer { id: tW; interval: 1200; onTriggered: shell.windowShots() }
  Timer { id: tW2; interval: 700; onTriggered: shell.windowShot2() }
  Timer { id: t4; interval: 1000; onTriggered: shell.step4() }
  Timer { id: t5; interval: 4500; onTriggered: shell.step5() }
  Timer { id: tEnd; interval: 800; onTriggered: { console.log("V128 done"); Qt.quit() } }
  function vis(name) { return all(name).filter(function(x) { return x.visible }) }
  function step1() {
    var now = Date.now()
    clip.history = [
      { type: "text", text: "newest history item", at: now }, { type: "text", text: "pin one", pinned: true, at: now - 5 },
      { type: "text", text: "second history item", at: now - 1000 }, { type: "text", text: "pin two", pinned: true, at: now - 6 },
      { type: "text", text: "third history item", at: now - 2000 }
    ]
    clip.rebuildDisplay(false)
    clip.open("{}")
    t2.start()
  }
  function step2() {
    var b = vis("ocrBannerText")
    console.log("V128 banner: " + (b.length ? "'" + b[0].text + "'" : "none"))
    var hints = vis("clipSlotHint").filter(function(x) { return x.parent.visible }).map(function(x) { return x.text })
    console.log("V128 row hints: " + hints.join(" "))
    win.contentItem.grabToImage(function(r) {
      if (pngDir) r.saveToFile(pngDir + "/popup-banner.png")
      // Alt+1 = pin one (history index 1), Alt+2 = pin two (index 3); no wait for Alt release.
      clip.handleSearchKey({ key: Qt.Key_1, modifiers: Qt.AltModifier, text: "1", accepted: false })
      console.log("V128 after Alt+1: opened=" + clip.opened)
      clip.open("{}"); clip.setFilter("third")
      clip.handleSearchKey({ key: Qt.Key_2, modifiers: Qt.AltModifier, text: "2", accepted: false })
      console.log("V128 after Alt+2 while searching 'third': opened=" + clip.opened)
      clip.open("{}")
      clip.handleSearchKey({ key: Qt.Key_5, modifiers: Qt.AltModifier, text: "5", accepted: false })
      console.log("V128 after Alt+5 (no 5th pin): opened=" + clip.opened)
      clip.openInfo()
      t3.start()
    })
  }
  function step3() {
    var v = all("headerVersion")[0], h = all("headerTitle")[0]
    console.log("V128 popup header: '" + h.text + "' version '" + v.text + "' visible=" + v.visible + " x=" + Math.round(v.x) + " titleEnd=" + Math.round(h.x + h.contentWidth))
    var labels = vis("clipOcrLang").map(function(x) { return x.text })
    console.log("V128 OCR pills: " + labels.join(", "))
    win.contentItem.grabToImage(function(r) {
      if (pngDir) r.saveToFile(pngDir + "/popup-settings-header.png")
      clip.closeInfo(); clip.openSettingsWindow(); tW.start()
    })
  }
  property var shots: [0, 3, 5, 1]
  property int shotI: 0
  function windowShots() {
    var w = clip.settingsWindowRef, k = w.contentItem
    var content = []; find(k, "settingsWindowContent", content)
    console.log("V128 window visible=" + w.visible + " " + w.width + "x" + w.height)
    win2.color = clip.background
    content[0].parent = win2.contentItem
    content[0].anchors.fill = win2.contentItem
    var nav = []; find(win2.contentItem, "settingsNavItem", nav)
    console.log("V128 sidebar: " + nav.map(function(x) { return x.modelData.label }).join(" | "))
    var wv = []; find(win2.contentItem, "settingsWindowVersion", wv)
    console.log("V128 window version: '" + wv[0].text + "'")
    shotI = 0; clip.showSettingsSection(shots[0]); tW2.start()
  }
  function windowShot2() {
    var key = clip.settingsSections[clip.settingsSection].key
    var tt = []; find(win2.contentItem, "settingsPaneTitle", tt)
    var lo = []; find(win2.contentItem, "settingsPaneLoader", lo)
    console.log("V128 pane " + key + ": title '" + tt[0].text + "' content h" + Math.round(lo[0].height))
    win2.contentItem.grabToImage(function(r) {
      if (pngDir) r.saveToFile(pngDir + "/window-" + key + ".png")
      shotI++
      if (shotI < shots.length) { clip.showSettingsSection(shots[shotI]); tW2.start(); return }
      // keys: Down from the last section wraps to General
      clip.showSettingsSection(6); clip.settingsWindowRef.visible = false
      clip.open("{}"); t4.start()
    })
  }
  function step4() {
    vis("ocrBannerDismiss")[0].clicked()
    console.log("V128 after Not now: banner=" + vis("ocrBannerText").length + " dismissed=" + JSON.stringify(clip.ocrDismissed))
    clip.ocrDismissed = []
    clip.rebuildDisplay(false)
    var inst = vis("ocrBannerInstall")
    console.log("V128 banner back after undismiss: " + inst.length)
    inst[0].clicked()
    console.log("V128 after Install: opened=" + clip.opened + " installing=" + clip.ocrInstalling)
    t5.start()
  }
  function step5() {
    console.log("V128 after re-detect: installed=" + JSON.stringify(clip.ocrInfo.installed) + " installing='" + clip.ocrInstalling + "' suggestions=" + clip.ocrSuggest.length)
    // Toast: which preview limits fit 2 lines with the closing quote?
    var limits = [120, 90, 80, 72, 64]
    for (var li = 0; li < limits.length; li++) {
      var fits = samples.map(function(s) { measure.text = CH.ocrPreview(s, limits[li]); return measure.truncated ? "CUT" : "ok" })
      console.log("V128 toast fit limit " + limits[li] + ": " + fits.join(" "))
    }
    measure.text = CH.ocrPreview(samples[0]); console.log("V128 default preview fits: " + !measure.truncated + " '" + CH.ocrPreview(samples[0]) + "'")
    toastTitle.text = "Copied text from screenshot · Super+V pastes"
    toastBody.text = CH.ocrPreview(samples[0])
    tShotToast.start()
  }
  Timer { id: tShotToast; interval: 500; onTriggered: win3.contentItem.grabToImage(function(r) { if (pngDir) r.saveToFile(pngDir + "/notification-ocr.png"); console.log("V128 toast body truncated=" + toastBody.truncated); tEnd.start() }) }
}
