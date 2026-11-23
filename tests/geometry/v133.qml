import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui
// 1.33.0 on the real Clipboard.qml (stub helpers): no edit button, the
// 1.31 left-click pills (a saved "pasteKeep" goes back to "paste" and is
// written back), the popup's first heading after Pinned and the settings
// History page next to the stock Display panel section layout. PNGs to
// $HARNESS_PNG_DIR.
ShellRoot {
  id: shell
  property var clip: null
  readonly property string pngDir: Quickshell.env("HARNESS_PNG_DIR") || ""
  readonly property string dataDir: Quickshell.env("XDG_DATA_HOME") + "/timon.clipboard"
  function find(item, name, out) {
    if (!item) return
    if (item.objectName === name && out.indexOf(item) < 0) out.push(item)
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) find(kids[i], name, out)
    if (item.contentItem && item.contentItem !== item) find(item.contentItem, name, out)
  }
  function vis(name) { var o = []; for (var w = 0; w < clip.children.length; w++) find(clip.children[w], name, o); return o.filter(function(x) { return x.visible }) }
  function inWin(name) { var o = []; find(win2.contentItem, name, o); return o.filter(function(x) { return x.visible }) }
  function png(w, name, next) { w.contentItem.grabToImage(function(r) { if (pngDir) r.saveToFile(pngDir + "/" + name); next() }) }
  function section(k) { clip.showSettingsSection(clip.settingsSections.map(function(x) { return x.key }).indexOf(k)) }
  function absY(it) { return Math.round(it.mapToItem(null, 0, 0).y) }
  function absX(it) { return Math.round(it.mapToItem(null, 0, 0).x) }
  // Gap from a separator's bottom to the first ink row of a heading's text box.
  function gap(sep, head) { return absY(head) + (head.topPadding || 0) - absY(sep) - Math.round(sep.height) }

  Window { id: win; width: 462; height: 420; visible: true; color: clip ? clip.background : "black" }
  Window { id: win2; width: 940; height: 420; visible: true; color: clip ? clip.background : "black" }
  // Stock reference: the Display (monitor) panel's SCALE block, built from
  // the same stock parts: Column 14 { PanelSeparator, Column 10 { PanelSectionHeader, Grid of pills } }.
  Window {
    id: refWin; width: 462; height: 160; visible: true; color: clip ? clip.background : "black"
    Column {
      x: Style.spacing.panelPadding; y: Style.spacing.panelPadding
      width: parent.width - 2 * Style.spacing.panelPadding
      spacing: Style.space(14)
      Text { text: "Display"; color: clip ? clip.foreground : "white"; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true }
      PanelSeparator { id: refSep; foreground: clip ? clip.foreground : "white" }
      Column {
        width: parent.width; spacing: Style.space(10)
        PanelSectionHeader { id: refHead; text: "Scale"; foreground: clip ? clip.foreground : "white" }
        Grid {
          id: refGrid; width: parent.width; columns: 4; spacing: Style.spacing.xs
          Repeater {
            model: ["1x", "1.25x", "1.6x", "2x"]
            Button { required property string modelData; width: (refGrid.width - refGrid.spacing * 3) / 4; text: modelData; fontSize: Style.font.caption; bordered: true; active: modelData === "1.6x"; foreground: clip ? clip.foreground : "white"; horizontalPadding: Style.spacing.sm; verticalPadding: Style.spacing.controlPaddingY }
          }
        }
      }
    }
  }
  FileView { id: seedState; path: shell.dataDir + "/state.json"; atomicWrites: true; printErrors: false }
  FileView { id: readState; path: shell.dataDir + "/state.json"; printErrors: false; blockLoading: true }

  Component.onCompleted: {
    // A 1.32 install that chose "Copy, paste and keep open".
    seedState.setText(JSON.stringify({ private: false, clickAction: "pasteKeep" }) + "\n")
    tStart.start()
  }
  Timer { id: tStart; interval: 300; onTriggered: shell.start() }
  function start() {
    var c = Qt.createComponent("clip/Clipboard.qml")
    if (c.status !== Component.Ready) { console.log("V133 ERR " + c.errorString()); Qt.quit(); return }
    clip = c.createObject(win.contentItem, {})
    var bg = Quickshell.env("HARNESS_BG") || "#1e1e2e", fg = Quickshell.env("HARNESS_FG") || "#cdd6f4", ac = Quickshell.env("HARNESS_ACCENT") || "#89b4fa"
    clip.background = bg; clip.foreground = fg; clip.accent = ac; clip.border = ac; clip.scrim = "transparent"; clip.urgent = Quickshell.env("HARNESS_URGENT") || "#a55555"
    clip.selectedBackground = Qt.rgba(Qt.color(fg).r, Qt.color(fg).g, Qt.color(fg).b, 0.12); clip.selectedText = fg
    clip.open("{}")
    t1.start()
  }
  Timer { id: t1; interval: 2500; onTriggered: shell.step1() }
  Timer { id: tEnd; interval: 800; onTriggered: { console.log("V133 done"); Qt.quit() } }

  function step1() {
    readState.reload()
    console.log("V133 migrated: clickAction=" + clip.clickAction + " saved=" + (JSON.parse(readState.text()).clickAction))
    var now = Date.now()
    clip.history = [{ type: "text", text: "pin one", pinned: true, at: now - 10 }, { type: "text", text: "alpha", at: now - 1000 }, { type: "text", text: "beta", at: now - 2000 }]
    clip.rebuildDisplay(false)
    clip.selectAbsolute(0)
    Qt.callLater(function() {
      console.log("V133 edit button shown: " + vis("clipAction").some(function(a) { return a.iconText === "󰏫" }))
      var sep = vis("clipSep")[0], heads = vis("clipSectionHeading")
      var hist = heads.filter(function(h) { return h.text !== "PINNED" })[0]
      var rows = vis("clipRow").map(absY).sort(function(a, b) { return a - b })
      console.log("V133 popup: pinned row bottom->sep=" + (absY(sep) - rows[0] - clip.rowHeight) + " sep->heading=" + gap(sep, hist) + " sep x=" + absX(sep) + " w=" + Math.round(sep.width) + " (header rule x=" + absX(vis("clipHeaderRule")[0]) + " w=" + Math.round(vis("clipHeaderRule")[0].width) + ")")
      console.log("V133 stock Display: sep->heading=" + gap(refSep, refHead) + " heading->pills=" + (absY(refGrid) - absY(refHead) - Math.round(refHead.height)))
      png(win, "popup-history-heading.png", function() { png(refWin, "stock-display-section.png", function() { settings() }) })
    })
  }
  function settings() {
    clip.close()
    clip.openSettingsWindow("general")
    Qt.callLater(function() {
      var content = []; find(clip.settingsWindowRef.contentItem, "settingsWindowContent", content)
      content[0].parent = win2.contentItem
      content[0].anchors.fill = win2.contentItem
      Qt.callLater(function() {
        console.log("V133 general pills: " + inWin("clipClickPill").map(function(b) { return b.text + (b.active ? " [on]" : "") }).join(" | ") + " explain shown=" + (inWin("clipClickExplain").length > 0))
        png(win2, "window-general.png", function() {
          inWin("clipClickPill")[0].clicked()
          console.log("V133 click 'copy': clickAction=" + clip.clickAction)
          section("history")
          Qt.callLater(function() {
            var head = inWin("clipKeepHeader")[0], pill = inWin("clipKeepPill")[0]
            // The page head's separator is the last child of the head column.
            var paneHead = inWin("settingsPaneTitle")[0].parent, rule = paneHead.children[paneHead.children.length - 1]
            console.log("V133 settings History: sep->heading=" + gap(rule, head) + " heading->pills=" + (absY(pill) - absY(head) - Math.round(head.height)))
            png(win2, "window-history.png", function() { tEnd.start() })
          })
        })
      })
    })
  }
}
