import Quickshell
import QtQuick
import QtQuick.Window
// 1.33.1 on the real Clipboard.qml: typing in the feedback box while a send
// is still on its way. The fake Worker takes 2 s for a message with "slow".
// The "Sending…" note stays until the answer, and the text typed after
// pressing Send is kept (only what was sent is removed).
// A pinned row armed for delete (first Del), then a copy arrives from
// another app: the red "click again" state must not move to another row
// (it ends; the next Del arms again).
ShellRoot {
  id: shell
  property var clip: null
  function find(item, name, out) {
    if (!item) return
    if (item.objectName === name && out.indexOf(item) < 0) out.push(item)
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) find(kids[i], name, out)
    if (item.contentItem && item.contentItem !== item) find(item.contentItem, name, out)
  }
  function inWin(name) { var o = []; find(win2.contentItem, name, o); return o }
  Window { id: win; width: 462; height: 700; visible: true; color: "black" }
  Window { id: win2; width: 900; height: 650; visible: true; color: "black" }
  property var fi: null
  Component.onCompleted: {
    var c = Qt.createComponent("clip/Clipboard.qml")
    if (c.status !== Component.Ready) { console.log("V1331 ERR " + c.errorString()); Qt.quit(); return }
    clip = c.createObject(win.contentItem, {})
    t1.start()
  }
  Timer { id: t1; interval: 2500; onTriggered: shell.step1() }
  Timer { id: t2; interval: 400; onTriggered: shell.step2() }
  Timer { id: t3; interval: 3500; onTriggered: shell.step3() }
  Timer { id: t4; interval: 1500; onTriggered: shell.step4() }
  Timer { id: tEnd; interval: 300; onTriggered: { console.log("V1331 done"); Qt.quit() } }
  function step1() {
    clip.openSettingsWindow("feedback")
    Qt.callLater(function() {
      var content = []; find(clip.settingsWindowRef.contentItem, "settingsWindowContent", content)
      content[0].parent = win2.contentItem
      content[0].anchors.fill = win2.contentItem
      fi = inWin("feedbackInput")[0]
      fi.text = "slow first message"
      console.log("V1331 send: " + clip.sendFeedback(fi) + " note='" + clip.feedbackNote + "'")
      t2.start()
    })
  }
  function step2() {
    fi.insert(fi.length, " and a second thought")
    console.log("V1331 typing while sending: note='" + clip.feedbackNote + "'")
    console.log("V1331 send again while sending: " + clip.sendFeedback(fi) + " note='" + clip.feedbackNote + "'")
    t3.start()
  }
  function step3() {
    console.log("V1331 after the answer: input='" + fi.text + "' note='" + clip.feedbackNote + "' sent=" + clip.feedbackSent)
    fi.text = "fast message"
    clip.sendFeedback(fi)
    t4.start()
  }
  function step4() {
    console.log("V1331 untouched send: input='" + fi.text + "' sent=" + clip.feedbackSent)
    var now = Date.now()
    clip.history = [{ type: "text", text: "pin one", pinned: true, at: now - 10 }, { type: "text", text: "alpha", at: now - 1000 }]
    clip.open("{}")
    clip.rebuildDisplay(false)
    clip.requestDelete(0, false)
    console.log("V1331 armed rows: " + armedRows())
    clip.storeEntry({ type: "text", text: "copied elsewhere" })
    console.log("V1331 armed rows after a copy from another app: " + armedRows())
    tEnd.start()
  }
  function armedRows() {
    var o = []
    for (var i = 0; i < clip.displayModelCount(); i++) {
      var r = clip.displayRow(i)
      if (r.historyIndex === clip.armedDeleteIndex) o.push(clip.history[r.historyIndex].text)
    }
    return "[" + o.join(", ") + "]"
  }
}
