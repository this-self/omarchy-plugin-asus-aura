pragma ComponentBehavior: Bound

import QtQuick
import qs.Ui
import qs.Commons
import "../controls"
import "../../app/ColourMath.js" as Colour

Column {
  id: root
  required property PluginBarApi bar
  required property var colour
  required property int colourCount
  required property int selectedSlot
  required property real hue
  required property real saturation
  property bool cursorActive: false
  property string cursorSection: ""
  property int cursorIndex: -1
  readonly property var fontTokens: Style.font
  readonly property var spacingTokens: Style.spacing
  readonly property int hueStep: 10
  readonly property int saturationStep: 5
  readonly property var navigationSections: {
    if (!root.visible) return []
    var sections = []
    if (root.colourCount >= 2) sections.push({id: "colourTarget", count: 2})
    return sections.concat([{id: "hue", slider: true}, {id: "saturation", slider: true}])
  }
  signal slotRequested(int slot)
  signal channelRequested(string channel, real value)
  signal hueSaturationRequested(real hue, real saturation)
  signal focusRequested(string section, int index)
  spacing: Style.space(10)

  function adjust(section, delta) {
    if (section === "hue") root.hueSaturationRequested(root.hue + delta * root.hueStep, root.saturation)
    else if (section === "saturation") root.hueSaturationRequested(root.hue, root.saturation + delta * root.saturationStep / 100)
  }

  Item {
    width: parent.width
    implicitHeight: Math.max(header.implicitHeight, hexLabel.implicitHeight)
    PanelSectionHeader {
      id: header
      text: "COLOUR"
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      id: hexLabel
      textFormat: Text.PlainText
      text: Colour.hex(root.colour).toUpperCase()
      color: Qt.darker(root.bar.foreground, 1.4)
      font.family: root.bar.fontFamily
      font.pixelSize: root.fontTokens.caption
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
    }
  }
  Grid {
    id: slots
    visible: root.colourCount >= 2
    width: parent.width
    columns: 2
    spacing: root.spacingTokens.xs
    readonly property real cellWidth: (width - spacing) / 2
    Repeater {
      model: 2
      OptionPill {
        required property int index
        bar: root.bar
        width: slots.cellWidth
        active: root.selectedSlot === index + 1
        text: "Colour " + (index + 1)
        tooltipText: "Hue, saturation and RGB sliders edit the " + (index === 0 ? "first" : "second") + " effect colour."
        hasCursor: root.cursorActive && root.cursorSection === "colourTarget" && root.cursorIndex === index
        onClicked: root.slotRequested(index + 1)
        onHovered: function(hovered) { if (hovered) root.focusRequested("colourTarget", index) }
      }
    }
  }
  SpectrumSlider {
    bar: root.bar
    width: parent.width
    label: "HUE"
    valueText: Math.round(liveValue) + "°"
    maximum: 359
    step: root.hueStep
    value: root.hue
    knobColor: Colour.hsvHex(liveValue, 1, 1)
    hasCursor: root.cursorActive && root.cursorSection === "hue"
    trackGradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0 / 6; color: "#ff0000" }
      GradientStop { position: 1 / 6; color: "#ffff00" }
      GradientStop { position: 2 / 6; color: "#00ff00" }
      GradientStop { position: 3 / 6; color: "#00ffff" }
      GradientStop { position: 4 / 6; color: "#0000ff" }
      GradientStop { position: 5 / 6; color: "#ff00ff" }
      GradientStop { position: 1; color: "#ff0000" }
    }
    onValueRequested: function(v) { root.hueSaturationRequested(v, root.saturation) }
    onFocusRequested: root.focusRequested("hue", -1)
  }
  SpectrumSlider {
    bar: root.bar
    width: parent.width
    label: "SATURATION"
    valueText: Math.round(liveValue) + "%"
    maximum: 100
    step: root.saturationStep
    value: Math.round(root.saturation * 100)
    knobColor: Colour.hsvHex(root.hue, liveValue / 100, 1)
    hasCursor: root.cursorActive && root.cursorSection === "saturation"
    trackGradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: "#ffffff" }
      GradientStop { position: 1; color: Colour.hsvHex(root.hue, 1, 1) }
    }
    onValueRequested: function(v) { root.hueSaturationRequested(root.hue, v / 100) }
    onFocusRequested: root.focusRequested("saturation", -1)
  }
  Item { width: 1; height: Style.space(2) }
  ChannelSlider {
    bar: root.bar; width: parent.width; label: "RED"; amount: root.colour.red
    onValueRequested: function(v) { root.channelRequested("red", v) }
  }
  ChannelSlider {
    bar: root.bar; width: parent.width; label: "GREEN"; amount: root.colour.green
    onValueRequested: function(v) { root.channelRequested("green", v) }
  }
  ChannelSlider {
    bar: root.bar; width: parent.width; label: "BLUE"; amount: root.colour.blue
    onValueRequested: function(v) { root.channelRequested("blue", v) }
  }
}
