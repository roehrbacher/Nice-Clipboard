import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Window
// 1.34.1 on the real Clipboard.qml (external review findings):
// 1. history.json is cut off (v1341.history). It must be set aside as
//    history.json.bad-<time>, unchanged, and a new copy must not be saved
//    over it.
// 2. A copy that arrives before the history file is read is kept once the
//    file is loaded (it used to replace the whole history).
// 3. A pinned row is dragged to the third slot and a copy arrives before the
//    drop: the drop still saves the dragged order and the new item shows.
// 4. A copy arrives while a row is only pressed (not moved yet): the list
//    updates at once and a drag started afterwards still moves that entry.
ShellRoot {
  id: shell
  property var clip: null
  Window { id: win; width: 462; height: 700; visible: true; color: "black" }
  FileView { id: live; path: ""; blockLoading: true; printErrors: false }
  Component.onCompleted: {
    var c = Qt.createComponent("clip/Clipboard.qml")
    if (c.status !== Component.Ready) { console.log("V1341 ERR " + c.errorString()); Qt.quit(); return }
    clip = c.createObject(win.contentItem, {})
    t1.start()
  }
  Timer { id: t1; interval: 2500; onTriggered: shell.step1() }
  Timer { id: t2; interval: 1000; onTriggered: shell.step2() }
  Timer { id: t3; interval: 800; onTriggered: shell.step3() }
  Timer { id: t4; interval: 800; onTriggered: shell.step4() }
  Timer { id: tEnd; interval: 800; onTriggered: { console.log("V1341 done"); Qt.quit() } }
  function texts(h) { return "[" + h.map(function(e) { return (e.pinned ? "*" : "") + e.text }).join(", ") + "]" }
  function rows() {
    var o = []
    for (var i = 0; i < clip.displayModelCount(); i++) { var r = clip.displayRow(i); o.push((r.pinned ? "*" : "") + r.fullText) }
    return "[" + o.join(", ") + "]"
  }
  function step1() {
    console.log("V1341 after loading the cut-off file: " + texts(clip.history))
    clip.storeEntry({ type: "text", text: "after the break" })
    t2.start()
  }
  function step2() {
    live.path = Quickshell.env("XDG_DATA_HOME") + "/timon.clipboard/history.json"
    console.log("V1341 history.json after a copy: " + String(live.text()).trim())
    // 2: a copy before the file is read
    clip.historyLoaded = false
    clip.storeEntry({ type: "text", text: "early copy" })
    clip.loadHistory(JSON.stringify([{ type: "text", text: "saved pin", pinned: true, at: Date.now() - 5000 }, { type: "text", text: "saved item", at: Date.now() - 4000 }]))
    console.log("V1341 early copy then load: " + texts(clip.history))
    t3.start()
  }
  function step3() {
    var now = Date.now()
    clip.history = [{ type: "text", text: "P1", pinned: true, at: now - 10 }, { type: "text", text: "P2", pinned: true, at: now - 20 },
                    { type: "text", text: "P3", pinned: true, at: now - 30 }, { type: "text", text: "h1", at: now - 1000 }, { type: "text", text: "h2", at: now - 2000 }]
    clip.open("{}")
    clip.rebuildDisplay(false)
    clip.dragStart(0)
    clip.dragMoveTo(2)
    clip.storeEntry({ type: "text", text: "incoming" })
    var err = ""
    try { clip.dragFinish() } catch (e) { err = String(e) }
    console.log("V1341 drag with a copy mid-drag: history " + texts(clip.history) + " rows " + rows() + (err ? " ERROR " + err : ""))
    t4.start()
  }
  function step4() {
    var now = Date.now()
    clip.history = [{ type: "text", text: "h1", at: now - 1000 }, { type: "text", text: "P1", pinned: true, at: now - 10 }, { type: "text", text: "P2", pinned: true, at: now - 20 }]
    clip.rebuildDisplay(false)
    clip.dragStart(0)
    clip.storeEntry({ type: "text", text: "pressed copy" })
    console.log("V1341 rows right after a copy during a press: " + rows())
    clip.dragMoved = true
    clip.dragMoveTo(1)
    var err = ""
    try { clip.dragFinish() } catch (e) { err = String(e) }
    console.log("V1341 press, copy, then drag: history " + texts(clip.history) + (err ? " ERROR " + err : ""))
    tEnd.start()
  }
}
