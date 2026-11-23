import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui
// 1.32.2 on the real Clipboard.qml (stub helpers): every way the popup
// closes ends edit mode, the clear-history question and an armed delete;
// a cancelled or failed OCR install / removal in the terminal clears its
// "Installing…" / "Removing…" state within 3 s of ocr-install.sh exiting.
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
  function vis(name) { var o = []; for (var w = 0; w < clip.children.length; w++) find(clip.children[w], name, o); return o.filter(function(x) { return x.visible }) }
  function rowIndexOf(text) { for (var i = 0; i < clip.displayModelCount(); i++) if (clip.history[clip.displayRow(i).historyIndex].text === text) return i; return -1 }
  function seed() {
    var now = Date.now()
    clip.history = [{ type: "text", text: "pin one", pinned: true, at: now - 10 }, { type: "text", text: "alpha", at: now - 1000 }, { type: "text", text: "beta", at: now - 2000 }]
    clip.rebuildDisplay(false)
  }
  function modes() { return "editing=" + (clip.editOrig !== "") + " fields=" + vis("clipEditField").length + " clearConfirm=" + clip.clearConfirmOpen + " armedDelete=" + (clip.armedDeleteIndex !== -1) }
  readonly property string doneDir: Quickshell.env("XDG_DATA_HOME") + "/timon.clipboard/"

  Window { id: win; width: 462; height: 700; visible: true; color: "black" }
  FileView { id: removeWriter; path: shell.doneDir + "ocr-done-remove"; atomicWrites: true; printErrors: false }
  FileView { id: installWriter; path: shell.doneDir + "ocr-done-install"; atomicWrites: true; printErrors: false }

  Component.onCompleted: {
    var c = Qt.createComponent("clip/Clipboard.qml")
    if (c.status !== Component.Ready) { console.log("V1322 ERR " + c.errorString()); Qt.quit(); return }
    clip = c.createObject(win.contentItem, {})
    clip.open("{}")
    t1.start()
  }
  Timer { id: t1; interval: 2500; onTriggered: shell.step1() }
  Timer { id: t2; interval: 400; onTriggered: shell.step2() }
  Timer { id: t3; interval: 400; onTriggered: shell.step3() }
  Timer { id: t4; interval: 400; onTriggered: shell.step4() }
  Timer { id: t5; interval: 7000; onTriggered: shell.step5() }
  Timer { id: t6; interval: 3500; onTriggered: shell.step6() }
  Timer { id: tEnd; interval: 500; onTriggered: { console.log("V1322 done"); Qt.quit() } }

  // Edit, then pick another row with the mouse (paste closes the popup).
  function step1() {
    seed()
    clip.clickAction = "paste"
    clip.runRowAction("edit", rowIndexOf("alpha"), true)
    console.log("V1322 edit started: " + modes())
    clip.clickIndex(rowIndexOf("beta"))
    clip.open("{}")
    t2.start()
  }
  // The clear-history question, then Alt+Shift+1 inside the popup.
  function step2() {
    console.log("V1322 reopen after pick while editing: " + modes())
    clip.requestClearHistory()
    console.log("V1322 clear question open: " + modes())
    clip.activateSlot(1)
    clip.open("{}")
    t3.start()
  }
  // An armed delete (pinned row), then Alt+Shift+2; reopened within 3 s.
  function step3() {
    console.log("V1322 reopen after Alt+Shift+1 with the question open: " + modes())
    clip.requestDelete(rowIndexOf("pin one"), true)
    console.log("V1322 delete armed: " + modes())
    clip.activateSlot(2)
    clip.open("{}")
    t4.start()
  }
  // OCR removal and install, both cancelled in the terminal.
  function step4() {
    console.log("V1322 reopen after Alt+Shift+2 with a delete armed: " + modes())
    clip.close()
    clip.removeOcrLanguage({ code: "ita", name: "Italian", protect: "" })
    clip.installOcrLanguage({ code: "fra", name: "French", installed: false })
    console.log("V1322 ocr started: removing=" + clip.ocrRemoving + " installing=" + clip.ocrInstalling)
    t5.start()
  }
  function step5() {
    console.log("V1322 ocr 7 s later, terminal already gone: removing=" + clip.ocrRemoving + " installing=" + clip.ocrInstalling)
    var at = Math.floor(Date.now() / 1000)
    removeWriter.setText(JSON.stringify({ code: "ita", remove: true, rc: 130, at: at }) + "\n")
    t6.start()
  }
  function step6() {
    console.log("V1322 ocr after ita removal cancelled (rc 130): removing=" + clip.ocrRemoving + " installing=" + clip.ocrInstalling)
    var at = Math.floor(Date.now() / 1000)
    installWriter.setText(JSON.stringify({ code: "fra", remove: false, rc: 1, at: at }) + "\n")
    t7.start()
  }
  Timer { id: t7; interval: 3500; onTriggered: { console.log("V1322 ocr after fra install failed (rc 1): removing=" + shell.clip.ocrRemoving + " installing=" + shell.clip.ocrInstalling); tEnd.start() } }
}
