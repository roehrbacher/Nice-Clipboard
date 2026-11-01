// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_feedback.qml
// Settings > Feedback (1.24.0): the issue URL Clipboard.qml builds, and the
// field's keys (Ctrl+Enter sends, plain Enter is a new line). Same logic as
// feedbackUrl() / sendFeedback() there; xdg-open is replaced by a counter.
import QtQuick
import QtTest

Item {
  id: root
  width: 400; height: 200
  property var opened: []
  readonly property string feedbackRepo: "roehrbacher/Nice-Clipboard"
  function feedbackUrl(text) {
    var t = String(text || "").trim()
    var first = t.split("\n")[0]
    var title = "Feedback: " + (first.length > 60 ? first.slice(0, 57) + "..." : first)
    var body = t + "\n\n---\nSent from Nice Clipboard settings (1.24.0)"
    return "https://github.com/" + root.feedbackRepo + "/issues/new?labels=feedback&title="
      + encodeURIComponent(title) + "&body=" + encodeURIComponent(body)
  }
  function sendFeedback() {
    var t = input.text.trim()
    if (t === "") return false
    root.opened.push(root.feedbackUrl(t))
    input.text = ""
    return true
  }
  TextEdit {
    id: input
    anchors.fill: parent
    focus: true
    Keys.onPressed: function(event) {
      if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) { root.sendFeedback(); event.accepted = true }
    }
  }
  TestCase {
    name: "Feedback"
    when: windowShown
    function test_url() {
      var u = root.feedbackUrl("Pin & search: ä?\nsecond line")
      verify(u.indexOf("https://github.com/roehrbacher/Nice-Clipboard/issues/new?labels=feedback&title=") === 0)
      compare(decodeURIComponent(u.split("&title=")[1].split("&body=")[0]), "Feedback: Pin & search: ä?")
      verify(decodeURIComponent(u.split("&body=")[1]).indexOf("second line") > 0)
      verify(root.feedbackUrl("x".repeat(100)).indexOf("...") > 0)
    }
    function test_keys() {
      root.opened = []
      compare(root.sendFeedback(), false)
      input.forceActiveFocus()
      keyClick("h"); keyClick("i"); keyClick(Qt.Key_Return)
      compare(root.opened.length, 0)
      keyClick(Qt.Key_Return, Qt.ControlModifier)
      compare(root.opened.length, 1)
      compare(input.text, "")
    }
  }
}
