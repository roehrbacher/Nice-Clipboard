import Quickshell
import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui
// 1.25.0 on the real Clipboard.qml (stub helpers and notifier): settings
// sections (divider + header, keyboard order = screen order), header title
// and back arrow on the settings page, OCR copy notification with a preview.
// Saves PNGs of the settings page to $V125_PNG_DIR (offscreen, software).
ShellRoot {
  id: shell
  property var clip: null
  property var flick: null
  property int shot: 0
  readonly property string pngDir: Quickshell.env("V125_PNG_DIR") || ""
  function find(item, name, out) {
    if (!item) return
    if (item.objectName === name && out.indexOf(item) < 0) out.push(item)
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) find(kids[i], name, out)
    if (item.contentItem && item.contentItem !== item) find(item.contentItem, name, out)
  }
  function all(name) { var o = []; for (var w = 0; w < clip.children.length; w++) find(clip.children[w], name, o); return o }
  Window { id: win; width: 462; height: 630; visible: true; color: "black" }
  Component.onCompleted: {
    var c = Qt.createComponent("clip/Clipboard.qml")
    if (c.status !== Component.Ready) { console.log("V125 ERR " + c.errorString()); Qt.quit(); return }
    clip = c.createObject(win.contentItem, {})
    var bg = Quickshell.env("V125_BG") || "#1e1e2e", fg = Quickshell.env("V125_FG") || "#cdd6f4", ac = Quickshell.env("V125_ACCENT") || "#89b4fa"
    clip.background = bg; clip.foreground = fg; clip.accent = ac; clip.border = ac; clip.scrim = "transparent"
    clip.selectedBackground = Qt.rgba(Qt.color(fg).r, Qt.color(fg).g, Qt.color(fg).b, 0.12); clip.selectedText = fg
    clip.open("{}")
    t.start()
  }
  Timer { id: t; interval: 3000; onTriggered: shell.step1() }
  Timer { id: t2; interval: 1500; onTriggered: shell.step2() }
  Timer { id: tShot; interval: 600; onTriggered: shell.takeShot() }
  Timer { id: tEnd; interval: 800; onTriggered: { console.log("V125 done"); Qt.quit() } }
  function step1() {
    var now = Date.now()
    clip.history = [
      { type: "text", text: "newest", at: now },
      { type: "image", path: "/nonexistent/s.png", mime: "image/png", bytes: 900, at: now, screenshot: true,
        ocr: "Invoice  4711\n\n<b>Total</b> & tax:\t€ 1.234,50\n" + "lorem ipsum dolor sit amet ".repeat(8), scanned: true, scanv: 3 }
    ]
    clip.rebuildDisplay(false)
    var shotRow = -1; for (var i = 0; i < clip.displayModelCount(); i++) if (clip.displayModelGet(i).ocrText) shotRow = i
    clip.copyOcrText(shotRow)
    clip.open("{}"); clip.openInfo()
    t2.start()
  }
  function step2() {
    var col = all("infoColumn")[0]
    flick = all("infoFlick")[0]
    var heads = [], order = []
    // 1.26.0: sections sit in Loaders; look one level down.
    var kids = []
    for (var j = 0; j < col.children.length; j++) { var c = col.children[j]; if (c.item) for (var q = 0; q < c.item.children.length; q++) kids.push(c.item.children[q]); else kids.push(c) }
    for (var i = 0; i < kids.length; i++) {
      var k = kids[i]
      if (k.title !== undefined && k.first !== undefined) {
        var sep = k.children[0], hdr = k.children[1]
        heads.push(k.title + "@y" + Math.round(k.y) + (sep.visible ? " rule(h" + sep.height + " a" + sep.color.a.toFixed(2) + " w" + sep.width + "/" + col.width + ")" : " no-rule")
          + " header(" + hdr.font.pixelSize + "px bold=" + hdr.font.bold + ")")
      }
    }
    console.log("V125 sections: " + heads.join(" | "))
    var title = all("headerTitle")[0], btn = all("searchButton")[0]
    console.log("V125 header title='" + title.text + "' button visible=" + btn.visible)
    console.log("V125 keyboard order: " + clip.infoActions.join(","))
    var fp = flick.mapToItem(win.contentItem, 0, 0)
    console.log("V125 content height " + Math.round(flick.contentHeight) + " view " + Math.round(flick.height) + " at y " + Math.round(fp.y))
    shot = 0; flick.contentY = 0; tShot.start()
  }
  function takeShot() {
    var target = win.contentItem
    var n = shot
    target.grabToImage(function(r) {
      if (pngDir) r.saveToFile(pngDir + "/settings-" + n + ".png")
      console.log("V125 shot " + n + " at contentY " + Math.round(flick.contentY))
      var maxY = Math.max(0, flick.contentHeight - flick.height)
      if (flick.contentY >= maxY - 1 || shot >= 6) { clip.closeInfo(); console.log("V125 after back: title='" + all("headerTitle")[0].text + "' infoOpen=" + clip.infoOpen); tEnd.start(); return }
      shot++
      flick.contentY = Math.min(maxY, flick.contentY + flick.height * 0.85)
      tShot.start()
    })
  }
}
