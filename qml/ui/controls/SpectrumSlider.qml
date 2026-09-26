import QtQuick
import qs.Ui
import qs.Commons

// Gradient slider with drag-local state. It has no colour model or navigation
// dependency: consumers provide a gradient/value and handle semantic signals.
Column {
  id: root
  required property PluginBarApi bar
  required property string label
  required property string valueText
  required property real value
  required property real maximum
  required property int step
  required property color knobColor
  required property Gradient trackGradient
  property bool hasCursor: false
  property real liveValue: value
  property bool dragging: false
  property real wheelAccumulator: 0
  readonly property var fontTokens: Style.font
  readonly property var spacingTokens: Style.spacing
  readonly property real knobSize: Style.space(22)
  readonly property real progress: Math.max(0, Math.min(1, liveValue / Math.max(1, maximum)))
  signal valueRequested(real value)
  signal focusRequested()

  spacing: Style.space(2)
  onValueChanged: if (!dragging) liveValue = value

  function setLive(value) {
    var next = Math.max(0, Math.min(root.maximum, Math.round(value)))
    root.liveValue = next
    root.valueRequested(next)
  }

  Item {
    width: parent.width
    implicitHeight: Math.max(sliderLabel.implicitHeight, sliderValue.implicitHeight)
    Text {
      id: sliderLabel
      text: root.label
      color: Qt.darker(root.bar.foreground, 1.4)
      font.family: root.bar.fontFamily
      font.pixelSize: root.fontTokens.caption
      font.bold: true
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      id: sliderValue
      text: root.valueText
      color: Qt.darker(root.bar.foreground, 1.4)
      font.family: root.bar.fontFamily
      font.pixelSize: root.fontTokens.caption
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  CursorSurface {
    width: parent.width
    height: root.knobSize + root.spacingTokens.controlGap
    hasCursor: root.hasCursor
    foreground: root.bar.foreground
    outline: true
    Accessible.role: Accessible.Slider
    Accessible.name: root.label
    Accessible.description: root.valueText

    Item {
      id: trackArea
      anchors.fill: parent
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(14)
        radius: height / 2
        gradient: root.trackGradient
      }
      Rectangle {
        anchors.fill: track
        radius: track.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.35)
      }
      // Background ring keeps the knob distinct from the spectrum beneath it.
      Rectangle {
        width: root.knobSize + Style.space(2)
        height: width
        radius: width / 2
        color: root.bar.background
        anchors.centerIn: knob
        scale: knob.scale
      }
      Rectangle {
        id: knob
        width: root.knobSize
        height: width
        radius: width / 2
        color: root.knobColor
        border.width: Style.space(3)
        border.color: root.bar.foreground
        anchors.verticalCenter: track.verticalCenter
        x: (trackArea.width - width) * root.progress
        scale: mouseArea.containsMouse || root.dragging ? 1.1 : 1.0
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
      }
      MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        function valueFromX(x) {
          var span = Math.max(1, width - root.knobSize)
          return (x - root.knobSize / 2) / span * root.maximum
        }
        onEntered: root.focusRequested()
        onPressed: function(mouse) {
          root.dragging = true
          root.setLive(valueFromX(mouse.x))
        }
        onPositionChanged: function(mouse) { if (root.dragging) root.setLive(valueFromX(mouse.x)) }
        onReleased: { root.dragging = false; root.liveValue = root.value }
        onCanceled: { root.dragging = false; root.liveValue = root.value }
        onWheel: function(wheel) {
          var steps = Util.wheelSteps(root.wheelAccumulator, wheel.angleDelta.y)
          root.wheelAccumulator = steps.remainder
          if (steps.steps !== 0) root.setLive(root.liveValue + steps.steps * root.step)
        }
      }
    }
  }
}
