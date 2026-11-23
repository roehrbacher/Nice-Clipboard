import Quickshell
import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui
// 1.31.0 on the real Clipboard.qml (stub helpers): delete button arms (red,
// check icon) and confirms, disarms on mouse leave / after 3 s, Ctrl+Z
// undo (place + pin), General / History / Text recognition / Uninstall
// pages. PNGs to $V131_PNG_DIR.
ShellRoot {
  id: shell
  property var clip: null
  readonly property string pngDir: Quickshell.env("V131_PNG_DIR") || ""
  function find(item, name, out) {
    if (!item) return
    if (item.objectName === name && out.indexOf(item) < 0) out.push(item)
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) find(kids[i], name, out)
    if (item.contentItem && item.contentItem !== item) find(item.contentItem, name, out)
  }
  function all(name) { var o = []; for (var w = 0; w < clip.children.length; w++) find(clip.children[w], name, o); return o }
  function vis(name) { return all(name).filter(function(x) { return x.visible }) }
  function inWin(name) { var o = []; find(win2.contentItem, name, o); return o.filter(function(x) { return x.visible }) }
  function texts() { return clip.history.map(function(e) { return e.text + (e.pinned ? "*" : "") }).join(",") }
  function key(code, mods) { var e = { key: code, nativeScanCode: 0, modifiers: mods, text: "", accepted: false }; clip.handleSearchKey(e); return e.accepted }
  function png(win, name, next) { win.contentItem.grabToImage(function(r) { if (pngDir) r.saveToFile(pngDir + "/" + name); next() }) }
  function section(k) { clip.showSettingsSection(clip.settingsSections.map(function(x) { return x.key }).indexOf(k)) }
  Window { id: win; width: 462; height: 700; visible: true; color: "black" }
  Window { id: win2; width: 940; height: 650; visible: true; color: clip ? clip.background : "black" }
  Component.onCompleted: {
    var c = Qt.createComponent("clip/Clipboard.qml")
    if (c.status !== Component.Ready) { console.log("V131 ERR " + c.errorString()); Qt.quit(); return }
    clip = c.createObject(win.contentItem, {})
    var bg = Quickshell.env("V131_BG") || "#1e1e2e", fg = Quickshell.env("V131_FG") || "#cdd6f4", ac = Quickshell.env("V131_ACCENT") || "#89b4fa"
    clip.background = bg; clip.foreground = fg; clip.accent = ac; clip.border = ac; clip.scrim = "transparent"; clip.urgent = Quickshell.env("V131_URGENT") || "#a55555"
    clip.selectedBackground = Qt.rgba(Qt.color(fg).r, Qt.color(fg).g, Qt.color(fg).b, 0.12); clip.selectedText = fg
    clip.open("{}")
    t1.start()
  }
  Timer { id: t1; interval: 2500; onTriggered: shell.step1() }
  Timer { id: t2; interval: 3400; onTriggered: shell.step2() }
  Timer { id: t3; interval: 1500; onTriggered: shell.step3() }
  Timer { id: t4; interval: 2500; onTriggered: shell.step4() }
  Timer { id: tEnd; interval: 800; onTriggered: { console.log("V131 done"); Qt.quit() } }
  function rowIndexOf(text) { for (var i = 0; i < clip.displayModelCount(); i++) if (clip.history[clip.displayRow(i).historyIndex].text === text) return i; return -1 }
  function step1() {
    var now = Date.now()
    clip.history = [{ type: "text", text: "pin one", pinned: true, at: now - 10 }, { type: "text", text: "alpha", at: now - 1000 }, { type: "text", text: "beta", at: now - 2000 }, { type: "text", text: "gamma", at: now - 3000 }]
    clip.rebuildDisplay(false)
    console.log("V131 start: " + texts())
    var i = rowIndexOf("beta")
    clip.selectAbsolute(i)
    clip.runRowAction("delete", i, true)
    var red = vis("clipDeleteArmed")
    console.log("V131 1st click: deleted=" + (texts().indexOf("beta") < 0) + " armed red=" + red.length + " glyph=" + vis("clipAction").filter(function(a) { return a.iconText === "󰄬" }).length)
    png(win, "popup-delete-armed.png", function() {
      clip.runRowAction("delete", rowIndexOf("beta"), true)
      console.log("V131 2nd click: " + texts())
      // Leaving the armed button disarms it.
      clip.runRowAction("delete", rowIndexOf("gamma"), true)
      var armedBtn = vis("clipAction").filter(function(a) { return a.iconText === "󰄬" })[0]
      armedBtn.hovered(false)
      console.log("V131 mouse left: armed=" + clip.armedDeleteIndex)
      // Keyboard Del on an unpinned row: at once.
      clip.selectAbsolute(rowIndexOf("gamma")); clip.requestDelete(rowIndexOf("gamma"))
      // Pinned row: click twice.
      clip.runRowAction("delete", rowIndexOf("pin one"), true); clip.runRowAction("delete", rowIndexOf("pin one"), true)
      console.log("V131 after 3 deletes: " + texts() + " undo=" + clip.undoStack.length)
      console.log("V131 Ctrl+Z accepted=" + key(Qt.Key_Z, Qt.ControlModifier) + " -> " + texts())
      key(Qt.Key_Z, Qt.ControlModifier); key(Qt.Key_Z, Qt.ControlModifier)
      console.log("V131 Ctrl+Z x3 -> " + texts() + " undo=" + clip.undoStack.length + " 4th accepted=" + key(Qt.Key_Z, Qt.ControlModifier))
      // Auto reset after 3 s.
      clip.runRowAction("delete", rowIndexOf("alpha"), true)
      t2.start()
    })
  }
  function step2() {
    console.log("V131 after 3.4 s: armed=" + clip.armedDeleteIndex)
    clip.runRowAction("delete", rowIndexOf("alpha"), true)
    clip.close()
    console.log("V131 popup closed: armed=" + clip.armedDeleteIndex + " " + texts())
    clip.openSettingsWindow("general")
    Qt.callLater(function() {
      var w = clip.settingsWindowRef
      var content = []; find(w.contentItem, "settingsWindowContent", content)
      content[0].parent = win2.contentItem
      content[0].anchors.fill = win2.contentItem
      t3.start()
    })
  }
  function step3() {
    var d = inWin("settingsPaneDesc")[0]
    console.log("V131 subtitle: px=" + d.font.pixelSize + " (Style.font.bodySmall=" + Style.font.bodySmall + ", caption=" + Style.font.caption + ") color=" + d.color)
    console.log("V131 incognito hint: '" + inWin("incognitoHint")[0].text + "'")
    png(win2, "window-general.png", function() {
      section("history")
      Qt.callLater(function() {
        console.log("V131 history header: '" + inWin("clipKeepHeader")[0].text + "' active=" + clip.keepDays)
        png(win2, "window-history.png", function() {
          section("ocr")
          t4.start()
        })
      })
    })
  }
  function step4() {
    var rows = inWin("clipOcrInstalled")
    console.log("V131 OCR installed rows: " + rows.map(function(r) { return r.modelData.name + " " + r.modelData.size + " use=" + r.modelData.inUse + (r.modelData.protect ? " [" + r.modelData.protect + "]" : " [Remove]") }).join(" | "))
    console.log("V131 OCR add pills: " + inWin("clipOcrLang").map(function(b) { return b.text }).join(" | "))
    png(win2, "window-ocr.png", function() {
      clip.toggleOcrUse("ita")
      console.log("V131 ita off: ocrOff=" + JSON.stringify(clip.ocrOff))
      var rm = inWin("clipOcrRemove")
      rm.filter(function(b) { return b.parent.parent.code === "deu" })[0].clicked()
      inWin("clipOcrLang").filter(function(b) { return b.code === "fra" })[0].clicked()
      Qt.callLater(function() {
        console.log("V131 rows after ita off: " + inWin("clipOcrInstalled").map(function(r) { return r.code + "=" + r.modelData.inUse }).join(","))
        png(win2, "window-ocr-ita-off.png", function() {
          section("uninstall")
          Qt.callLater(function() {
            var b = inWin("uninstallButton")
            b[0].clicked()
            console.log("V131 uninstall 1st click: armed=" + clip.uninstallArmed + " text='" + b[0].text + "'")
            png(win2, "window-uninstall-armed.png", function() {
              b[0].clicked()
              console.log("V131 uninstall 2nd click: armed='" + clip.uninstallArmed + "'")
              b[1].clicked(); b[1].hovered(false)
              console.log("V131 languages button left: armed='" + clip.uninstallArmed + "'")
              b[1].clicked(); b[1].clicked()
              section("feedback")
              Qt.callLater(function() { png(win2, "window-feedback.png", function() { tEnd.start() }) })
            })
          })
        })
      })
    })
  }
}
