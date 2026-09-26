import QtQuick
import qs.Ui
import qs.Commons

// A styled button. Focus and activation are supplied by its owning section.
Button {
  id: root
  required property PluginBarApi bar
  readonly property var fontTokens: Style.font
  readonly property var spacingTokens: Style.spacing
  fontSize: root.fontTokens.caption
  foreground: root.bar.foreground
  fontFamily: root.bar.fontFamily
  horizontalPadding: root.spacingTokens.sm
  verticalPadding: root.spacingTokens.controlPaddingY
  bordered: true
  Accessible.role: Accessible.Button
  Accessible.name: root.text
  Accessible.description: root.tooltipText
}
