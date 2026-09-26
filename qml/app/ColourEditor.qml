import QtQuick
import "ColourMath.js" as Colour

// Session editing state, not hardware state. This survives closing the popup.
QtObject {
  id: root
  property var colour1: ({red: 0, green: 0, blue: 0})
  property var colour2: ({red: 0, green: 0, blue: 0})
  property int colourCount: 0
  property int selectedSlot: 1
  property real hue: 0
  property real saturation: 0
  readonly property int effectiveSlot: colourCount >= 2 && selectedSlot === 2 ? 2 : 1
  readonly property var colour: effectiveSlot === 2 ? colour2 : colour1

  onColourCountChanged: if (colourCount < 2) selectedSlot = 1
  onColourChanged: syncFromColour()

  function selectSlot(slot) {
    if (slot !== 1 && (slot !== 2 || root.colourCount < 2)) return false
    root.selectedSlot = slot
    return true
  }

  function syncFromColour() {
    var hsv = Colour.rgbToHsv(root.colour)
    var previous = Colour.hsvToRgb(root.hue, root.saturation, hsv.v)
    if (previous.red === root.colour.red && previous.green === root.colour.green && previous.blue === root.colour.blue) return
    root.saturation = hsv.s
    if (hsv.s > 0) root.hue = hsv.h
  }

  function withChannel(channel, value) {
    if (["red", "green", "blue"].indexOf(channel) < 0 || !isFinite(value)) return null
    var next = Object.assign({}, root.colour)
    next[channel] = Math.max(0, Math.min(255, Math.round(value)))
    return next
  }

  function atHueSaturation(hue, saturation) {
    var c = root.colour
    var value = Math.max(c.red, c.green, c.blue) / 255
    // Black has no hue to edit, so it starts at full value.
    return Colour.hsvToRgb(hue, saturation, value > 0 ? value : 1)
  }

  function remember(hue, saturation) {
    root.hue = hue
    root.saturation = saturation
  }
}
