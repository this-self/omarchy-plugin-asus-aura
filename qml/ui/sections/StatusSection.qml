import QtQuick
import qs.Ui
import qs.Commons
import "../controls"

Column {
  id: root
  required property PluginBarApi bar
  required property string subtitle
  required property string errorMessage
  required property bool canResync
  required property bool resyncing
  required property string resyncStatus
  property bool hasCursor: false
  readonly property var fontTokens: Style.font
  readonly property var spacingTokens: Style.spacing
  signal resyncRequested()
  signal focusRequested()
  spacing: Style.space(14)

  Item {
    width: parent.width
    implicitHeight: Math.max(icon.implicitHeight, labels.implicitHeight, resyncButton.height)
    Text {
      id: icon
      textFormat: Text.PlainText
      text: "󰌌"
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: root.fontTokens.display
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }
    Column {
      id: labels
      anchors.left: icon.right
      anchors.leftMargin: Style.space(14)
      anchors.right: resyncButton.left
      anchors.rightMargin: root.spacingTokens.sm
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text {
        text: "ASUS Aura Lighting"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: root.fontTokens.title
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }
      Text {
        textFormat: Text.PlainText
        text: root.subtitle.toUpperCase()
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: root.fontTokens.caption
        font.bold: true
        font.letterSpacing: 1.2
        elide: Text.ElideRight
        width: parent.width
      }
    }
    OptionPill {
      id: resyncButton
      bar: root.bar
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(implicitWidth, implicitHeight)
      height: width
      bordered: false
      enabled: root.canResync
      iconText: "󰑓"
      iconSpinning: root.resyncing
      hasCursor: root.hasCursor
      tooltipText: "Re-send saved lighting settings; keep brightness, including Off."
        + (root.resyncStatus ? "\n" + root.resyncStatus : "")
      Accessible.name: "Resync lighting"
      onClicked: root.resyncRequested()
      onHovered: function(hovered) { if (hovered) root.focusRequested() }
    }
  }
  Text {
    visible: !!root.errorMessage
    width: parent.width
    text: root.errorMessage
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: root.fontTokens.caption
  }
}
