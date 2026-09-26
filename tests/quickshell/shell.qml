import QtQuick
import Quickshell

// Real Process/StdioCollector callbacks with a fake helper. Like Omarchy's
// plugin loader, use explicit file URLs for code outside the config directory;
// Qt.resolvedUrl would resolve within Quickshell's virtual config namespace.
ShellRoot {
  id: root
  property int phase: 0
  property var client: null
  property var session: null
  property var ipc: null
  property int openRequests: 0

  function check(condition, message) {
    if (!condition) {
      console.error("AuraClient integration failure: " + message)
      Qt.callLater(function() { Qt.exit(1) })
      throw new Error(message)
    }
  }
  function received(snapshot) {
    root.check(snapshot.version === 1, "snapshot decoded")
    if (root.phase === 0) {
      root.phase = 1
      var publicState = JSON.parse(root.ipc.handler.state())
      root.check(publicState.available && publicState.mode === 1, "controller and IPC received state")
      root.check(publicState.colour1 === "#ff7f00" && publicState.colour2 === "#000000", "public colour format preserved")
      root.check(publicState.multizone === false && publicState.deviceType === 1, "public capability fields preserved")
      root.check(publicState.power[0].on === true && publicState.power[0].zone === -1, "public power shape preserved")
      root.check(root.ipc.handler.colourSlot("2") === "selected", "IPC uses session colour slot")
      root.check(root.ipc.handler.colour("#fff").indexOf("invalid") === 0, "IPC rejects invalid colour")
      root.check(root.ipc.handler.power("1", "awake", "yes") === "expected true or false", "IPC boolean parsing preserved")
      root.ipc.handler.open()
      root.check(root.openRequests === 1, "panel lifecycle routed as a signal")
      root.check(client.canResync, "initial state settled")
      root.check(client.submit({kind: "brightness", value: 1}), "first write accepted")
      client.submit({kind: "brightness", value: 2})
      client.submit({kind: "brightness", value: 3})
      root.check(client.queueState.pending.length === 1, "pending slider updates coalesce")
      root.check(client.queueState.pending[0].value === 3, "latest value retained")
      client.submit({kind: "mode", value: 1})
      client.submit({kind: "effect", mode: 1, field: "speed", value: "fail"})
      client.submit({kind: "brightness", value: 0})
      root.check(client.modePending, "mode transition guarded")
    } else if (root.phase === 1) {
      root.phase = 2
      root.check(client.errorMessage.indexOf("intentional test failure") >= 0, "stderr visible after failure")
      root.check(!client.writing && !client.syncPending && !client.modePending, "final readback settled")
      root.check(client.submit({kind: "resync"}), "resync accepted")
      root.check(!client.submit({kind: "brightness", value: 2}), "resync excludes edits")
    } else {
      root.check(client.errorMessage === "", "new operation clears previous error")
      root.check(client.resyncStatus === "Settings re-sent · brightness preserved.", "resync completed")
      console.log("AuraClient process integration tests passed")
      Qt.quit()
    }
  }
  Timer {
    interval: 10000
    running: true
    onTriggered: root.check(false, "timed out")
  }
  Component.onCompleted: {
    var project = "file://" + Quickshell.env("AURA_TEST_ROOT")
    var component = Qt.createComponent(project + "/qml/transport/AuraClient.qml")
    root.check(component.status === Component.Ready, component.errorString())
    root.client = component.createObject(root, {helperUrl: project + "/tests/fixtures/fake_backend.py"})
    root.check(root.client !== null, "client created")
    var controllerComponent = Qt.createComponent(project + "/qml/app/AuraController.qml")
    root.check(controllerComponent.status === Component.Ready, controllerComponent.errorString())
    root.session = controllerComponent.createObject(root, {client: root.client, pollingEnabled: false})
    root.check(root.session !== null, "controller created")
    var ipcComponent = Qt.createComponent(project + "/qml/ipc/AuraIpc.qml")
    root.check(ipcComponent.status === Component.Ready, ipcComponent.errorString())
    root.ipc = ipcComponent.createObject(root, {controller: root.session})
    root.check(root.ipc !== null, "IPC adapter created")
    root.ipc.openRequested.connect(function() { root.openRequests++ })
    root.client.stateReceived.connect(root.received)
    root.client.readFailed.connect(function() { root.check(false, "fake state read failed: " + root.client.errorMessage) })
    root.client.refresh()
  }
}
