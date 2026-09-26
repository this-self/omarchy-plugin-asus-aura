import QtQuick

// Implements the controller's client contract without processes or hardware.
QtObject {
  id: root
  property bool acceptRequests: true
  property var requests: []
  property int refreshCount: 0
  property bool reading: false
  property bool writing: false
  property bool syncPending: false
  property bool modePending: false
  property bool resyncing: false
  readonly property bool canResync: !reading && !writing && !syncPending
  property string errorMessage: ""
  property string resyncStatus: ""
  signal stateReceived(var snapshot)
  signal readFailed()

  function refresh() { root.refreshCount++ }
  function submit(request) {
    if (!root.acceptRequests || root.resyncing) return false
    root.requests = root.requests.concat([request])
    root.writing = true
    root.syncPending = true
    if (request.kind === "mode" || request.kind === "global") root.modePending = true
    if (request.kind === "resync") root.resyncing = true
    return true
  }
  function publish(snapshot) {
    root.writing = false
    root.syncPending = false
    root.modePending = false
    root.resyncing = false
    root.stateReceived(snapshot)
  }
}
