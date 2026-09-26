import QtQuick
import qs.Ui
import qs.Commons
import "Presentation.js" as Presentation

BarIconButton {
  id: root
  required property bool available
  required property int level
  required property int maximum
  required property string modeName
  property real wheelAccumulator: 0
  signal togglePanelRequested()
  signal toggleBacklightRequested()
  signal brightnessAdjustmentRequested(int delta)
  text: "󰌌"
  tooltipText: root.available
    ? "ASUS Aura — " + Presentation.levelName(root.level, root.maximum) + " · " + root.modeName
      + "\nScroll to adjust brightness. Right-click to turn off/restore."
    : "ASUS Aura — service unavailable"
  onPressed: function(button) {
    if (button === Qt.RightButton) root.toggleBacklightRequested()
    else root.togglePanelRequested()
  }
  onWheelMoved: function(delta) {
    var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
    root.wheelAccumulator = wheel.remainder
    if (wheel.steps !== 0) root.brightnessAdjustmentRequested(wheel.steps)
  }
}
