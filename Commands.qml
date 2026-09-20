import QtQuick
import Quickshell
import Quickshell.Io

// A single ordered writer prevents mode/effect/brightness races. Adjacent
// updates to the same field coalesce, but never cross a mode or power barrier.
Scope {
  id: commands

  property string auraPath: ""
  property var queue: []
  property var activeRequest: null
  property int revision: 0
  property int readRevision: 0
  property bool modePending: false
  property bool syncPending: false
  property string errorMessage: ""
  property string errorOperation: ""
  property string resyncStatus: ""
  readonly property bool reading: stateProc.running
  readonly property bool writing: activeRequest !== null || queue.length > 0
  readonly property bool resyncing: activeRequest !== null && activeRequest.kind === "resync"
  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("aura.py").toString().replace(/^file:\/\//, ""))

  signal stateReceived(var state)
  signal failed(string operation, string message)

  function fail(operation, message) {
    errorMessage = operation + ": " + message
    errorOperation = operation
    failed(operation, message)
    console.warn(errorMessage)
  }

  function refresh() {
    if (writing || reading) return
    readRevision = revision
    stateProc.running = true
  }

  function enqueue(request) {
    if (!auraPath || resyncing) return false
    revision++
    syncPending = true
    errorMessage = ""
    errorOperation = ""
    var pending = queue.slice()
    var key = request.kind + ":" + String(request.mode) + ":" + String(request.zone) + ":" + String(request.field)
    request.key = key
    if (pending.length && pending[pending.length - 1].key === key)
      pending[pending.length - 1] = request
    else pending.push(request)
    queue = pending
    pump()
    return true
  }

  function pump() {
    if (activeRequest !== null || queue.length === 0 || writeProc.running) return
    var pending = queue.slice()
    activeRequest = pending.shift()
    queue = pending
    writeProc.command = ["python3", "-B", helper, "apply", auraPath, JSON.stringify(activeRequest)]
    writeProc.running = true
  }

  function setBrightness(value) { return enqueue({kind: "brightness", value: value}) }
  function setMode(value) {
    var accepted = enqueue({kind: "mode", value: value})
    if (accepted) modePending = true
    return accepted
  }
  function setEffect(mode, field, value) { return enqueue({kind: "effect", mode: mode, field: field, value: value}) }
  function useGlobal(mode) {
    var accepted = enqueue({kind: "global", mode: mode})
    if (accepted) modePending = true
    return accepted
  }
  function setPower(zone, field, value) { return enqueue({kind: "power", zone: zone, field: field, value: value}) }
  function resync() {
    if (!auraPath || writing || reading || syncPending) return false
    resyncStatus = "Resyncing…"
    return enqueue({kind: "resync"})
  }

  Process {
    id: stateProc
    command: ["python3", "-B", commands.helper, "state"]
    stdout: StdioCollector { id: stateOutput; waitForEnd: true }
    stderr: StdioCollector { id: stateErrors; waitForEnd: true }
    Component.onCompleted: exited.connect(function(code) {
      // An older read must not overwrite a more recent user action.
      if (commands.readRevision !== commands.revision || commands.writing) {
        settle.restart()
        return
      }
      var state = null
      try { state = JSON.parse(String(stateOutput.text || "").trim()) } catch (e) {}
      if (code !== 0 || !state || !state.available) {
        commands.fail("Read", String(stateErrors.text || "ASUS service unavailable").trim())
        commands.auraPath = ""
        commands.stateReceived({available: false})
      } else {
        if (commands.errorOperation === "Read") {
          commands.errorMessage = ""
          commands.errorOperation = ""
        }
        commands.auraPath = String(state.path)
        commands.stateReceived(state)
      }
      commands.modePending = false
      commands.syncPending = false
    })
  }

  Process {
    id: writeProc
    stderr: StdioCollector { id: writeErrors; waitForEnd: true }
    Component.onCompleted: exited.connect(function(code) {
      var request = commands.activeRequest
      if (code !== 0) {
        commands.fail(request ? request.kind : "Write", String(writeErrors.text || "ASUS service request failed").trim())
        // Do not execute requests based on state that failed to apply.
        commands.queue = []
      }
      if (request && request.kind === "resync")
        commands.resyncStatus = code === 0 ? "Settings re-sent · brightness preserved." : commands.errorMessage
      commands.activeRequest = null
      // Defer until Process.running has settled.
      settle.restart()
    })
  }

  Timer {
    id: settle
    interval: 1
    onTriggered: {
      if (commands.queue.length) commands.pump()
      else commands.refresh()
    }
  }
}
