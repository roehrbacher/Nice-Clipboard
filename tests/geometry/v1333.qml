import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Window
// 1.33.3 on the real Clipboard.qml (stub clipboard.sh that only logs):
// "Select, paste & close" closes the popup and hands the paste to
// clipboard.sh together with the window that had the keyboard when the
// popup opened, so the paste goes back there. Offscreen there is no
// Hyprland, so the test sets that address the way the open would.
// Prints "V1333 PASS ..." / "V1333 FAIL ..." per check.
ShellRoot {
  id: shell
  property var clip: null
  property int fails: 0
  FileView { id: helperLog; path: Quickshell.env("XDG_DATA_HOME") + "/../helper"; blockLoading: true }
  function calls() {
    helperLog.reload()
    return String(helperLog.text() || "").split("\n").filter(function(l) { return l !== "" && l.indexOf("current") !== 0 && l.indexOf("init") !== 0 && l.indexOf("prune") !== 0 })
  }
  function last() { var c = calls(); return c.length ? c[c.length - 1] : "" }
  function check(name, ok, got) { if (!ok) shell.fails++; console.log("V1333 " + (ok ? "PASS " : "FAIL ") + name + (got !== undefined ? "  [" + got + "]" : "")) }
  function rowOf(text) { for (var i = 0; i < clip.displayModelCount(); i++) if (clip.history[clip.displayRow(i).historyIndex].text === text) return i; return -1 }
  function hiOf(text) { for (var i = 0; i < clip.history.length; i++) if (clip.history[i].text === text) return i; return -1 }
  // The stub says the clipboard is empty, so each open puts the top pin
  // there ("copy 0", stock behaviour); the reload in next() picks it up
  // before the next action sets its mark.
  function reopen() { clip.close(); clip.open("{}"); clip.rebuildDisplay(false) }
  Window { id: win; width: 462; height: 700; visible: true; color: "black" }
  Component.onCompleted: {
    var c = Qt.createComponent("clip/Clipboard.qml")
    if (c.status !== Component.Ready) { console.log("V1333 ERR " + c.errorString()); Qt.quit(); return }
    clip = c.createObject(win.contentItem, {})
    t1.start()
  }
  // Each step: an action, then (700 ms later) a reload of the stub's log,
  // then (200 ms later) the checks on the calls the action added.
  property int mark: 0
  property int stepNo: 0
  function added() { return calls().slice(shell.mark) }
  function act(fn) { shell.mark = calls().length; fn() }
  Timer { id: t1; interval: 2500; onTriggered: shell.next() }
  Timer { id: tReload; interval: 700; onTriggered: { helperLog.reload(); tCheck.start() } }
  Timer { id: tCheck; interval: 200; onTriggered: shell.next() }
  function next() {
    var steps = [step1, step2, step3, step4, step5]
    if (shell.stepNo >= steps.length) { console.log("V1333 done fails=" + shell.fails); Qt.quit(); return }
    steps[shell.stepNo++]()
    tReload.start()
  }
  function step1() {
    var now = Date.now()
    clip.history = [{ type: "text", text: "pin one", pinned: true, at: now - 10 }, { type: "text", text: "alpha", at: now - 1000 }, { type: "text", text: "beta", at: now - 2000 }]
    check("default left click action is paste", clip.clickAction === "paste", clip.clickAction)
    reopen()
    check("no Hyprland offscreen: nothing captured on open", clip.pasteTarget === "", clip.pasteTarget)
    clip.pasteTarget = "55aa01"   // what Hyprland.activeToplevel.address gives on open
    act(function() { clip.clickIndex(rowOf("alpha")) })
    check("left click closes the popup", clip.opened === false)
  }
  function step2() {
    check("left click pastes into the window from before the popup", JSON.stringify(added()) === JSON.stringify(["paste " + hiOf("alpha") + " 55aa01"]), added())
    reopen()
    check("reopening captures again (no stale window)", clip.pasteTarget === "", clip.pasteTarget)
    act(function() { clip.clickIndex(rowOf("beta")) })
  }
  function step3() {
    check("without a window address: plain paste as before", JSON.stringify(added()) === JSON.stringify(["paste " + hiOf("beta")]), added())
    clip.setClickAction("copy")
    reopen()
    clip.pasteTarget = "55aa01"
    act(function() { clip.clickIndex(rowOf("alpha")) })
    check("'Select (copy only)' keeps the popup open", clip.opened === true)
  }
  function step4() {
    // ("copy 0" may follow: the open's own "put the top pin on an empty clipboard".)
    var a = added()
    check("'Select (copy only)' copies, no paste, no window", a[0] === "copy " + hiOf("alpha") && !a.some(function(l) { return l.indexOf("paste") === 0 }), a)
    clip.setClickAction("paste")
    act(function() { clip.activateSlot(2) })
  }
  function step5() {
    check("Alt+Shift+2 in the popup pastes into that window too", JSON.stringify(added()) === JSON.stringify(["paste " + hiOf("alpha") + " 55aa01"]), added())
    check("helperArgs: Markdown paste gets the window", JSON.stringify(clip.helperArgs("paste-md", 3).slice(1)) === '["paste-md","3","55aa01"]')
    check("helperArgs: send / open / copy do not", JSON.stringify([clip.helperArgs("send", 1).length, clip.helperArgs("open", 1).length, clip.helperArgs("copy", 1).length]) === "[3,3,3]")
  }
}
