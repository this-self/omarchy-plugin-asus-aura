pragma ComponentBehavior: Bound

import QtQuick
import qs.Ui
import qs.Commons
import "../controls"
import "../Presentation.js" as Presentation

// The effect workflow stays together: load saved mode, explicitly replace
// zones, then edit only the parameters supported by that mode.
Column {
  id: root
  required property PluginBarApi bar
  required property var effects
  required property var currentMode
  required property var effect
  required property bool available
  required property bool editable
  required property bool canReplaceZones
  required property string zoneState
  required property var colour
  required property int selectedSlot
  required property real hue
  required property real saturation
  property bool cursorActive: false
  property string cursorSection: ""
  property int cursorIndex: -1
  readonly property var spacingTokens: Style.spacing
  readonly property var navigationSections: {
    var sections = [{id: "effect", count: root.effects.length}]
    if (replaceButton.visible) sections.push({id: "global", count: 1})
    sections = sections.concat(colourSection.navigationSections)
    if (speedSection.visible) sections.push({id: "speed", count: root.currentMode.speeds.length})
    if (directionSection.visible) sections.push({id: "direction", count: root.currentMode.directions.length})
    return sections
  }
  signal modeRequested(int mode)
  signal replaceZonesRequested()
  signal colourSlotRequested(int slot)
  signal channelRequested(string channel, real value)
  signal hueSaturationRequested(real hue, real saturation)
  signal speedRequested(string speed)
  signal directionRequested(string direction)
  signal focusRequested(string section, int index)
  spacing: Style.space(14)

  function focused(section, index) {
    return root.cursorActive && root.cursorSection === section && root.cursorIndex === index
  }
  function adjust(section, delta) { colourSection.adjust(section, delta) }
  function activate(section, index) {
    if (section === "effect" && index >= 0 && index < root.effects.length) root.modeRequested(root.effects[index].id)
    else if (section === "global") root.replaceZonesRequested()
    else if (section === "colourTarget" && index >= 0 && index < 2) root.colourSlotRequested(index + 1)
    else if (section === "speed" && index >= 0 && index < root.currentMode.speeds.length) root.speedRequested(root.currentMode.speeds[index])
    else if (section === "direction" && index >= 0 && index < root.currentMode.directions.length) root.directionRequested(root.currentMode.directions[index])
  }

  Column {
    width: parent.width
    spacing: Style.space(10)
    PanelSectionHeader {
      text: "EFFECT"
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
    }
    Grid {
      id: modes
      width: parent.width
      columns: 3
      spacing: root.spacingTokens.xs
      readonly property real cellWidth: (width - spacing * (columns - 1)) / columns
      Repeater {
        model: root.effects
        OptionPill {
          required property var modelData
          required property int index
          bar: root.bar
          width: modes.cellWidth
          active: root.currentMode.id === modelData.id
          text: modelData.name
          tooltipText: Presentation.effectTooltip(modelData, root.zoneState)
          enabled: root.available
          hasCursor: root.focused("effect", index)
          onClicked: root.modeRequested(modelData.id)
          onHovered: function(hovered) { if (hovered) root.focusRequested("effect", index) }
        }
      }
    }
  }
  OptionPill {
    id: replaceButton
    bar: root.bar
    visible: root.zoneState === "zoned"
    width: parent.width
    enabled: root.canReplaceZones
    hasCursor: root.focused("global", 0)
    text: "Replace zones"
    tooltipText: "Replace active zoned lighting with the saved global effect.\nEnables colour, speed and direction editing; keeps brightness."
    onClicked: root.replaceZonesRequested()
    onHovered: function(hovered) { if (hovered) root.focusRequested("global", 0) }
  }
  PanelSeparator { visible: colourSection.visible; foreground: root.bar.foreground }
  ColourSection {
    id: colourSection
    bar: root.bar
    visible: root.editable && root.currentMode.colourCount >= 1
    width: parent.width
    colour: root.colour
    colourCount: root.currentMode.colourCount
    selectedSlot: root.selectedSlot
    hue: root.hue
    saturation: root.saturation
    cursorActive: root.cursorActive
    cursorSection: root.cursorSection
    cursorIndex: root.cursorIndex
    onSlotRequested: function(slot) { root.colourSlotRequested(slot) }
    onChannelRequested: function(channel, value) { root.channelRequested(channel, value) }
    onHueSaturationRequested: function(hue, saturation) { root.hueSaturationRequested(hue, saturation) }
    onFocusRequested: function(section, index) { root.focusRequested(section, index) }
  }
  PanelSeparator { visible: speedSection.visible; foreground: root.bar.foreground }
  Column {
    id: speedSection
    visible: root.editable && root.currentMode.speeds.length > 0
    width: parent.width
    spacing: Style.space(10)
    PanelSectionHeader {
      text: "SPEED"
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
    }
    Grid {
      id: speeds
      width: parent.width
      columns: Math.max(1, root.currentMode.speeds.length)
      spacing: root.spacingTokens.xs
      readonly property real cellWidth: (width - spacing * (columns - 1)) / columns
      Repeater {
        model: root.currentMode.speeds
        OptionPill {
          required property string modelData
          required property int index
          bar: root.bar
          width: speeds.cellWidth
          active: root.effect.speed === modelData
          text: modelData
          hasCursor: root.focused("speed", index)
          onClicked: root.speedRequested(modelData)
          onHovered: function(hovered) { if (hovered) root.focusRequested("speed", index) }
        }
      }
    }
  }
  PanelSeparator { visible: directionSection.visible; foreground: root.bar.foreground }
  Column {
    id: directionSection
    visible: root.editable && root.currentMode.directions.length > 0
    width: parent.width
    spacing: Style.space(10)
    PanelSectionHeader {
      text: "DIRECTION"
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
    }
    Grid {
      id: directions
      width: parent.width
      columns: Math.max(1, root.currentMode.directions.length)
      spacing: root.spacingTokens.xs
      readonly property real cellWidth: (width - spacing * (columns - 1)) / columns
      Repeater {
        model: root.currentMode.directions
        OptionPill {
          required property string modelData
          required property int index
          bar: root.bar
          width: directions.cellWidth
          active: root.effect.direction === modelData
          text: modelData
          hasCursor: root.focused("direction", index)
          onClicked: root.directionRequested(modelData)
          onHovered: function(hovered) { if (hovered) root.focusRequested("direction", index) }
        }
      }
    }
  }
}
