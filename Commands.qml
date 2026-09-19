import QtQuick
import Quickshell
import Quickshell.Io

// ASUS command interface. All external processes and D-Bus details live here.
// The panel supplies effect/power values and consumes stateReceived snapshots.
Scope {
  id: commands

  property string auraPath: ""
  // Pause reads while the UI has a debounced write pending.
  property bool writePending: false
  readonly property bool reading: stateProc.running
  readonly property bool resyncing: resyncProc.running
  readonly property bool writing: brightnessProc.running || modeProc.running
    || modeDataProc.running || powerProc.running || resyncing || writePending
  property int resyncExitCode: -1
  readonly property string resyncStatus: resyncing ? "Resyncing…"
    : resyncExitCode < 0 ? ""
    : resyncExitCode === 0 ? "Settings re-sent · brightness preserved."
    : "Resync failed: " + (String(resyncErrors.text || "").trim() || "ASUS service request failed.")

  signal stateReceived(var state)
  signal failed(string operation, string message)

  function busctlSet(prop, args) {
    return ["busctl", "--system", "set-property", "xyz.ljones.Asusd",
            commands.auraPath, "xyz.ljones.Aura", prop].concat(args)
  }

  function refresh() {
    if (!writing && !reading) stateProc.running = true
  }

  function setBrightness(level) {
    if (!auraPath || resyncing || brightnessProc.running) return false
    brightnessProc.command = busctlSet("Brightness", ["u", String(level)])
    brightnessProc.running = true
    return true
  }

  // LedMode loads the effect's saved colours/speed; refresh after settling.
  function setMode(mode) {
    if (!auraPath || resyncing || modeProc.running) return false
    modeProc.command = busctlSet("LedMode", ["u", String(mode)])
    modeProc.running = true
    return true
  }

  function setEffect(mode, colour1, colour2, speed, direction) {
    if (!auraPath || resyncing || modeDataProc.running) return false
    modeDataProc.command = busctlSet("LedModeData", [
      "(uu(yyy)(yyy)ss)", String(mode), "0",
      String(colour1[0]), String(colour1[1]), String(colour1[2]),
      String(colour2[0]), String(colour2[1]), String(colour2[2]),
      speed, direction])
    modeDataProc.running = true
    return true
  }

  // Rows: [zone, boot, awake, sleep, shutdown]. Include unchanged zones too.
  function setPower(rows) {
    if (!auraPath || resyncing || powerProc.running) return false
    var args = ["(a(ubbbb))", String(rows.length)]
    for (var j = 0; j < rows.length; j++) {
      args.push(String(rows[j][0]))
      for (var k = 1; k <= 4; k++) args.push(rows[j][k] ? "true" : "false")
    }
    powerProc.command = busctlSet("LedPower", args)
    powerProc.running = true
    return true
  }

  function resync() {
    if (!auraPath || writing || reading) return false
    resyncExitCode = -1
    resyncProc.command = ["python3",
      decodeURIComponent(Qt.resolvedUrl("resync.py").toString().replace(/^file:\/\//, "")),
      auraPath]
    resyncProc.running = true
    return true
  }

  function reportFailure(operation, exitCode, details) {
    if (exitCode !== 0) {
      var message = String(details || "").trim() || "ASUS service request failed (exit " + exitCode + ")."
      console.warn(operation + ": " + message)
      failed(operation, message)
    }
  }

  Process {
    id: stateProc
    command: ["bash", "-c",
      "P=$(busctl --system tree xyz.ljones.Asusd 2>/dev/null | grep -o '/xyz/ljones/aura/[A-Za-z0-9_]*' | head -1); " +
      "[ -z \"$P\" ] && { echo '{\"available\":false}'; exit 0; }; " +
      "busctl --system --json=short get-property xyz.ljones.Asusd \"$P\" xyz.ljones.Aura " +
      "Brightness LedMode LedModeData LedPower SupportedBasicModes SupportedBrightness 2>/dev/null " +
      "| jq -sc --arg p \"$P\" 'if length == 6 then {available:true,path:$p,brightness:.[0].data,mode:.[1].data," +
      "data:.[2].data,power:.[3].data[0],modes:.[4].data,levels:.[5].data} else {available:false} end'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var state = null
        try { state = JSON.parse(String(text || "").trim()) } catch (e) {}
        if (!state || !state.available) state = { available: false }
        commands.auraPath = state.available ? String(state.path || "") : ""
        commands.stateReceived(state)
      }
    }
  }

  Process {
    id: brightnessProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: brightnessErrors; waitForEnd: true }
    Component.onCompleted: exited.connect(function(code) {
      commands.reportFailure("Brightness", code, brightnessErrors.text)
    })
  }
  Process {
    id: modeProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: modeErrors; waitForEnd: true }
    Component.onCompleted: exited.connect(function(code) {
      commands.reportFailure("Mode", code, modeErrors.text)
    })
    onRunningChanged: if (!running) modeSettle.restart()
  }
  Process {
    id: modeDataProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: effectErrors; waitForEnd: true }
    Component.onCompleted: exited.connect(function(code) {
      commands.reportFailure("Effect", code, effectErrors.text)
    })
  }
  Process {
    id: powerProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: powerErrors; waitForEnd: true }
    Component.onCompleted: exited.connect(function(code) {
      commands.reportFailure("Power", code, powerErrors.text)
    })
  }
  Process {
    id: resyncProc
    stderr: StdioCollector { id: resyncErrors; waitForEnd: true }
    Component.onCompleted: exited.connect(function(code) {
      commands.resyncExitCode = code
      commands.reportFailure("Resync", code, resyncErrors.text)
      modeSettle.restart()
    })
  }

  Timer { id: modeSettle; interval: 250; repeat: false; onTriggered: commands.refresh() }
}
