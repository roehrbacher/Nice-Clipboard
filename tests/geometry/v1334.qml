import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Window
import qs.Commons
// 1.33.4 on the real Clipboard.qml (stub clipboard.sh that only logs):
//  - unpin (button/key) puts the item on top of History with a fresh time;
//    the system clipboard and its "on the clipboard" mark stay put,
//  - Ctrl+Z takes back pin and unpin (same stack as delete), and never
//    brings back an item that is gone since,
//  - Clear history empties the system clipboard only if it holds a cleared item,
//  - the floating "Top" button: PNGs with and without list text under it
//    (tests/topbutton.test.sh compares the button's pixels).
// Prints "V1334 PASS ..." / "V1334 FAIL ...".
ShellRoot {
  id: shell
  property var clip: null
  property int fails: 0
  readonly property string pngDir: Quickshell.env("HARNESS_PNG_DIR") || ""
  FileView { id: helperLog; path: Quickshell.env("XDG_DATA_HOME") + "/../helper"; blockLoading: true }
  FileView { id: copyLog; path: Quickshell.env("XDG_DATA_HOME") + "/../wlcopy"; blockLoading: true; printErrors: false }
  function calls() {
    helperLog.reload()
    return String(helperLog.text() || "").split("\n").filter(function(l) { return l !== "" && l.indexOf("current") !== 0 && l.indexOf("init") !== 0 && l.indexOf("prune") !== 0 })
  }
  function check(name, ok, got) { if (!ok) shell.fails++; console.log("V1334 " + (ok ? "PASS " : "FAIL ") + name + (got !== undefined ? "  [" + got + "]" : "")) }
  function find(item, name, out) {
    if (!item) return
    if (item.objectName === name && out.indexOf(item) < 0) out.push(item)
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) find(kids[i], name, out)
    if (item.contentItem && item.contentItem !== item) find(item.contentItem, name, out)
  }
  function one(name) { var o = []; find(clip, name, o); return o[0] }
  function texts() { return clip.history.map(function(e) { return e.text + (e.pinned ? "*" : "") }).join(",") }
  function snap() { return JSON.stringify(clip.history.map(function(e) { return [e.text, e.pinned === true, e.at] })) }
  function shown() { var o = []; for (var i = 0; i < clip.displayModelCount(); i++) { var r = clip.displayRow(i); o.push(clip.history[r.historyIndex].text + (r.pinned ? "*" : "")) } return o.join(",") }
  function rowOf(text) { for (var i = 0; i < clip.displayModelCount(); i++) if (clip.history[clip.displayRow(i).historyIndex].text === text) return i; return -1 }
  function hiOf(text) { for (var i = 0; i < clip.history.length; i++) if (clip.history[i].text === text) return i; return -1 }
  function key(code, mods) { var e = { key: code, nativeScanCode: 0, modifiers: mods, text: "", accepted: false }; clip.handleSearchKey(e); return e.accepted }
  function ctrlZ() { return key(Qt.Key_Z, Qt.ControlModifier) }
  function keyOf(text) { return clip.displayRow(rowOf(text)).clipKey }
  function reopen() { clip.close(); clip.open("{}"); clip.rebuildDisplay(false) }
  // The popup card's own background under the list, as in the shell (a
  // grab does not include the window colour).
  Window { id: win; width: 462; height: 700; visible: true; color: "black"
    Rectangle { anchors.fill: parent; color: Color.popups.background }
  }
  Component.onCompleted: {
    var c = Qt.createComponent("clip/Clipboard.qml")
    if (c.status !== Component.Ready) { console.log("V1334 ERR " + c.errorString()); Qt.quit(); return }
    clip = c.createObject(win.contentItem, {})
    var bg = Quickshell.env("HARNESS_BG") || "#1e1e2e", fg = Quickshell.env("HARNESS_FG") || "#cdd6f4", ac = Quickshell.env("HARNESS_ACCENT") || "#89b4fa"
    clip.background = bg; clip.foreground = fg; clip.accent = ac; clip.border = ac; clip.scrim = "transparent"
    t1.start()
  }
  property int stepNo: 0
  property int mark: 0
  property var t0: 0
  property var before: null
  Timer { id: t1; interval: 2500; onTriggered: shell.next() }
  // Between steps: 700 ms for detached helpers to log, a reload of the
  // stub's log, 200 ms for it to land, then the next step.
  Timer { id: tNext; interval: 700; onTriggered: { helperLog.reload(); tRun.start() } }
  Timer { id: tRun; interval: 200; onTriggered: shell.next() }
  function next() {
    var steps = [step0, step1, step2, step3, step3b, step4, step5, step5b, step6, step7]
    if (shell.stepNo >= steps.length) { console.log("V1334 done fails=" + shell.fails); Qt.quit(); return }
    steps[shell.stepNo++]()
  }
  function step0() {
    var now = Date.now()
    shell.t0 = now
    clip.history = [
      { type: "text", text: "alpha", at: now - 1000 },
      { type: "text", text: "pin A", pinned: true, at: now - 86400000 * 30 },
      { type: "text", text: "beta", at: now - 2000 },
      { type: "text", text: "pin B", pinned: true, at: now - 3000 },
      { type: "text", text: "gamma", at: now - 4000 }
    ]
    reopen()  // the stub says "empty": the open copies the top pin (async)
    tNext.start()
  }
  function step1() {
    clip.currentClipKey = keyOf("beta")   // "beta" is what is copied right now
    shell.before = snap()
    shell.mark = calls().length
    check("start: pins first, then history order", shown() === "pin A*,pin B*,alpha,beta,gamma", shown())
    clip.togglePinDisplayIndex(rowOf("pin B"))
    tNext.start()
  }
  function step2() {
    check("unpin: the item is the first History row", shown() === "pin A*,pin B,alpha,beta,gamma", shown())
    var e = clip.history[hiOf("pin B")]
    check("unpin: fresh copy time (auto-delete starts over)", e.at >= shell.t0 && !e.pinned, e.at - shell.t0)
    check("unpin: nothing copied or pasted", calls().slice(shell.mark).length === 0, calls().slice(shell.mark))
    check("unpin: the clipboard mark stays on beta", clip.currentClipKey === keyOf("beta") && keyOf("pin B") !== clip.currentClipKey)
    var slotsOk = true
    for (var i = 0; i < clip.displayModelCount(); i++) if (clip.displayRow(i).slot !== i + 1) slotsOk = false
    check("Alt+Shift numbers follow the rows (pin B is 2)", slotsOk && clip.displayRow(rowOf("pin B")).slot === 2)
    check("Ctrl+Z is taken", ctrlZ() === true)
    check("Ctrl+Z after unpin: same history as before", snap() === shell.before, texts())
    // Pin, then Ctrl+Z.
    clip.togglePinDisplayIndex(rowOf("gamma"))
    check("pin: gamma pinned", clip.history[hiOf("gamma")].pinned === true && shown().indexOf("gamma*") >= 0, shown())
    ctrlZ()
    check("Ctrl+Z after pin: same history as before", snap() === shell.before, texts())
    // Delete, then pin: two Ctrl+Z take back the pin first, then the delete.
    clip.requestDelete(rowOf("alpha"))
    clip.togglePinDisplayIndex(rowOf("beta"))
    check("delete + pin done", texts() === "pin A*,beta*,pin B*,gamma", texts())
    ctrlZ()
    check("1st Ctrl+Z: the pin", texts() === "pin A*,beta,pin B*,gamma", texts())
    ctrlZ()
    check("2nd Ctrl+Z: the delete", snap() === shell.before, texts())
    check("nothing left: Ctrl+Z goes to the search field", ctrlZ() === false)
    tNext.start()
  }
  function step3() {
    // An item unpinned 30 days after its copy does not vanish at the next auto-delete.
    clip.togglePinDisplayIndex(rowOf("pin A"))
    clip.pruneOld()
    check("unpinned old item survives auto-delete", hiOf("pin A") >= 0 && shown().indexOf("pin A,") === shown().indexOf("pin A"), shown())
    check("it is the first History row", shown() === "pin B*,pin A,alpha,beta,gamma", shown())
    // Clear history removes it; Ctrl+Z must not bring it back as a pin.
    shell.mark = calls().length
    clip.currentClipKey = keyOf("pin B")    // a pinned item is on the clipboard
    clip.clearUnpinned()
    check("Ctrl+Z after clear: nothing comes back", ctrlZ() === false && texts() === "pin B*", texts())
    tNext.start()
  }
  function step3b() {
    check("clear: the top row was not on the clipboard, so it stays", calls().slice(shell.mark).indexOf("clear") < 0, calls().slice(shell.mark))
    tNext.start()
  }
  function step4() {
    var now = Date.now()
    clip.history = [{ type: "text", text: "copied", at: now - 5 }, { type: "text", text: "pinned", pinned: true, at: now }]
    clip.rebuildDisplay(false)
    clip.currentClipKey = keyOf("copied")
    shell.mark = calls().length
    clip.clearUnpinned()
    tNext.start()
  }
  function step5() {
    check("clear: the copied item is cleared, so the clipboard is emptied", calls().slice(shell.mark).indexOf("clear") >= 0, calls().slice(shell.mark))
    // Top button: a long list, scrolled to the end.
    var now = Date.now(), h = []
    for (var i = 0; i < 40; i++) h.push({ type: "text", text: "Example City " + i + " " + Array(60).join("W"), at: now - i * 1000 })
    clip.history = h
    reopen()
    tNext.start()
  }
  function step5b() {
    one("resultList").positionViewAtEnd()
    tNext.start()
  }
  function step6() {
    var b = one("topButton")
    check("Top button shows at the bottom", b && b.visible && b.opacity === 1, b ? b.opacity : "none")
    var p = b.mapToItem(win.contentItem, 0, 0)
    console.log("V1334 TOPRECT " + p.x + " " + p.y + " " + b.width + " " + b.height + " " + win.width)
    check("Top button sits on whole pixels", p.x === Math.round(p.x) && p.y === Math.round(p.y) && b.width === Math.round(b.width), p.x + "," + p.y + " " + b.width)
    win.contentItem.grabToImage(function(r) {
      if (shell.pngDir) r.saveToFile(shell.pngDir + "/top-text.png")
      // Same frame without any list text under the button.
      var list = one("resultList")
      for (var k = 0; k < list.contentItem.children.length; k++) list.contentItem.children[k].opacity = 0
      tNext.start()
    })
  }
  function step7() {
    win.contentItem.grabToImage(function(r) {
      if (shell.pngDir) r.saveToFile(shell.pngDir + "/top-blank.png")
      tNext.start()
    })
  }
}
