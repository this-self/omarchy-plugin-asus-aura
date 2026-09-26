.pragma library

// Pure transitions. The QML adapter alone starts processes and timers.
function create() {
  return {path: "", pending: [], active: null, revision: 0, readRevision: 0,
    reading: false, modePending: false, syncPending: false,
    error: "", errorOperation: "", resyncStatus: ""}
}

function writing(state) { return state.active !== null || state.pending.length > 0 }
function resyncing(state) { return state.active !== null && state.active.kind === "resync" }
function canResync(state) { return !!state.path && !writing(state) && !state.reading && !state.syncPending }
function key(request) {
  return [request.kind, request.mode, request.zone, request.field].join(":")
}

function enqueue(state, request) {
  if (!state.path || resyncing(state) || (request.kind === "resync" && !canResync(state))) return null
  var pending = state.pending.slice()
  if (pending.length && key(pending[pending.length - 1]) === key(request))
    pending[pending.length - 1] = request
  else pending.push(request)
  return Object.assign({}, state, {
    pending: pending, revision: state.revision + 1, syncPending: true,
    modePending: state.modePending || request.kind === "mode" || request.kind === "global",
    error: "", errorOperation: "",
    resyncStatus: request.kind === "resync" ? "Resyncing…" : state.resyncStatus
  })
}

function startWrite(state) {
  if (state.active !== null || !state.pending.length) return state
  return Object.assign({}, state, {active: state.pending[0], pending: state.pending.slice(1)})
}

function finishWrite(state, error) {
  var operation = state.active ? state.active.kind : "Write"
  var message = error ? operation + ": " + error : state.error
  return Object.assign({}, state, {
    active: null, pending: error ? [] : state.pending,
    error: message, errorOperation: error ? operation : state.errorOperation,
    resyncStatus: operation === "resync"
      ? (error ? message : "Settings re-sent · brightness preserved.") : state.resyncStatus
  })
}

function startRead(state) {
  if (writing(state) || state.reading) return state
  return Object.assign({}, state, {reading: true, readRevision: state.revision})
}

function finishRead(state, snapshot, error) {
  // Do not clear mode/sync guards until a current readback has completed.
  if (state.readRevision !== state.revision || writing(state))
    return {state: Object.assign({}, state, {reading: false}), stale: true}
  var next = Object.assign({}, state, {reading: false, modePending: false, syncPending: false})
  if (error) {
    next.path = ""
    next.error = "Read: " + error
    next.errorOperation = "Read"
  } else {
    next.path = snapshot.path
    if (state.errorOperation === "Read") {
      next.error = ""
      next.errorOperation = ""
    }
  }
  return {state: next, stale: false}
}
