// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_feedback.qml
// Settings > Feedback (1.30.0): the field's keys, same handler as
// Clipboard.qml: Enter (and Ctrl+Enter) sends, Shift+Enter is a new line.
// No GitHub fallback any more; sending is replaced by a counter here.
import QtQuick
import QtTest
import "../ClipboardHistory.js" as ClipboardHistory

Item {
  id: root
  width: 400; height: 200
  property var sent: []
  function sendFeedback(input) {
    var t = input.text.trim()
    if (t === "") return false
    root.sent.push(t)
    input.text = ""
    return true
  }
  TextEdit {
    id: input
    anchors.fill: parent
    focus: true
    Keys.onPressed: function(event) {
      var k = ClipboardHistory.feedbackKey(event.key, event.modifiers & Qt.ShiftModifier, event.modifiers & Qt.ControlModifier)
      if (k === "send") { root.sendFeedback(input); event.accepted = true }
      else if (k === "newline") { input.insert(input.cursorPosition, "\n"); event.accepted = true }
    }
  }
  TestCase {
    name: "Feedback"
    when: windowShown
    function test_keys() {
      root.sent = []
      input.text = ""
      input.forceActiveFocus()
      keyClick(Qt.Key_Return)
      compare(root.sent.length, 0, "empty text is not sent")
      keyClick("h"); keyClick("i")
      keyClick(Qt.Key_Return, Qt.ShiftModifier)
      compare(root.sent.length, 0, "Shift+Enter does not send")
      keyClick("x")
      compare(input.text, "hi\nx", "Shift+Enter is a new line")
      keyClick(Qt.Key_Return)
      compare(root.sent.length, 1, "Enter sends")
      compare(root.sent[0], "hi\nx")
      compare(input.text, "")
      keyClick("y"); keyClick(Qt.Key_Enter)
      compare(root.sent.length, 2, "keypad Enter sends")
      keyClick("z"); keyClick(Qt.Key_Return, Qt.ControlModifier)
      compare(root.sent.length, 3, "Ctrl+Enter still sends")
    }
  }
}
