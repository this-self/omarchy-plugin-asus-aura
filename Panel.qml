import QtQuick
import qs.Ui as Shell
import "qml/app" as App
import "qml/transport" as Transport
import "qml/ipc" as Ipc
import "qml/ui" as Ui

// Omarchy composition root. Hardware, application state and presentation
// remain independently understandable and testable behind these boundaries.
Shell.Panel {
  id: root
  moduleName: "this-self.asus-aura"
  ipcTarget: "this-self.asus-aura"
  manageIpc: false
  readonly property Shell.PluginBarApi barApi: root.bar as Shell.PluginBarApi

  // Keep the widget reachable even when the ASUS service cannot be read.
  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Transport.AuraClient { id: backendClient }
  App.AuraController {
    id: auraSession
    client: backendClient
    panelOpen: root.opened
  }
  Ipc.AuraIpc {
    controller: auraSession
    onOpenRequested: root.open()
    onCloseRequested: root.close()
    onToggleRequested: root.toggle()
  }
  Ui.AuraBarButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    available: auraSession.available
    level: auraSession.level
    maximum: auraSession.maxLevel
    modeName: auraSession.currentMode.name
    onTogglePanelRequested: root.toggle()
    onToggleBacklightRequested: {
      auraSession.toggleBacklight()
      root.showOsd()
    }
    onBrightnessAdjustmentRequested: function(delta) {
      auraSession.adjustBrightness(delta)
      root.showOsd()
    }
  }
  Ui.AuraPopup {
    session: auraSession
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    onPanelSwitchRequested: function(direction) { root.switchPanel(direction) }
  }

  function showOsd() {
    if (!root.barApi || !root.barApi.shell) return
    root.barApi.shell.summon("omarchy.osd", JSON.stringify({
      icon: "keyboard",
      value: auraSession.maxLevel > 0 ? Math.round(auraSession.level * 100 / auraSession.maxLevel) : 0
    }))
  }
}
