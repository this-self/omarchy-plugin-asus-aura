import QtQuick
import qs.Ui
import qs.Commons

Column {
  id: root
  required property PluginBarApi bar
  required property string label
  required property int amount
  readonly property var fontTokens: Style.font
  signal valueRequested(real value)
  spacing: Style.space(2)

  Item {
    width: parent.width
    implicitHeight: Math.max(channelLabel.implicitHeight, channelValue.implicitHeight)
    Text {
      id: channelLabel
      text: root.label
      color: Qt.darker(root.bar.foreground, 1.4)
      font.family: root.bar.fontFamily
      font.pixelSize: root.fontTokens.caption
      font.bold: true
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      id: channelValue
      text: String(root.amount)
      color: Qt.darker(root.bar.foreground, 1.4)
      font.family: root.bar.fontFamily
      font.pixelSize: root.fontTokens.caption
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
    }
  }
  PanelSlider {
    bar: root.bar
    width: parent.width
    minimum: 0
    maximum: 255
    step: 1
    integer: true
    value: root.amount
    onMoved: function(v) { root.valueRequested(v) }
    onReleased: function(v) { root.valueRequested(v) }
  }
}
