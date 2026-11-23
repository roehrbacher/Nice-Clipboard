import Quickshell
import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui
// 1.34.0 on the real Clipboard.qml: the update check is on by default.
// No saved state, and a pre-1.34 state.json (which always saved
// "updateCheck": false) -> on. A choice made in Settings
// ("updateCheckSet": true) is kept, off or on. Opening the popup runs the
// (stub) update check once; a second open the same day does not.
ShellRoot {
  id: shell
  property var clip: null
  Window { id: win; width: 462; height: 700; visible: true; color: "black" }
  Component.onCompleted: {
    var c = Qt.createComponent("clip/Clipboard.qml")
    if (c.status !== Component.Ready) { console.log("V134 ERR " + c.errorString()); Qt.quit(); return }
    clip = c.createObject(win.contentItem, {})
    t1.start()
  }
  Timer { id: t1; interval: 2500; onTriggered: shell.step1() }
  Timer { id: t2; interval: 1500; onTriggered: shell.step2() }
  Timer { id: tEnd; interval: 800; onTriggered: { console.log("V134 done"); Qt.quit() } }
  function show(label, raw) {
    clip.loadState(raw)
    console.log("V134 " + label + ": updateCheck=" + clip.updateCheck + " set=" + clip.updateCheckSet)
  }
  function step1() {
    console.log("V134 fresh install: updateCheck=" + clip.updateCheck + " set=" + clip.updateCheckSet)
    show("empty state", "{}")
    show("pre-1.34 state (false saved)", '{"private":false,"updateCheck":false}')
    show("chosen off", '{"updateCheck":false,"updateCheckSet":true}')
    show("chosen on", '{"updateCheck":true,"updateCheckSet":true}')
    show("pre-1.34 state again", '{"private":false,"updateCheck":false,"updateLastCheck":0}')
    clip.open("{}")
    clip.close()
    clip.open("{}")
    t2.start()
  }
  function step2() {
    console.log("V134 after 2 opens: latest=" + clip.updateLatest + " available=" + clip.updateAvailable + " lastCheck>0=" + (clip.updateLastCheck > 0))
    clip.close()
    clip.runSettingsAction("updateCheck")
    console.log("V134 switched off in Settings: updateCheck=" + clip.updateCheck + " set=" + clip.updateCheckSet)
    tEnd.start()
  }
}
