pragma ComponentBehavior: Bound

import QtQuick
import qs.Ui
import qs.Commons
import "../controls"
import "../Presentation.js" as Presentation

Column {
  id: root
  required property PluginBarApi bar
  required property var controls
  required property bool interactive
  property bool hasCursor: false
  property int cursorIndex: -1
  readonly property var spacingTokens: Style.spacing
  signal powerRequested(int zone, string field, bool value)
  signal focusRequested(int index)
  visible: controls.length > 0
  spacing: Style.space(6)

  function activate(index) {
    if (index < 0 || index >= root.controls.length) return
    var control = root.controls[index]
    root.powerRequested(control.zone, control.field, !control.value)
  }

  PanelSectionHeader {
    text: "LIGHTING POWER"
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
  }
  Grid {
    id: grid
    width: parent.width
    columns: 2
    spacing: root.spacingTokens.xs
    readonly property real cellWidth: (width - spacing * (columns - 1)) / columns
    Repeater {
      model: root.controls
      OptionPill {
        required property var modelData
        required property int index
        bar: root.bar
        width: grid.cellWidth
        active: modelData.value
        text: modelData.label
        tooltipText: Presentation.powerTooltip(modelData)
        enabled: root.interactive
        hasCursor: root.hasCursor && root.cursorIndex === index
        onClicked: root.activate(index)
        onHovered: function(hovered) { if (hovered) root.focusRequested(index) }
      }
    }
  }
}
