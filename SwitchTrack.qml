import QtQuick
import qs.Commons

// The small on/off switch (footer Incognito, OCR "in use"): accent track and
// a knob that slides right when on. Clicks are handled by the parent.
Rectangle {
  id: track
  property bool on: false
  property color accent: "white"
  property color foreground: "white"
  property color background: "black"

  width: Math.round(Style.font.body * 2.2)
  height: Math.round(Style.font.body * 1.2)
  radius: height / 2
  color: on ? accent : Util.alpha(foreground, 0.22)

  Rectangle {
    width: track.height - Style.space(4)
    height: width
    radius: width / 2
    y: Style.space(2)
    x: track.on ? track.width - width - Style.space(2) : Style.space(2)
    color: track.on ? track.background : track.foreground
    Behavior on x { NumberAnimation { duration: 120 } }
  }
}
