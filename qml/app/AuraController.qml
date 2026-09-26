import QtQuick
import "ColourMath.js" as Colour

// Application state and actions. The injected client has the small interface
// documented in ARCHITECTURE.md, allowing tests without Quickshell or hardware.
QtObject {
  id: root
  required property var client
  property bool panelOpen: false
  property bool pollingEnabled: true
  property bool available: false
  property var snapshot: null
  property var display: ({
    brightness: {value: 0, levels: [0, 1, 2, 3]}, modeId: 0,
    savedEffect: {colour1: {red: 127, green: 187, blue: 179}, colour2: {red: 0, green: 0, blue: 0}, speed: "Med", direction: "Right"},
    effects: [], device: {type: -1, rgbZones: [], powerZones: []},
    zoneState: "unknown", powerControls: []
  })
  property int restoreLevel: 1

  readonly property int level: display.brightness.value
  readonly property int maxLevel: Math.max.apply(null, display.brightness.levels)
  readonly property int mode: display.modeId
  readonly property var effects: display.effects
  readonly property var currentMode: {
    for (var i = 0; i < root.effects.length; i++)
      if (root.effects[i].id === root.mode) return root.effects[i]
    return {id: root.mode, name: "Mode " + root.mode, colourCount: 0, fields: [], speeds: [], directions: []}
  }
  readonly property var effect: display.savedEffect
  readonly property var powerControls: display.powerControls
  readonly property string zoneState: display.zoneState
  readonly property bool effectEditable: available && !client.modePending && zoneState === "global"
  readonly property bool resyncing: client.resyncing
  readonly property bool pending: client.writing || client.reading || client.syncPending
  readonly property bool canResync: available && client.canResync
  readonly property bool canReplaceZones: available && !client.modePending && !resyncing
  readonly property string errorMessage: client.errorMessage
  readonly property string resyncStatus: client.resyncStatus

  readonly property ColourEditor colourEditor: ColourEditor {
    colour1: root.effect.colour1
    colour2: root.effect.colour2
    colourCount: root.currentMode.colourCount
  }

  readonly property Connections clientConnections: Connections {
    target: root.client
    function onStateReceived(state) { root.acceptSnapshot(state) }
    function onReadFailed() { root.available = false }
  }
  readonly property Timer pollTimer: Timer {
    interval: root.panelOpen ? 4000 : 30000
    running: root.pollingEnabled
    repeat: true
    onTriggered: root.refresh()
  }
  Component.onCompleted: if (pollingEnabled) refresh()
  onPanelOpenChanged: if (panelOpen && pollingEnabled) refresh()

  function refresh() { root.client.refresh() }
  function acceptSnapshot(state) {
    root.snapshot = state
    root.display = state
    if (root.level > 0) root.restoreLevel = root.level
    root.available = true
  }
  function patchDisplay(changes) { root.display = Object.assign({}, root.display, changes) }
  function patchEffect(changes) {
    root.patchDisplay({savedEffect: Object.assign({}, root.effect, changes)})
  }

  function setBrightness(value) {
    if (!root.available || root.resyncing || !isFinite(value)) return false
    var level = Math.max(0, Math.min(root.maxLevel, Math.round(value)))
    if (!root.client.submit({kind: "brightness", value: level})) return false
    if (level > 0) root.restoreLevel = level
    root.patchDisplay({brightness: Object.assign({}, root.display.brightness, {value: level})})
    return true
  }
  function adjustBrightness(delta) { return root.setBrightness(root.level + delta) }
  function toggleBacklight() { return root.setBrightness(root.level > 0 ? 0 : root.restoreLevel) }

  function selectMode(mode) {
    if (!root.available || !root.effects.some(function(e) { return e.id === mode })) return false
    if (!root.client.submit({kind: "mode", value: mode})) return false
    // Only the mode is optimistic. Its saved parameters arrive in readback.
    root.patchDisplay({modeId: mode})
    return true
  }
  function setEffectField(field, value) {
    if (!root.effectEditable || root.resyncing || root.currentMode.fields.indexOf(field) < 0) return false
    return root.client.submit({kind: "effect", mode: root.mode, field: field, value: value})
  }
  function setColour(slot, colour) {
    if ((slot !== 1 && slot !== 2) || slot > root.currentMode.colourCount || !Colour.valid(colour)) return false
    var field = "colour" + slot
    if (!root.setEffectField(field, [colour.red, colour.green, colour.blue])) return false
    var change = {}
    change[field] = colour
    root.patchEffect(change)
    return true
  }
  function setChannel(channel, value) {
    return root.setColour(root.colourEditor.effectiveSlot, root.colourEditor.withChannel(channel, value))
  }
  function applyHex(hex) { return root.setColour(root.colourEditor.effectiveSlot, Colour.fromHex(hex)) }
  function selectColourSlot(slot) { return root.colourEditor.selectSlot(slot) }
  function setHueSaturation(hue, saturation) {
    if (!isFinite(hue) || !isFinite(saturation)) return false
    var h = Math.max(0, Math.min(359, Math.round(hue)))
    var s = Math.max(0, Math.min(1, saturation))
    if (!root.setColour(root.colourEditor.effectiveSlot, root.colourEditor.atHueSaturation(h, s))) return false
    root.colourEditor.remember(h, s)
    return true
  }
  function setSpeed(speed) {
    if (root.currentMode.speeds.indexOf(speed) < 0 || !root.setEffectField("speed", speed)) return false
    root.patchEffect({speed: speed})
    return true
  }
  function setDirection(direction) {
    if (root.currentMode.directions.indexOf(direction) < 0 || !root.setEffectField("direction", direction)) return false
    root.patchEffect({direction: direction})
    return true
  }

  function setPower(zone, field, value) {
    if (!root.available || typeof value !== "boolean") return false
    var control = root.powerControls.find(function(c) { return c.zone === zone && c.field === field })
    if (!control || !root.client.submit({kind: "power", zone: zone, field: field, value: value})) return false
    root.patchDisplay({powerControls: root.powerControls.map(function(c) {
      return c.id === control.id ? Object.assign({}, c, {value: value}) : c
    })})
    return true
  }
  function replaceZones() {
    return root.canReplaceZones && root.client.submit({kind: "global", mode: root.mode})
  }
  function resync() { return root.canResync && root.client.submit({kind: "resync"}) }
}
