import Quickshell
import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui
// 1.30.0 on the real Clipboard.qml (stub helpers): update check (on by
// default since 1.34.0) (stub says 99.0.0: notice in the popup, once a day only),
// OCR pills with pacman sizes, renamed OCR section, sidebar GitHub link,
// feedback note under Send at 940 and 620 px. PNGs to $HARNESS_PNG_DIR.
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
  function inWin(name) { var o = []; find(win2.contentItem, name, o); return o }
  function right(item) { return item.mapToItem(win2.contentItem, item.width, 0).x }
  Window { id: win; width: 462; height: 700; visible: true; color: "black" }
  // The settings window's content is moved here for the PNG (an offscreen
  // FloatingWindow does not render). 940 px = about half a 1920 px screen.
  Window { id: win2; width: 940; height: 650; visible: true; color: clip ? clip.background : "black" }
  Component.onCompleted: {
    var c = Qt.createComponent("clip/Clipboard.qml")
    if (c.status !== Component.Ready) { console.log("V130 ERR " + c.errorString()); Qt.quit(); return }
    clip = c.createObject(win.contentItem, {})
    var bg = Quickshell.env("HARNESS_BG") || "#1e1e2e", fg = Quickshell.env("HARNESS_FG") || "#cdd6f4", ac = Quickshell.env("HARNESS_ACCENT") || "#89b4fa"
    clip.background = bg; clip.foreground = fg; clip.accent = ac; clip.border = ac; clip.scrim = "transparent"
    clip.selectedBackground = Qt.rgba(Qt.color(fg).r, Qt.color(fg).g, Qt.color(fg).b, 0.12); clip.selectedText = fg
    clip.open("{}")
    t1.start()
  }
  Timer { id: t1; interval: 2500; onTriggered: shell.step1() }
  Timer { id: t2; interval: 1200; onTriggered: shell.step2() }
  Timer { id: t3; interval: 2500; onTriggered: shell.step3() }
  Timer { id: t4; interval: 1500; onTriggered: shell.step4() }
  Timer { id: t5; interval: 800; onTriggered: shell.step5() }
  Timer { id: tEnd; interval: 800; onTriggered: { console.log("V130 done"); Qt.quit() } }
  function step1() {
    var now = Date.now(), h = []
    for (var i = 1; i <= 6; i++) h.push({ type: "text", text: "history item " + i, at: now - i * 1000 })
    clip.history = h
    clip.rebuildDisplay(false)
    console.log("V130 default: updateCheck=" + clip.updateCheck + " notice=" + vis("updateNoticeText").length)
    if (!clip.updateCheck) clip.runSettingsAction("updateCheck")
    clip.open("{}")
    clip.maybeCheckUpdate()
    t2.start()
  }
  function step2() {
    var n = vis("updateNoticeText"), how = vis("updateNoticeHow")
    console.log("V130 update on: latest=" + clip.updateLatest + " available=" + clip.updateAvailable + " lastCheck>0=" + (clip.updateLastCheck > 0))
    console.log("V130 notice: '" + (n.length ? n[0].text : "none") + "' how='" + (how.length ? how[0].text : "") + "'")
    win.contentItem.grabToImage(function(r) {
      if (pngDir) r.saveToFile(pngDir + "/popup-update-notice.png")
      clip.openUrl("file:///etc/passwd")
      clip.openUrl(clip.repoUrl)
      clip.openSettingsWindow("ocr")
      Qt.callLater(function() {
        var w = clip.settingsWindowRef
        var content = []; find(w.contentItem, "settingsWindowContent", content)
        content[0].parent = win2.contentItem
        content[0].anchors.fill = win2.contentItem
        t3.start()
      })
    })
  }
  function step3() {
    console.log("V130 OCR title='" + inWin("settingsPaneTitle")[0].text + "' sizes=" + Object.keys(clip.ocrSizes).length)
    console.log("V130 OCR nav: " + inWin("settingsNavItem").map(function(x) { var t = []; for (var i = 0; i < x.children.length; i++) if (x.children[i].text !== undefined && x.children[i].text) t.push(x.children[i].text + (x.children[i].truncated ? " [TRUNCATED]" : "")); return t.join("") }).join(" | "))
    console.log("V130 OCR pills: " + inWin("clipOcrLang").map(function(b) { return b.text }).join(" | "))
    var help = inWin("clipOcrHelp")[0]; console.log("V130 OCR help: '" + help.text + "'")
    var gh = inWin("settingsGithubLink")[0]
    console.log("V130 GitHub link: visible=" + gh.visible + " y=" + Math.round(gh.mapToItem(win2.contentItem, 0, 0).y) + " h=" + gh.height)
    win2.contentItem.grabToImage(function(r) {
      if (pngDir) r.saveToFile(pngDir + "/window-ocr-sizes.png")
      clip.showSettingsSection(clip.settingsSections.map(function(x) { return x.key }).indexOf("feedback"))
      Qt.callLater(function() {
        var d = inWin("settingsPaneDesc")[0]
        console.log("V130 feedback desc: '" + d.text + "' format=" + d.textFormat)
        var fi = inWin("feedbackInput")[0]
        fi.text = "Hello from the v130 harness"
        console.log("V130 send returned " + clip.sendFeedback(fi))
        t4.start()
      })
    })
  }
  function step4() {
    var note = inWin("feedbackNote")[0], icon = inWin("feedbackSentIcon")[0], send = inWin("feedbackSend")[0]
    console.log("V130 940: note='" + note.text + "' sent=" + clip.feedbackSent + " check='" + icon.text + "' visible=" + icon.visible + " color=" + icon.color + " lines=" + note.lineCount
      + " noteBelowSend=" + (note.mapToItem(win2.contentItem, 0, 0).y >= send.mapToItem(win2.contentItem, 0, send.height).y) + " right=" + Math.round(right(note)) + "/" + win2.width)
    win2.contentItem.grabToImage(function(r) {
      if (pngDir) r.saveToFile(pngDir + "/window-feedback-sent-940.png")
      win2.width = 620
      t5.start()
    })
  }
  function step5() {
    var note = inWin("feedbackNote")[0]
    console.log("V130 620: lines=" + note.lineCount + " right=" + Math.round(right(note)) + "/" + win2.width + " paintedWidth<=width " + (note.paintedWidth <= note.width + 0.5))
    win2.contentItem.grabToImage(function(r) {
      if (pngDir) r.saveToFile(pngDir + "/window-feedback-sent-620.png")
      win2.width = 940
      clip.showSettingsSection(0)
      Qt.callLater(function() {
        console.log("V130 update status: '" + inWin("settingSwitchStatus")[1].text + "'")
        win2.contentItem.grabToImage(function(r2) { if (pngDir) r2.saveToFile(pngDir + "/window-general-update.png"); tEnd.start() })
      })
    })
  }
}
