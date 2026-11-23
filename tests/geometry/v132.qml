import Quickshell
import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui
// 1.32.0 on the real Clipboard.qml (stub helpers): popup header (stock
// PanelHero next to ours), edit mode, left-click "paste and keep open",
// General / History (clear in the window) / Phone / Shortcuts pages,
// subtitle sizes next to the dev gallery header, the phone quarantine
// after incognito. PNGs to $HARNESS_PNG_DIR.
ShellRoot {
  id: shell
  property var clip: null
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
  function inWin(name) { var o = []; find(win2.contentItem, name, o); return o.filter(function(x) { return x.visible }) }
  function texts() { return clip.history.map(function(e) { return JSON.stringify(e.text) + (e.pinned ? "*" : "") }).join(",") }
  function png(w, name, next) { w.contentItem.grabToImage(function(r) { if (pngDir) r.saveToFile(pngDir + "/" + name); next() }) }
  function section(k) { clip.showSettingsSection(clip.settingsSections.map(function(x) { return x.key }).indexOf(k)) }
  function rowIndexOf(text) { for (var i = 0; i < clip.displayModelCount(); i++) if (clip.history[clip.displayRow(i).historyIndex].text === text) return i; return -1 }
  function absY(it) { return Math.round(it.mapToItem(null, 0, 0).y) }
  function absX(it) { return Math.round(it.mapToItem(null, 0, 0).x) }

  Window { id: win; width: 462; height: 700; visible: true; color: "black" }
  Window { id: win2; width: 940; height: 650; visible: true; color: clip ? clip.background : "black" }
  // Stock references, rendered with the same theme colours: the shared
  // PanelHero + PanelSeparator (Bluetooth/Wi-Fi/Display hand-code the same
  // tokens: icon Style.font.display, title Style.font.title bold, caps
  // caption meta, 14 apart) and the dev gallery window header.
  Window {
    id: refWin; width: 462; height: 230; visible: true; color: clip ? clip.background : "black"
    Column {
      x: Style.spacing.panelPadding; y: Style.spacing.panelPadding
      width: parent.width - 2 * Style.spacing.panelPadding
      spacing: Style.space(14)
      PanelHero {
        id: refHero
        title: "Bluetooth"; meta: "Connected"
        foreground: clip ? clip.foreground : "white"
        iconComponent: Component { Text { text: "󰂯"; color: clip ? clip.foreground : "white"; font.family: Style.font.family; font.pixelSize: Style.font.display } }
        trailingControl: Component { ToggleSwitch { checked: true; foreground: clip ? clip.foreground : "white" } }
      }
      PanelSeparator { foreground: clip ? clip.foreground : "white" }
      Column {
        width: parent.width; spacing: Style.space(4)
        Text { text: "Omarchy shell · dev gallery"; color: clip ? clip.foreground : "white"; font.family: "monospace"; font.pixelSize: Style.font.iconLarge; font.bold: true }
        Text { id: refDesc; text: "Live previews of every type exported from qs.Ui. Use this as the visual reference."; color: Qt.darker(clip ? clip.foreground : "white", 1.4); font.family: "monospace"; font.pixelSize: Style.font.bodySmall; width: parent.width; wrapMode: Text.WordWrap }
      }
    }
  }

  Component.onCompleted: {
    var c = Qt.createComponent("clip/Clipboard.qml")
    if (c.status !== Component.Ready) { console.log("V132 ERR " + c.errorString()); Qt.quit(); return }
    clip = c.createObject(win.contentItem, {})
    var bg = Quickshell.env("HARNESS_BG") || "#1e1e2e", fg = Quickshell.env("HARNESS_FG") || "#cdd6f4", ac = Quickshell.env("HARNESS_ACCENT") || "#89b4fa"
    clip.background = bg; clip.foreground = fg; clip.accent = ac; clip.border = ac; clip.scrim = "transparent"; clip.urgent = Quickshell.env("HARNESS_URGENT") || "#a55555"
    clip.selectedBackground = Qt.rgba(Qt.color(fg).r, Qt.color(fg).g, Qt.color(fg).b, 0.12); clip.selectedText = fg
    clip.open("{}")
    t1.start()
  }
  Timer { id: t1; interval: 2500; onTriggered: shell.step1() }
  Timer { id: t2; interval: 1200; onTriggered: shell.step2() }
  Timer { id: t3; interval: 1500; onTriggered: shell.step3() }
  Timer { id: tEnd; interval: 800; onTriggered: { console.log("V132 done"); Qt.quit() } }

  function step1() {
    var now = Date.now()
    clip.history = [{ type: "text", text: "pin one", pinned: true, at: now - 10 }, { type: "text", text: "alpha", at: now - 1000 }, { type: "text", text: "beta", at: now - 2000 }, { type: "text", text: "gamma", at: now - 3000 }]
    clip.rebuildDisplay(false)
    var hero = vis("clipHero")[0], rule = vis("clipHeaderRule")[0], icon = vis("clipHeroIcon")[0]
    console.log("V132 header: icon px=" + icon.font.pixelSize + " (display=" + Style.font.display + ") meta='" + hero.meta + "' title='" + hero.title + "' heroH=" + Math.round(hero.height) + " gap hero->rule=" + (absY(rule) - absY(hero) - Math.round(hero.height)) + " icon x=" + absX(icon))
    console.log("V132 stock:  heroH=" + Math.round(refHero.height) + " gap=" + (absY(refHero.parent.children[1]) - absY(refHero) - Math.round(refHero.height)))
    png(win, "popup-header.png", function() { png(refWin, "stock-hero-and-gallery-header.png", function() {
      // Edit: row button, multi-line text, save keeps pin and place.
      var i = rowIndexOf("alpha")
      clip.selectAbsolute(i)
      console.log("V132 edit button shown: " + vis("clipAction").some(function(a) { return a.iconText === "󰏫" }))
      clip.runRowAction("edit", i, true)
      Qt.callLater(function() {
        var f = vis("clipEditField")
        console.log("V132 editing: fields=" + f.length + " text='" + (f.length ? f[0].text : "") + "' focus=" + (f.length && f[0].activeFocus))
        f[0].text = "alpha edited\nsecond line\nthird line"
        Qt.callLater(function() {
          console.log("V132 edit row height=" + Math.round(f[0].parent.parent.parent.parent.height) + " vs rowHeight=" + clip.rowHeight)
          png(win, "popup-edit.png", function() {
            // A new copy while editing rebuilds the list: the draft stays.
            clip.addClipboardJson(JSON.stringify({ type: "text", text: "delta" }))
            var g = vis("clipEditField")
            console.log("V132 copy while editing: fields=" + g.length + " draft kept=" + (g.length === 1 && g[0].text === "alpha edited\nsecond line\nthird line"))
            clip.saveEdit(g[0].text)
            clip.history = clip.history.filter(function(e) { return e.text !== "delta" }); clip.rebuildDisplay(true)
            console.log("V132 saved: " + texts())
            clip.runRowAction("edit", rowIndexOf("pin one"), true)
            clip.saveEdit("pin one, edited")
            console.log("V132 pinned edit: " + texts())
            clip.runRowAction("edit", rowIndexOf("beta"), true)
            clip.cancelEdit()
            console.log("V132 cancel: editing=" + (clip.editOrig !== "") + " " + texts())
            // Left click: copy, paste and keep open.
            clip.setClickAction("pasteKeep")
            clip.clickIndex(rowIndexOf("gamma"))
            console.log("V132 pasteKeep: closed right after click=" + !clip.opened)
            t2.start()
          })
        })
      })
    }) })
  }
  function step2() {
    console.log("V132 pasteKeep: open again=" + clip.opened + " selected='" + clip.history[clip.displayRow(clip.selectedIndex).historyIndex].text + "'")
    clip.close()
    clip.openSettingsWindow("general")
    Qt.callLater(function() {
      var content = []; find(clip.settingsWindowRef.contentItem, "settingsWindowContent", content)
      content[0].parent = win2.contentItem
      content[0].anchors.fill = win2.contentItem
      t3.start()
    })
  }
  function step3() {
    var d = inWin("settingsPaneDesc")[0], title = inWin("settingsPaneTitle")[0]
    console.log("V132 subtitle px=" + d.font.pixelSize + " family=" + d.font.family + " lineH=" + Math.round(d.contentHeight / Math.max(1, d.lineCount)) + " | gallery px=" + refDesc.font.pixelSize + " lineH=" + Math.round(refDesc.contentHeight / Math.max(1, refDesc.lineCount)))
    var hints = inWin("settingSwitchHint").concat(inWin("clipClickExplain"))
    console.log("V132 hint px: " + hints.map(function(h) { return h.font.pixelSize }).join(",") + " (bodySmall=" + Style.font.bodySmall + ", caption=" + Style.font.caption + ")")
    var lefts = [title, inWin("settingSwitchLabel")[0], inWin("clipClickHeader")[0], inWin("clipClickPill")[0], inWin("clipClickExplain")[0]].map(absX)
    console.log("V132 left edges (heading, switch label, section header, pill, explain): " + lefts.join(","))
    console.log("V132 click pills: " + inWin("clipClickPill").map(function(b) { return b.text + (b.active ? " [on]" : "") }).join(" | ") + " explain='" + inWin("clipClickExplain")[0].text + "'")
    var sw = inWin("settingSwitch")
    console.log("V132 switches: " + inWin("settingSwitchLabel").map(function(l) { return l.text }).join(", ") + " checked=" + sw.map(function(s) { return s.checked }).join(","))
    png(win2, "window-general.png", function() {
      sw[1].toggled()
      console.log("V132 update switch toggled: updateCheck=" + clip.updateCheck)
      Qt.callLater(function() { png(win2, "window-general-update-on.png", function() {
        section("history")
        Qt.callLater(function() {
          var b = inWin("clearHistoryButton")[0]
          console.log("V132 clear button: '" + b.text + "'")
          b.clicked()
          console.log("V132 1st click: armed=" + clip.clearArmed + " '" + b.text + "' popup open=" + clip.opened + " " + texts())
          png(win2, "window-history-clear-armed.png", function() {
            b.clicked()
            console.log("V132 2nd click: " + texts() + " popup open=" + clip.opened + " label now '" + b.text + "'")
            png(win2, "window-history-cleared.png", function() {
              section("flux")
              Qt.callLater(function() { png(win2, "window-phone.png", function() {
                section("shortcuts")
                Qt.callLater(function() { png(win2, "window-shortcuts.png", function() { quarantine() }) })
              }) })
            })
          })
        })
      }) })
    })
  }
  function quarantine() {
    clip.fluxPresent = true
    clip.setPrivate(true, false)
    clip.setPrivate(false, false)
    var now = Math.floor(Date.now() / 1000)
    clip.addClipboardJson(JSON.stringify({ type: "text", text: "sent from phone while incognito" }))
    console.log("V132 quarantine: resume set=" + (clip.fluxResumeMs > 0) + " pending=" + clip.quarantinePending.length + " " + texts())
    clip.applyFluxStatus(JSON.stringify({ running: true, devices: [{ name: "Pixel", paired: true, online: true }], clipboard: [{ dir: "in", text: "sent from phone while incognito", time: now }] }))
    console.log("V132 phone item: pending=" + clip.quarantinePending.length + " " + texts())
    clip.addClipboardJson(JSON.stringify({ type: "text", text: "copied here" }))
    clip.applyFluxStatus(JSON.stringify({ running: true, devices: [{ name: "Pixel", paired: true, online: true }], clipboard: [{ dir: "in", text: "sent from phone while incognito", time: now }] }))
    console.log("V132 local item in the window: " + texts())
    clip.fluxOnlineMs = Date.now() - 6000
    clip.addClipboardJson(JSON.stringify({ type: "text", text: "phone later" }))
    console.log("V132 after the window: pending=" + clip.quarantinePending.length + " " + texts())
    tEnd.start()
  }
}
