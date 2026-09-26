import QtQuick
import QtQuick.Controls
import qs.Ui
import qs.Commons
import "../app" as App
import "sections"
import "Presentation.js" as Presentation

// Presenter: connects small visual sections to application actions. Sections
// receive values and emit intents; none of them knows the controller/client.
KeyboardPanel {
  id: root
  required property App.AuraController session
  readonly property PluginBarApi barApi: root.bar as PluginBarApi
  readonly property var spacingTokens: Style.spacing
  signal panelSwitchRequested(int direction)
  focusTarget: keyCatcher
  contentWidth: root.fittedContentWidth(Style.space(340))
  contentHeight: root.fittedContentHeight(Math.ceil(contentColumn.implicitHeight))
  onOpenChanged: if (open) navigation.reset()

  readonly property PanelNavigation navigation: PanelNavigation {
    id: navigation
    sections: {
      var sections = [{id: "resync", count: 1}, {id: "brightness", slider: true}]
      sections = sections.concat(effectSection.navigationSections)
      if (powerSection.visible) sections.push({id: "power", count: root.session.powerControls.length})
      return sections
    }
    onAdjusted: function(section, delta) {
      if (root.session.resyncing) return
      if (section === "brightness") root.session.adjustBrightness(delta)
      else effectSection.adjust(section, delta)
    }
    onActivated: function(section, index) {
      if (root.session.resyncing) return
      if (section === "resync") root.session.resync()
      else if (section === "brightness") root.session.toggleBacklight()
      else if (section === "power") powerSection.activate(index)
      else effectSection.activate(section, index)
    }
  }

  PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onMoveRequested: function(dx, dy) { navigation.move(dx, dy) }
    onActivateRequested: navigation.activate()
    onCloseRequested: root.close()
    onTabRequested: function(direction) { root.panelSwitchRequested(direction) }

    ScrollView {
      id: scrollArea
      readonly property int clipGutter: root.spacingTokens.xxs
      readonly property bool overflowing: contentHeight > availableHeight
      anchors.fill: parent
      anchors.margins: -clipGutter
      clip: true
      padding: 0
      contentWidth: availableWidth
      contentHeight: Math.ceil(contentColumn.implicitHeight) + clipGutter * 2
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      ScrollBar.vertical.policy: overflowing ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
      Binding {
        target: scrollArea.contentItem
        property: "interactive"
        value: scrollArea.overflowing
      }
      Column {
        id: contentColumn
        enabled: !root.session.resyncing
        x: scrollArea.clipGutter
        y: scrollArea.clipGutter
        width: scrollArea.availableWidth - scrollArea.clipGutter * 2
        spacing: Style.space(14)

        StatusSection {
          bar: root.barApi
          width: parent.width
          subtitle: root.session.available
            ? root.session.currentMode.name + " · " + Presentation.levelName(root.session.level, root.session.maxLevel)
            : "Service unavailable"
          errorMessage: root.session.errorMessage
          canResync: root.session.canResync
          resyncing: root.session.resyncing
          resyncStatus: root.session.resyncStatus
          hasCursor: navigation.active && navigation.section === "resync"
          onResyncRequested: root.session.resync()
          onFocusRequested: navigation.select("resync", 0)
        }
        PanelSeparator { foreground: root.barApi.foreground }
        BrightnessSection {
          bar: root.barApi
          width: parent.width
          level: root.session.level
          maximum: root.session.maxLevel
          interactive: root.session.available
          hasCursor: navigation.active && navigation.section === "brightness"
          onLevelRequested: function(value) { root.session.setBrightness(value) }
          onToggleRequested: root.session.toggleBacklight()
          onFocusRequested: navigation.select("brightness", -1)
        }
        PanelSeparator { foreground: root.barApi.foreground }
        EffectSection {
          id: effectSection
          bar: root.barApi
          width: parent.width
          effects: root.session.effects
          currentMode: root.session.currentMode
          effect: root.session.effect
          available: root.session.available
          editable: root.session.effectEditable
          canReplaceZones: root.session.canReplaceZones
          zoneState: root.session.zoneState
          colour: root.session.colourEditor.colour
          selectedSlot: root.session.colourEditor.effectiveSlot
          hue: root.session.colourEditor.hue
          saturation: root.session.colourEditor.saturation
          cursorActive: navigation.active
          cursorSection: navigation.section
          cursorIndex: navigation.index
          onModeRequested: function(mode) { root.session.selectMode(mode) }
          onReplaceZonesRequested: root.session.replaceZones()
          onColourSlotRequested: function(slot) { root.session.selectColourSlot(slot) }
          onChannelRequested: function(channel, value) { root.session.setChannel(channel, value) }
          onHueSaturationRequested: function(hue, saturation) { root.session.setHueSaturation(hue, saturation) }
          onSpeedRequested: function(speed) { root.session.setSpeed(speed) }
          onDirectionRequested: function(direction) { root.session.setDirection(direction) }
          onFocusRequested: function(section, index) { navigation.select(section, index) }
        }
        PanelSeparator { visible: powerSection.visible; foreground: root.barApi.foreground }
        PowerSection {
          id: powerSection
          bar: root.barApi
          width: parent.width
          controls: root.session.powerControls
          interactive: root.session.available
          hasCursor: navigation.active && navigation.section === "power"
          cursorIndex: navigation.index
          onPowerRequested: function(zone, field, value) { root.session.setPower(zone, field, value) }
          onFocusRequested: function(index) { navigation.select("power", index) }
        }
      }
    }
  }
}
