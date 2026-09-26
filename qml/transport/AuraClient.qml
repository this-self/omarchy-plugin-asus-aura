import QtQuick
import Quickshell
import Quickshell.Io
import "RequestQueue.js" as Queue
import "BackendProtocol.js" as Protocol

// Process adapter. Queue transitions are pure and tested without Quickshell.
Scope {
  id: root
  property var queueState: Queue.create()
  readonly property bool reading: queueState.reading
  readonly property bool writing: Queue.writing(queueState)
  readonly property bool resyncing: Queue.resyncing(queueState)
  readonly property bool modePending: queueState.modePending
  readonly property bool syncPending: queueState.syncPending
  readonly property bool canResync: Queue.canResync(queueState)
  readonly property string errorMessage: queueState.error
  readonly property string resyncStatus: queueState.resyncStatus
  property url helperUrl: Qt.resolvedUrl("../../backend/aura_cli.py")
  readonly property string helper: decodeURIComponent(root.helperUrl.toString().replace(/^file:\/\//, ""))

  signal stateReceived(var snapshot)
  signal readFailed()
  signal failed(string operation, string message)

  function reportError() {
    root.failed(root.queueState.errorOperation, root.errorMessage)
    console.warn(root.errorMessage)
  }

  function submit(request) {
    var next = Queue.enqueue(root.queueState, request)
    if (next === null) return false
    root.queueState = next
    root.pump()
    return true
  }

  function pump() {
    if (writeProcess.running) return
    var next = Queue.startWrite(root.queueState)
    if (next === root.queueState) return
    root.queueState = next
    writeProcess.command = ["python3", "-B", root.helper, "apply", next.path, JSON.stringify(next.active)]
    writeProcess.running = true
  }

  function refresh() {
    if (readProcess.running) return
    var next = Queue.startRead(root.queueState)
    if (next === root.queueState) return
    root.queueState = next
    readProcess.running = true
  }

  function finishRead(code) {
    var snapshot = null
    var error = code !== 0 ? String(readErrors.text || "ASUS service unavailable").trim() : ""
    if (!error) {
      try { snapshot = Protocol.parse(String(readOutput.text || "").trim()) }
      catch (e) { error = String(e) }
    }
    var result = Queue.finishRead(root.queueState, snapshot, error)
    root.queueState = result.state
    if (result.stale) { settle.restart(); return }
    if (error) { root.reportError(); root.readFailed() }
    else root.stateReceived(snapshot)
  }

  function finishWrite(code) {
    var error = code !== 0 ? String(writeErrors.text || "ASUS service request failed").trim() : ""
    root.queueState = Queue.finishWrite(root.queueState, error)
    if (error) root.reportError()
    // Process.running may not have settled inside the exit callback.
    settle.restart()
  }

  Process {
    id: readProcess
    command: ["python3", "-B", root.helper, "state"]
    stdout: StdioCollector { id: readOutput; waitForEnd: true }
    stderr: StdioCollector { id: readErrors; waitForEnd: true }
    // Quickshell's QProcess::ExitStatus lacks a qmllint type definition.
    Component.onCompleted: exited.connect(function(code) { root.finishRead(code) })
  }

  Process {
    id: writeProcess
    stderr: StdioCollector { id: writeErrors; waitForEnd: true }
    Component.onCompleted: exited.connect(function(code) { root.finishWrite(code) })
  }

  Timer {
    id: settle
    interval: 1
    onTriggered: {
      if (root.queueState.pending.length) root.pump()
      else root.refresh()
    }
  }
}
