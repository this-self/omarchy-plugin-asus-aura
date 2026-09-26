import QtQuick
import qs.Ui
import qs.Commons
import "../Presentation.js" as Presentation

Column {
  id: root
  required property PluginBarApi bar
  required property int level
  required property int maximum
  required property bool interactive
  property bool hasCursor: false
  readonly property var fontTokens: Style.font
  readonly property var spacingTokens: Style.spacing
  signal levelRequested(int value)
  signal toggleRequested()
  signal focusRequested()
  spacing: Style.space(6)

  Item {
    width: parent.width
    implicitHeight: Math.max(header.implicitHeight, valueLabel.implicitHeight)
    PanelSectionHeader {
      id: header
      text: "BRIGHTNESS"
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      id: valueLabel
      readonly property int level: slider.dragging ? Math.round(slider.liveValue) : root.level
      textFormat: Text.PlainText
      text: Presentation.levelName(level, root.maximum) + "  " + level + "/" + root.maximum
      color: Qt.darker(root.bar.foreground, 1.4)
      font.family: root.bar.fontFamily
      font.pixelSize: root.fontTokens.caption
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
    }
  }
  CursorSurface {
    width: parent.width
    height: slider.implicitHeight + root.spacingTokens.controlGap
    hasCursor: root.hasCursor
    foreground: root.bar.foreground
    outline: true
    PanelSlider {
      id: slider
      enabled: root.interactive
      bar: root.bar
      anchors.fill: parent
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      minimum: 0
      maximum: root.maximum
      step: 1
      integer: true
      tickCount: root.maximum + 1
      value: root.level
      onMoved: function(v) { root.levelRequested(v) }
      onReleased: function(v) { root.levelRequested(v) }
      onRightClicked: root.toggleRequested()
    }
    HoverHandler {
      onHoveredChanged: if (hovered) root.focusRequested()
    }
  }
}
