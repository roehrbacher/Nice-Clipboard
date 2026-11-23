import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Window
import qs.Commons
// 1.33.5 on the real Clipboard.qml (stub clipboard.sh that only logs):
// Ctrl+Z after unpin / pin / delete is one clean change on screen.
// Every frame drawn after the action must already show the final list
// (row order, positions, highlighted row, scroll), the row that changes
// pin keeps its on-screen row (moved, not removed and made again), and the
// list does not scroll. Checked at the top of the list and scrolled.
// Prints "V1335 PASS ..." / "V1335 FAIL ...".
ShellRoot {
  id: shell
  property var clip: null
  property var list: null
  property int fails: 0
  property string phase: ""
  property var frames: []
  property var ops: ({ insert: 0, remove: 0, move: 0 })
  function check(name, ok, got) { if (!ok) shell.fails++; console.log("V1335 " + (ok ? "PASS " : "FAIL ") + name + (got !== undefined ? "  [" + got + "]" : "")) }
  function find(item, name, out) {
    if (!item) return
    if (item.objectName === name && out.indexOf(item) < 0) out.push(item)
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) find(kids[i], name, out)
    if (item.contentItem && item.contentItem !== item) find(item.contentItem, name, out)
  }
  function one(name) { var o = []; find(clip, name, o); return o[0] }
  function rowOf(text) { for (var i = 0; i < clip.displayModelCount(); i++) if (clip.displayRow(i).fullText === text) return i; return -1 }
  function itemOf(text) { var i = rowOf(text); return i < 0 ? null : list.itemAtIndex(i) }
  function key(code, mods) { var e = { key: code, nativeScanCode: 0, modifiers: mods, text: "", accepted: false }; clip.handleSearchKey(e); return e.accepted }
  // What is on screen: scroll, and each row in view with its y and highlight.
  function layout() {
    var o = []
    for (var i = 0; i < clip.displayModelCount(); i++) {
      var it = list.itemAtIndex(i)
      if (!it) continue
      var y = Math.round(it.y - list.contentY)
      if (y + it.height < 0 || y > list.height) continue
      var r = clip.displayRow(i)
      o.push((r.pinned ? "*" : "") + r.fullText + "@" + y + (it.hasCursor ? "#" : ""))
    }
    return "cy=" + Math.round(list.contentY) + " " + o.join(" ")
  }
  Window { id: win; width: 462; height: 700; visible: true; color: "black"
    Rectangle { anchors.fill: parent; color: Color.popups.background }
    onFrameSwapped: if (shell.phase) shell.frames.push(shell.layout())
  }
  Connections {
    target: shell.clip ? shell.clip.displayModelRef() : null
    function onRowsInserted() { if (shell.phase) shell.ops.insert++ }
    function onRowsRemoved() { if (shell.phase) shell.ops.remove++ }
    function onRowsMoved() { if (shell.phase) shell.ops.move++ }
  }
  Component.onCompleted: {
    var c = Qt.createComponent("clip/Clipboard.qml")
    if (c.status !== Component.Ready) { console.log("V1335 ERR " + c.errorString()); Qt.quit(); return }
    clip = c.createObject(win.contentItem, {})
    list = one("resultList")
    tStart.start()
  }
  Timer { id: tStart; interval: 2500; onTriggered: shell.next() }
  Timer { id: tSettle; interval: 600; onTriggered: shell.finish() }
  property var pending: null
  property int stepNo: 0
  function setHistory(pins, rows) {
    var now = Date.now(), h = []
    for (var i = 0; i < pins; i++) h.push({ type: "text", text: "pin " + (i + 1), pinned: true, at: now - 100 - i })
    for (var j = 0; j < rows; j++) h.push({ type: "text", text: "item " + (j + 1), at: now - 1000 - j * 10 })
    clip.history = h
    clip.close(); clip.open("{}"); clip.rebuildDisplay(false)
  }
  // act(name, fn, expect): runs fn, then after 600 ms checks the frames.
  function act(name, fn, expect) {
    shell.frames = []; shell.ops = { insert: 0, remove: 0, move: 0 }
    shell.pending = { name: name, expect: expect, before: layout(), item: expect.row ? itemOf(expect.row) : null }
    shell.phase = name
    fn()
    tSettle.start()
  }
  function finish() {
    var p = shell.pending
    shell.phase = ""
    var fin = layout()
    var odd = shell.frames.filter(function(f) { return f !== fin })
    check(p.name + ": every frame shows the final list (" + shell.frames.length + " frames)", odd.length === 0, odd.length ? "first odd frame: " + odd[0] + " | final: " + fin : fin)
    if (p.expect.moveOnly) check(p.name + ": the row is moved, not removed and made again", shell.ops.insert === 0 && shell.ops.remove === 0 && p.item !== null && itemOf(p.expect.row) === p.item, JSON.stringify(shell.ops))
    if (p.expect.insertOnly) check(p.name + ": one row comes back, nothing else is redrawn from scratch", shell.ops.insert === 1 && shell.ops.remove === 0, JSON.stringify(shell.ops))
    if (p.expect.sameScroll !== undefined) check(p.name + ": the list does not scroll", Math.round(list.contentY) === p.expect.sameScroll, Math.round(list.contentY))
    if (p.expect.cursor) check(p.name + ": the highlight is on " + p.expect.cursor, fin.indexOf(" " + (p.expect.cursorPinned ? "*" : "") + p.expect.cursor + "@") >= 0 && /#/.test(fin.split(p.expect.cursor + "@")[1].split(" ")[0]), fin)
    tNextStep.start()
  }
  Timer { id: tNextStep; interval: 300; onTriggered: shell.next() }
  function next() {
    var z = function() { key(Qt.Key_Z, Qt.ControlModifier) }
    var steps = [
      function() { setHistory(3, 4); tNextStep.start() },
      function() { act("top: unpin", function() { clip.togglePinDisplayIndex(rowOf("pin 2")) }, { row: "pin 2", moveOnly: true, sameScroll: 0 }) },
      function() { act("top: Ctrl+Z after unpin", z, { row: "pin 2", moveOnly: true, sameScroll: 0, cursor: "pin 2", cursorPinned: true }) },
      function() { act("top: pin", function() { clip.togglePinDisplayIndex(rowOf("item 2")) }, { row: "item 2", moveOnly: true, sameScroll: 0 }) },
      function() { act("top: Ctrl+Z after pin", z, { row: "item 2", moveOnly: true, sameScroll: 0, cursor: "item 2" }) },
      function() { act("top: delete", function() { clip.requestDelete(rowOf("item 3")) }, { sameScroll: 0 }) },
      function() { act("top: Ctrl+Z after delete", z, { insertOnly: true, sameScroll: 0, cursor: "item 3" }) },
      // Scrolled: a long Pinned list, the view on its end and the start of History.
      function() { setHistory(12, 30); tNextStep.start() },
      function() { list.positionViewAtIndex(rowOf("pin 6"), ListView.Beginning); shell.scrolled = Math.round(list.contentY); tNextStep.start() },
      function() { act("scrolled: unpin", function() { clip.togglePinDisplayIndex(rowOf("pin 10")) }, { row: "pin 10", moveOnly: true, sameScroll: shell.scrolled }) },
      function() { act("scrolled: Ctrl+Z after unpin", z, { row: "pin 10", moveOnly: true, sameScroll: shell.scrolled, cursor: "pin 10", cursorPinned: true }) },
      function() { act("scrolled: pin", function() { clip.togglePinDisplayIndex(rowOf("item 2")) }, { row: "item 2", moveOnly: true, sameScroll: shell.scrolled }) },
      function() { act("scrolled: Ctrl+Z after pin", z, { row: "item 2", moveOnly: true, sameScroll: shell.scrolled, cursor: "item 2" }) },
      function() { act("scrolled: delete", function() { clip.requestDelete(rowOf("item 1")) }, { sameScroll: shell.scrolled }) },
      function() { act("scrolled: Ctrl+Z after delete", z, { insertOnly: true, sameScroll: shell.scrolled, cursor: "item 1" }) }
    ]
    if (shell.stepNo >= steps.length) { console.log("V1335 done fails=" + shell.fails); Qt.quit(); return }
    steps[shell.stepNo++]()
  }
  property int scrolled: 0
}
