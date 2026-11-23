import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui
// 1.33.2 on the real Clipboard.qml (stub helpers): empty-state and search
// placeholder dimming next to the stock launcher; OCR no longer polls
// scan.sh --langs while a terminal job is running. PNGs to $HARNESS_PNG_DIR.
ShellRoot {
  id: shell
  property var clip: null
  readonly property string pngDir: Quickshell.env("HARNESS_PNG_DIR") || ""
  readonly property string dataDir: Quickshell.env("XDG_DATA_HOME") + "/timon.clipboard"
  readonly property string langsFile: Quickshell.env("XDG_DATA_HOME") + "/langs"
  function find(item, name, out) {
    if (!item) return
    if (item.objectName === name && out.indexOf(item) < 0) out.push(item)
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) find(kids[i], name, out)
    if (item.contentItem && item.contentItem !== item) find(item.contentItem, name, out)
  }
  function vis(name) { var o = []; for (var w = 0; w < clip.children.length; w++) find(clip.children[w], name, o); return o.filter(function(x) { return x.visible }) }
  function png(w, name, next) { w.contentItem.grabToImage(function(r) { if (pngDir) r.saveToFile(pngDir + "/" + name); next() }) }
  function langsCount() { langsView.reload(); var t = String(langsView.text() || ""); return t ? t.replace(/\s+$/, "").split(/\n/).length : 0 }
  function describe(it) {
    if (!it) return "missing"
    return "opacity=" + it.opacity + " color=" + String(it.color)
  }

  readonly property color refBg: Quickshell.env("HARNESS_BG") || "#1e1e2e"
  readonly property color refFg: Quickshell.env("HARNESS_FG") || "#cdd6f4"
  Window { id: win; width: 462; height: 520; visible: true; color: clip ? clip.background : shell.refBg }
  // Stock reference: the launcher search placeholder and empty state,
  // copied from Menu.qml (and the stock clipboard / emoji picker).
  Window {
    id: refWin; width: 462; height: 520; visible: true; color: shell.refBg
    Column {
      anchors.fill: parent
      anchors.margins: Style.spacing.panelPadding
      spacing: Style.space(14)
      Text {
        text: "Stock launcher"
        color: shell.refFg
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        id: refPlaceholder
        objectName: "stockSearchPlaceholder"
        width: parent.width
        text: "Go…"
        color: shell.refFg
        opacity: 0.58
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
      Item {
        width: parent.width
        height: 280
        Column {
          anchors.centerIn: parent
          spacing: Style.space(8)
          Text {
            id: refEmptyIcon
            objectName: "stockEmptyIcon"
            text: "󰈉"
            color: shell.refFg
            opacity: 0.8
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.displayLarge
            horizontalAlignment: Text.AlignHCenter
            width: Style.space(320)
          }
          Text {
            id: refEmptyText
            objectName: "stockEmptyText"
            textFormat: Text.PlainText
            text: "Nothing here yet"
            color: shell.refFg
            opacity: 0.7
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
            horizontalAlignment: Text.AlignHCenter
            width: Style.space(320)
          }
        }
      }
      Text {
        text: "Stock panel field (qs.Ui.TextField)"
        color: shell.refFg
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
      }
      TextField {
        id: refField
        width: parent.width
        placeholderText: "Search city"
        foreground: shell.refFg
        font.family: Style.font.menuFamily
      }
    }
  }
  FileView { id: langsView; path: shell.langsFile; printErrors: false; blockLoading: true }
  FileView { id: installWriter; path: shell.dataDir + "/ocr-done-install"; atomicWrites: true; printErrors: false }

  property int langsAtJobStart: -1

  Component.onCompleted: tStart.start()
  Timer { id: tStart; interval: 300; onTriggered: shell.start() }
  Timer { id: t1; interval: 2500; onTriggered: shell.step1() }
  Timer { id: tJob; interval: 4000; onTriggered: shell.stepJob() }
  Timer { id: tDone; interval: 3500; onTriggered: shell.stepDone() }
  Timer { id: tEnd; interval: 800; onTriggered: { console.log("V1332 done"); Qt.quit() } }

  function start() {
    var c = Qt.createComponent("clip/Clipboard.qml")
    if (c.status !== Component.Ready) { console.log("V1332 ERR " + c.errorString()); Qt.quit(); return }
    clip = c.createObject(win.contentItem, {})
    var bg = Quickshell.env("HARNESS_BG") || "#1e1e2e", fg = Quickshell.env("HARNESS_FG") || "#cdd6f4", ac = Quickshell.env("HARNESS_ACCENT") || "#89b4fa"
    clip.background = bg; clip.foreground = fg; clip.accent = ac; clip.border = ac; clip.scrim = "transparent"; clip.urgent = Quickshell.env("HARNESS_URGENT") || "#a55555"
    clip.selectedBackground = Qt.rgba(Qt.color(fg).r, Qt.color(fg).g, Qt.color(fg).b, 0.12); clip.selectedText = fg
    clip.history = []
    clip.rebuildDisplay(false)
    clip.open("{}")
    t1.start()
  }

  function step1() {
    clip.history = []
    clip.filterText = ""
    clip.searchExpanded = true
    clip.rebuildDisplay(false)
    Qt.callLater(function() {
      var ph = vis("clipSearchPlaceholder")[0], icon = vis("clipEmptyIcon")[0], tx = vis("clipEmptyText")[0]
      console.log("V1332 ours: placeholder " + describe(ph) + " emptyIcon " + describe(icon) + " emptyText " + describe(tx) + " emptyText='" + (tx ? tx.text : "") + "'")
      console.log("V1332 stock launcher: placeholder " + describe(refPlaceholder) + " emptyIcon " + describe(refEmptyIcon) + " emptyText " + describe(refEmptyText))
      console.log("V1332 stock TextField placeholderTextColor=" + String(refField.placeholderTextColor))
      png(win, "popup-empty-and-search.png", function() {
        png(refWin, "stock-launcher-empty-and-search.png", function() { ocrStart() })
      })
    })
  }

  function ocrStart() {
    clip.close()
    clip.installOcrLanguage({ code: "fra", name: "French", installed: false })
    shell.langsAtJobStart = langsCount()
    console.log("V1332 ocr started: installing=" + clip.ocrInstalling + " langs=" + shell.langsAtJobStart)
    tJob.start()
  }

  function stepJob() {
    var n = langsCount()
    console.log("V1332 ocr 4 s later, still running: installing=" + clip.ocrInstalling + " langs=" + n + " extra=" + (n - shell.langsAtJobStart))
    var at = Math.floor(Date.now() / 1000)
    installWriter.setText(JSON.stringify({ code: "fra", remove: false, rc: 1, at: at }) + "\n")
    tDone.start()
  }

  function stepDone() {
    console.log("V1332 ocr after fra install failed (rc 1): installing=" + clip.ocrInstalling + " langs=" + langsCount())
    tEnd.start()
  }
}
