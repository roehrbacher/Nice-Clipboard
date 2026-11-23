import Quickshell
import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui
// 1.27.0 on the real Clipboard.qml (stub helpers): the OCR language
// suggestion (German from locale + layout), its copy and dismiss buttons,
// direct feedback to a local fake Worker, popup + window PNGs.
// Saves PNGs to $V127_PNG_DIR (offscreen, software).
ShellRoot {
  id: shell
  property var clip: null
  property var flick: null
  property int shot: 0
  readonly property string pngDir: Quickshell.env("V127_PNG_DIR") || ""
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
    if (c.status !== Component.Ready) { console.log("V127 ERR " + c.errorString()); Qt.quit(); return }
    clip = c.createObject(win.contentItem, {})
    var bg = Quickshell.env("V127_BG") || "#1e1e2e", fg = Quickshell.env("V127_FG") || "#cdd6f4", ac = Quickshell.env("V127_ACCENT") || "#89b4fa"
    clip.background = bg; clip.foreground = fg; clip.accent = ac; clip.border = ac; clip.scrim = "transparent"
    clip.selectedBackground = Qt.rgba(Qt.color(fg).r, Qt.color(fg).g, Qt.color(fg).b, 0.12); clip.selectedText = fg
    clip.open("{}")
    t.start()
  }
  Timer { id: t; interval: 2500; onTriggered: shell.step1() }
  Timer { id: t2; interval: 1500; onTriggered: shell.step2() }
  Timer { id: t3; interval: 2500; onTriggered: shell.step3() }
  Timer { id: tWin; interval: 1500; onTriggered: shell.windowShot() }
  Timer { id: tWin2; interval: 800; onTriggered: shell.windowShot2() }
  Timer { id: tEnd; interval: 800; onTriggered: { console.log("V127 done"); Qt.quit() } }
  function scrollTo(name) {
    var it = all(name).filter(function(x) { return x.visible })[0]
    var p = it.mapToItem(flick.contentItem, 0, 0)
    flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, p.y - 40))
  }
  function step1() {
    var now = Date.now()
    clip.history = [{ type: "text", text: "h1", at: now }, { type: "text", text: "h2", at: now - 1000 }]
    clip.rebuildDisplay(false)
    clip.openInfo()
    flick = all("infoFlick")[0]
    t2.start()
  }
  function step2() {
    console.log("V127 ocrInfo hints=" + JSON.stringify(clip.ocrInfo.hints) + " installed=" + JSON.stringify(clip.ocrInfo.installed))
    var sg = all("clipOcrSuggest").filter(function(x) { return x.visible })
    console.log("V127 suggestions in popup: " + sg.length + " codes=" + sg.map(function(x) { return x.code }).join(","))
    var tx = all("clipOcrSuggestText").filter(function(x) { return x.visible })
    if (tx.length) console.log("V127 suggestion text: '" + tx[0].text + "'")
    var cp = all("clipOcrSuggestCopy").filter(function(x) { return x.visible })
    if (cp.length) { console.log("V127 copy button: '" + cp[0].text + "'"); cp[0].clicked() }
    scrollTo("clipOcrHeading")
    win.contentItem.grabToImage(function(r) {
      if (pngDir) r.saveToFile(pngDir + "/popup-ocr-suggestion.png")
      // Direct feedback through the local fake Worker.
      var fi = all("feedbackInput").filter(function(x) { return x.visible })[0]
      fi.text = "Hello from the v127 harness & <test>"
      console.log("V127 send returned " + clip.sendFeedback(fi) + " note='" + clip.feedbackNote + "'")
      scrollTo("feedbackBox")
      t3.start()
    })
  }
  function step3() {
    var fi = all("feedbackInput").filter(function(x) { return x.visible })[0]
    var note = all("feedbackNote").filter(function(x) { return x.visible })[0]
    console.log("V127 after send: note='" + clip.feedbackNote + "' shown='" + note.text + "' field='" + fi.text + "'")
    win.contentItem.grabToImage(function(r) {
      if (pngDir) r.saveToFile(pngDir + "/popup-feedback-sent.png")
      clip.closeInfo(); clip.openSettingsWindow(); tWin.start()
    })
  }
  function windowShot() {
    var w = clip.settingsWindowRef
    var k = w.contentItem
    var sg = []; find(k, "clipOcrSuggest", sg)
    console.log("V127 window visible=" + w.visible + " suggestions in window: " + sg.length)
    var content = []; find(k, "settingsWindowContent", content)
    win2.color = clip.background
    content[0].parent = win2.contentItem
    content[0].anchors.fill = win2.contentItem
    tWin2.start()
  }
  function windowShot2() {
    var w = clip.settingsWindowRef
    win2.contentItem.grabToImage(function(r) {
      if (pngDir) r.saveToFile(pngDir + "/window-settings.png")
      w.visible = false
      clip.dismissOcrSuggestion("deu")
      var left = []; find(win2.contentItem, "clipOcrSuggest", left)
      console.log("V127 after dismiss: suggestions=" + clip.ocrSuggest.length + " in window=" + left.filter(function(x) { return x.visible }).length + " dismissed=" + JSON.stringify(clip.ocrDismissed))
      tEnd.start()
    })
  }
}
