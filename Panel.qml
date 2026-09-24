pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Controls.js" as AuraControls

// ASUS Aura keyboard UI. Commands.qml owns the asusd command interface.
// Resync re-sends saved power/effect settings while preserving brightness.
Panel {
  id: root
  moduleName: "this-self.asus-aura"
  ipcTarget: "this-self.asus-aura"
  manageIpc: false

  readonly property PluginBarApi barApi: root.bar as PluginBarApi
  // Style exposes these extensible token objects as QtObject; retain their
  // dynamic members rather than treating them as plain QObject instances.
  readonly property var fontTokens: Style.font
  readonly property var spacingTokens: Style.spacing

  property bool available: false
  readonly property string resyncStatus: commands.resyncStatus

  property int level: 0
  property int maxLevel: 3
  property int restoreLevel: 1

  property int mode: 0
  property var supportedModes: [0]

  property int c1r: 127
  property int c1g: 187
  property int c1b: 179
  property int c2r: 0
  property int c2g: 0
  property int c2b: 0
  // Which colour the hue, saturation and RGB sliders edit: 1 or 2.
  property int colourTarget: 1
  // Hue survives zero saturation, so the hue slider does not snap to red
  // while the colour is white or grey.
  property real colourHue: 0
  property real colourSat: 0
  property bool assigningColour: false

  property string speed: "Med"
  property string direction: "Right"

  property int deviceType: -1
  property var supportedZones: []
  property var supportedPowerZones: []
  property var powerRows: []
  // null means the daemon's zoned/global state could not be established.
  property var multizone: null
  readonly property bool effectEditable: root.available && !commands.modePending && root.multizone === false
  readonly property var powerControls: AuraControls.powerControls(root.deviceType, root.supportedPowerZones, root.powerRows)
  readonly property int effectiveColourTarget: AuraControls.colourSlot(root.mode, root.colourTarget)

  property real wheelAccumulator: 0
  property bool cursorActive: false
  property string focusSection: "brightness"
  property int selectedIndex: -1

  readonly property var cur: AuraControls.modeInfo(root.mode)
  onModeChanged: if (!AuraControls.modeInfo(root.mode).c2) root.colourTarget = 1

  readonly property var speeds: ["Low", "Med", "High"]
  readonly property var directions: ["Right", "Left", "Up", "Down"]
  readonly property int hueStep: 10
  readonly property int satStep: 5

  // A write is in flight (or pending) — don't let a poll stomp the knob.
  readonly property bool writing: commands.writing

  readonly property int tr: root.effectiveColourTarget === 2 ? root.c2r : root.c1r
  readonly property int tg: root.effectiveColourTarget === 2 ? root.c2g : root.c1g
  readonly property int tb: root.effectiveColourTarget === 2 ? root.c2b : root.c1b

  function hex2(n) {
    var s = Math.max(0, Math.min(255, Math.round(n))).toString(16)
    return s.length < 2 ? "0" + s : s
  }
  function hexOf(r, g, b) { return "#" + root.hex2(r) + root.hex2(g) + root.hex2(b) }
  function hsvHex(h, s, v) {
    var c = AuraControls.hsvToRgb(h, s, v)
    return root.hexOf(c[0], c[1], c[2])
  }

  // Re-derive hue/saturation after the RGB changes from outside the
  // hue/saturation sliders; skip it when they already describe that RGB.
  function syncHueSat() {
    var t = AuraControls.rgbToHsv(root.tr, root.tg, root.tb)
    var c = AuraControls.hsvToRgb(root.colourHue, root.colourSat, t.v)
    if (c[0] === root.tr && c[1] === root.tg && c[2] === root.tb) return
    root.colourSat = t.s
    if (t.s > 0) root.colourHue = t.h
  }
  // Channels change one at a time (polls, slot switches), so defer to see
  // the whole colour; a half-updated one would leave a stray hue on grey.
  function queueHueSatSync() { if (!root.assigningColour) Qt.callLater(root.syncHueSat) }
  onTrChanged: queueHueSatSync()
  onTgChanged: queueHueSatSync()
  onTbChanged: queueHueSatSync()

  // ---------------- Reads ----------------

  function refresh() {
    commands.refresh()
  }

  // ---------------- Writes ----------------

  function clampLevel(v) {
    var n = Math.round(Number(v))
    if (!isFinite(n)) return 0
    return Math.max(0, Math.min(root.maxLevel, n))
  }

  function resyncLighting() {
    return root.available && commands.resync()
  }

  function setLevel(v) {
    if (!root.available || commands.resyncing || !isFinite(v)) return false
    var lvl = root.clampLevel(v)
    if (!commands.setBrightness(lvl)) return false
    if (lvl > 0) root.restoreLevel = lvl
    root.level = lvl
    return true
  }

  function adjust(delta) { return root.setLevel(root.level + delta) }

  function toggleBacklight() {
    root.setLevel(root.level > 0 ? 0 : (root.restoreLevel > 0 ? root.restoreLevel : 1))
  }

  // Writing LedMode alone makes asusd load that effect's own saved colours and
  // speed, so re-read afterwards instead of assuming ours still apply.
  function setMode(m) {
    if (!root.available || root.supportedModes.indexOf(m) < 0) return false
    if (!commands.setMode(m)) return false
    root.mode = m
    return true
  }

  function writeColour() {
    if (!root.effectEditable || !root.cur.c1) return false
    return commands.setEffect(root.mode, root.effectiveColourTarget === 2 ? "colour2" : "colour1", [root.tr, root.tg, root.tb])
  }

  function setChannel(ch, v) {
    if (!root.effectEditable || !root.cur.c1 || commands.resyncing) return
    var n = Math.max(0, Math.min(255, Math.round(v)))
    if (root.effectiveColourTarget === 2) {
      if (ch === "r") root.c2r = n; else if (ch === "g") root.c2g = n; else root.c2b = n
    } else {
      if (ch === "r") root.c1r = n; else if (ch === "g") root.c1g = n; else root.c1b = n
    }
    root.writeColour()
  }

  function assignColour(r, g, b) {
    root.assigningColour = true
    if (root.effectiveColourTarget === 2) { root.c2r = r; root.c2g = g; root.c2b = b }
    else { root.c1r = r; root.c1g = g; root.c1b = b }
    root.assigningColour = false
  }

  function applyHex(hex) {
    if (!root.effectEditable || !root.cur.c1 || commands.resyncing || !/^#[0-9a-fA-F]{6}$/.test(hex)) return false
    var c = Qt.color(hex)
    root.assignColour(Math.round(c.r * 255), Math.round(c.g * 255), Math.round(c.b * 255))
    root.syncHueSat()
    return root.writeColour()
  }

  // Keep the colour's value (max channel) so the sliders change hue and
  // saturation only; black has no hue to edit, so it starts at full value.
  function setHueSat(h, s) {
    if (!root.effectEditable || !root.cur.c1 || commands.resyncing || !isFinite(h) || !isFinite(s)) return false
    var v = Math.max(root.tr, root.tg, root.tb) / 255
    root.colourHue = Math.max(0, Math.min(359, Math.round(h)))
    root.colourSat = Math.max(0, Math.min(1, s))
    var c = AuraControls.hsvToRgb(root.colourHue, root.colourSat, v > 0 ? v : 1)
    root.assignColour(c[0], c[1], c[2])
    return root.writeColour()
  }

  function setSpeed(s) {
    if (!root.effectEditable || !root.cur.spd || root.speeds.indexOf(s) < 0) return false
    if (!commands.setEffect(root.mode, "speed", s)) return false
    root.speed = s
    return true
  }
  function setDirection(d) {
    if (!root.effectEditable || !root.cur.dir || root.directions.indexOf(d) < 0) return false
    if (!commands.setEffect(root.mode, "direction", d)) return false
    root.direction = d
    return true
  }

  function setPowerValue(zone, field, value) {
    if (!root.available) return false
    for (var i = 0; i < root.powerControls.length; i++) {
      var control = root.powerControls[i]
      if (control.zone !== zone || control.field !== field) continue
      if (!commands.setPower(zone, field, value)) return false
      root.powerRows = AuraControls.changePower(root.powerRows, control, value)
      return true
    }
    return false
  }

  function togglePower(idx) {
    if (idx < 0 || idx >= root.powerControls.length) return false
    var control = root.powerControls[idx]
    return root.setPowerValue(control.zone, control.field, !control.on)
  }

  function useGlobalEffect() {
    return root.available && !commands.modePending && commands.useGlobal(root.mode)
  }

  function levelName(lvl) {
    if (lvl <= 0) return "Off"
    if (root.maxLevel <= 3) return lvl === 1 ? "Low" : (lvl === 2 ? "Medium" : "High")
    return String(lvl)
  }

  function showOsd() {
    if (!root.barApi || !root.barApi.shell) return
    root.barApi.shell.summon("omarchy.osd", JSON.stringify({
      icon: "keyboard",
      value: root.maxLevel > 0 ? Math.round(root.level * 100 / root.maxLevel) : 0
    }))
  }

  // ---------------- Cursor model ----------------

  readonly property var visibleSections: {
    var l = ["resync", "brightness", "effect"]
    if (root.multizone === true) l.push("global")
    if (root.effectEditable) {
      if (root.cur.c2) l.push("colourTarget")
      if (root.cur.c1) l.push("hue", "saturation")
      if (root.cur.spd) l.push("speed")
      if (root.cur.dir) l.push("direction")
    }
    if (root.powerControls.length) l.push("power")
    return l
  }

  function sectionCount(s) {
    if (s === "resync" || s === "global") return 1
    if (s === "colourTarget") return 2
    if (s === "effect") return root.supportedModes.length
    if (s === "speed") return root.speeds.length
    if (s === "direction") return root.directions.length
    if (s === "power") return root.powerControls.length
    return 0  // lone sliders, sentinel -1
  }

  function isSliderSection(s) { return s === "brightness" || s === "hue" || s === "saturation" }
  function sectionFirstIndex(s) { return root.isSliderSection(s) ? -1 : 0 }

  function moveCursor(delta) {
    var secs = root.visibleSections
    var i = secs.indexOf(root.focusSection)
    if (i < 0) { root.focusSection = secs[0]; root.selectedIndex = root.sectionFirstIndex(secs[0]); return }
    var next = i + delta
    if (next < 0 || next > secs.length - 1) return
    root.focusSection = secs[next]
    root.selectedIndex = root.sectionFirstIndex(secs[next])
  }

  function moveCursorH(delta) {
    if (root.focusSection === "brightness") { root.adjust(delta); return }
    if (root.focusSection === "hue") { root.setHueSat(root.colourHue + delta * root.hueStep, root.colourSat); return }
    if (root.focusSection === "saturation") { root.setHueSat(root.colourHue, root.colourSat + delta * root.satStep / 100); return }
    var max = root.sectionCount(root.focusSection) - 1
    root.selectedIndex = Math.max(0, Math.min(max, root.selectedIndex + delta))
  }

  function activateCursor() {
    var s = root.focusSection
    var i = root.selectedIndex
    if (s === "effect" && i >= 0 && i < root.supportedModes.length) root.setMode(root.supportedModes[i])
    else if (s === "speed" && i >= 0 && i < root.speeds.length) root.setSpeed(root.speeds[i])
    else if (s === "direction" && i >= 0 && i < root.directions.length) root.setDirection(root.directions[i])
    else if (s === "power") root.togglePower(i)
    else if (s === "colourTarget" && i >= 0 && i < 2) root.colourTarget = i + 1
    else if (s === "global") root.useGlobalEffect()
    else if (s === "brightness") root.toggleBacklight()
    else if (s === "resync") root.resyncLighting()
  }

  function clampCursor() {
    var secs = root.visibleSections
    if (secs.indexOf(root.focusSection) < 0) {
      root.focusSection = secs[0]
      root.selectedIndex = root.sectionFirstIndex(secs[0])
      return
    }
    if (root.isSliderSection(root.focusSection)) { root.selectedIndex = -1; return }
    var max = root.sectionCount(root.focusSection) - 1
    root.selectedIndex = Math.max(0, Math.min(max, root.selectedIndex))
  }

  onVisibleSectionsChanged: clampCursor()

  // ---------------- IPC ----------------

  IpcHandler {
    target: "this-self.asus-aura"

    function set(level: string): string { return root.setLevel(Number(level)) ? "queued" : "invalid, busy or unavailable" }
    function up(): string { return root.adjust(1) ? "queued" : "busy or unavailable" }
    function down(): string { return root.adjust(-1) ? "queued" : "busy or unavailable" }
    function resync(): string { return root.resyncLighting() ? "started" : "busy or unavailable" }
    function mode(m: string): string { return root.setMode(Number(m)) ? "queued" : "unsupported, busy or unavailable" }
    function colour(hex: string): string { return root.applyHex(hex) ? "queued" : "invalid, busy or global effect editing unavailable" }
    function speed(value: string): string { return root.setSpeed(value) ? "queued" : "unsupported, busy or unavailable" }
    function direction(value: string): string { return root.setDirection(value) ? "queued" : "unsupported, busy or unavailable" }
    function globalEffect(): string { return root.useGlobalEffect() ? "queued" : "busy or unavailable" }
    function colourSlot(slot: string): string {
      var n = Number(slot)
      if (n !== 1 && (n !== 2 || !root.cur.c2)) return "unsupported colour slot"
      root.colourTarget = n
      return "selected"
    }
    function power(zone: string, field: string, enabled: string): string {
      if (enabled !== "true" && enabled !== "false") return "expected true or false"
      return root.setPowerValue(Number(zone), field, enabled === "true") ? "queued" : "unsupported, busy or unavailable"
    }
    function state(): string {
      return JSON.stringify({
        available: root.available, level: root.level, max: root.maxLevel,
        resyncing: commands.resyncing, resyncStatus: root.resyncStatus,
        mode: root.mode, modeName: root.cur.name, pending: commands.writing || commands.reading || commands.syncPending,
        error: commands.errorMessage, deviceType: root.deviceType,
        zones: root.supportedZones, multizone: root.multizone,
        effectEditable: root.effectEditable,
        colour1: root.effectEditable && root.cur.c1 ? root.hexOf(root.c1r, root.c1g, root.c1b) : null,
        colour2: root.effectEditable && root.cur.c2 ? root.hexOf(root.c2r, root.c2g, root.c2b) : null,
        speed: root.effectEditable && root.cur.spd ? root.speed : null,
        direction: root.effectEditable && root.cur.dir ? root.direction : null,
        power: root.powerControls
      })
    }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  // ---------------- Command interface ----------------

  Commands {
    id: commands
    onStateReceived: function(st) {
      if (!st.available) { root.available = false; return }
      if (Array.isArray(st.levels) && st.levels.length > 0)
        root.maxLevel = st.levels[st.levels.length - 1]
      if (Array.isArray(st.modes) && st.modes.length > 0) root.supportedModes = st.modes

      root.level = root.clampLevel(st.brightness)
      if (root.level > 0) root.restoreLevel = root.level
      root.mode = Number(st.mode)

      var d = st.data
      if (Array.isArray(d) && d.length >= 6) {
        root.c1r = d[2][0]; root.c1g = d[2][1]; root.c1b = d[2][2]
        root.c2r = d[3][0]; root.c2g = d[3][1]; root.c2b = d[3][2]
        root.speed = String(d[4])
        root.direction = String(d[5])
      }

      root.deviceType = Number(st.deviceType)
      root.supportedZones = st.zones || []
      root.supportedPowerZones = st.powerZones || []
      root.powerRows = st.power || []
      root.multizone = st.multizone
      root.available = true
    }
  }

  // Keep the panel reachable when reads fail so errors are visible.
  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (opened) {
      refresh()
      cursorActive = false
      focusSection = "brightness"
      selectedIndex = -1
    }
  }

  Timer {
    interval: root.opened ? 4000 : 30000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // ---------------- Reusable bits ----------------

  component OptionPill: Button {
    id: pill
    required property string group
    required property int idx
    required property bool on

    fontSize: root.fontTokens.caption
    foreground: root.barApi.foreground
    fontFamily: root.barApi.fontFamily
    horizontalPadding: root.spacingTokens.sm
    verticalPadding: root.spacingTokens.controlPaddingY
    bordered: true
    active: pill.on
    Accessible.role: Accessible.Button
    Accessible.name: pill.text
    Accessible.description: pill.tooltipText
    hasCursor: root.cursorActive && root.focusSection === pill.group && root.selectedIndex === pill.idx
    onHovered: function(isHovered) {
      if (!isHovered) return
      root.cursorActive = true
      root.focusSection = pill.group
      root.selectedIndex = pill.idx
    }
  }

  component ChannelSlider: Column {
    id: chan
    required property string channel
    required property string label
    required property int amount

    width: parent ? parent.width : 0
    spacing: Style.space(2)

    Item {
      width: parent.width
      implicitHeight: Math.max(chanLabel.implicitHeight, chanValue.implicitHeight)
      Text {
        id: chanLabel
        text: chan.label
        color: Qt.darker(root.barApi.foreground, 1.4)
        font.family: root.barApi.fontFamily
        font.pixelSize: root.fontTokens.caption
        font.bold: true
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        id: chanValue
        text: String(chan.amount)
        color: Qt.darker(root.barApi.foreground, 1.4)
        font.family: root.barApi.fontFamily
        font.pixelSize: root.fontTokens.caption
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    PanelSlider {
      bar: root.bar
      width: parent.width
      minimum: 0
      maximum: 255
      step: 1
      integer: true
      value: chan.amount
      onMoved: function(v) { root.setChannel(chan.channel, v) }
      onReleased: function(v) { root.setChannel(chan.channel, v) }
    }
  }

  // Gradient-track slider for hue and saturation; a keyboard cursor row
  // like brightness, where left/right steps the value.
  component SpectrumSlider: Column {
    id: spec
    required property string section
    required property string label
    required property string valueText
    required property real value
    required property real maximum
    required property int step
    required property color knobColor
    required property Gradient trackGradient
    property real liveValue: value
    property bool dragging: false
    property real wheelAccumulator: 0
    signal moved(real value)

    onValueChanged: if (!spec.dragging) spec.liveValue = spec.value

    width: parent ? parent.width : 0
    spacing: Style.space(2)

    readonly property real knobSize: Style.space(22)
    readonly property real progress: Math.max(0, Math.min(1, spec.liveValue / Math.max(1, spec.maximum)))

    function setLive(v) {
      var n = Math.max(0, Math.min(spec.maximum, Math.round(v)))
      spec.liveValue = n
      spec.moved(n)
    }

    Item {
      width: parent.width
      implicitHeight: Math.max(specLabel.implicitHeight, specValue.implicitHeight)
      Text {
        id: specLabel
        text: spec.label
        color: Qt.darker(root.barApi.foreground, 1.4)
        font.family: root.barApi.fontFamily
        font.pixelSize: root.fontTokens.caption
        font.bold: true
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        id: specValue
        text: spec.valueText
        color: Qt.darker(root.barApi.foreground, 1.4)
        font.family: root.barApi.fontFamily
        font.pixelSize: root.fontTokens.caption
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    CursorSurface {
      width: parent.width
      height: spec.knobSize + root.spacingTokens.controlGap
      hasCursor: root.cursorActive && root.focusSection === spec.section
      foreground: root.barApi.foreground
      outline: true
      Accessible.role: Accessible.Slider
      Accessible.name: spec.label
      Accessible.description: spec.valueText

      Item {
        id: specTrackArea
        anchors.fill: parent
        anchors.leftMargin: Style.space(6)
        anchors.rightMargin: Style.space(6)

        Rectangle {
          id: specTrack
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(14)
          radius: height / 2
          gradient: spec.trackGradient
        }
        Rectangle {
          anchors.fill: specTrack
          radius: specTrack.radius
          color: "transparent"
          border.width: 1
          border.color: Qt.rgba(0, 0, 0, 0.35)
        }

        // Outer ring in the panel background separates the knob from the
        // track colour beneath it.
        Rectangle {
          width: spec.knobSize + Style.space(2)
          height: width
          radius: width / 2
          color: root.barApi.background
          anchors.centerIn: specKnob
          scale: specKnob.scale
        }
        Rectangle {
          id: specKnob
          width: spec.knobSize
          height: width
          radius: width / 2
          color: spec.knobColor
          border.width: Style.space(3)
          border.color: root.barApi.foreground
          anchors.verticalCenter: specTrack.verticalCenter
          x: (specTrackArea.width - width) * spec.progress
          scale: specMouse.containsMouse || spec.dragging ? 1.1 : 1.0
          Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        }

        MouseArea {
          id: specMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor

          function valueFromX(x) {
            var span = Math.max(1, width - spec.knobSize)
            return (x - spec.knobSize / 2) / span * spec.maximum
          }

          onEntered: {
            root.cursorActive = true
            root.focusSection = spec.section
            root.selectedIndex = -1
          }
          onPressed: function(mouse) {
            spec.dragging = true
            spec.setLive(valueFromX(mouse.x))
          }
          onPositionChanged: function(mouse) { if (spec.dragging) spec.setLive(valueFromX(mouse.x)) }
          onReleased: {
            spec.dragging = false
            spec.liveValue = spec.value
          }
          onCanceled: {
            spec.dragging = false
            spec.liveValue = spec.value
          }
          onWheel: function(wheel) {
            var w = Util.wheelSteps(spec.wheelAccumulator, wheel.angleDelta.y)
            spec.wheelAccumulator = w.remainder
            if (w.steps !== 0) spec.setLive(spec.liveValue + w.steps * spec.step)
          }
        }
      }
    }
  }

  // ---------------- Bar button ----------------

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌌"
    tooltipText: root.available
      ? "ASUS Aura — " + root.levelName(root.level) + " · " + root.cur.name
        + "\nScroll to adjust brightness. Right-click to turn off/restore."
      : "ASUS Aura — service unavailable"
    onPressed: function(b) {
      if (b === Qt.RightButton) { root.toggleBacklight(); root.showOsd() }
      else root.toggle()
    }
    onWheelMoved: function(delta) {
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      root.adjust(wheel.steps)
      root.showOsd()
    }
  }

  // ---------------- Panel ----------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    // Fit the full layout unless the screen is too small. Round up so a
    // fractional layout height cannot leave a subpixel scroll range.
    contentHeight: panel.fittedContentHeight(Math.ceil(panelColumn.implicitHeight))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursorH(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        padding: 0
        contentWidth: availableWidth
        contentHeight: Math.ceil(panelColumn.implicitHeight)
        readonly property bool overflowing: contentHeight > availableHeight
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: overflowing ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: scrollArea.overflowing
        }

        Column {
          id: panelColumn
          enabled: !commands.resyncing
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- Hero ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, resyncButton.height)

            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: "󰌌"
              color: root.barApi.foreground
              font.family: root.barApi.fontFamily
              font.pixelSize: root.fontTokens.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: resyncButton.left
              anchors.rightMargin: root.spacingTokens.sm
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "ASUS Aura Lighting"
                color: root.barApi.foreground
                font.family: root.barApi.fontFamily
                font.pixelSize: root.fontTokens.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                text: root.available ? (root.cur.name + " · " + root.levelName(root.level)).toUpperCase() : "SERVICE UNAVAILABLE"
                color: Qt.darker(root.barApi.foreground, 1.4)
                font.family: root.barApi.fontFamily
                font.pixelSize: root.fontTokens.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }

            OptionPill {
              id: resyncButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(implicitWidth, implicitHeight)
              height: width
              group: "resync"
              idx: 0
              on: false
              bordered: false
              enabled: root.available && !root.writing && !commands.reading && !commands.syncPending
              iconText: "󰑓"
              iconSpinning: commands.resyncing
              tooltipText: "Re-send saved lighting settings; keep brightness, including Off."
                + (root.resyncStatus ? "\n" + root.resyncStatus : "")
              Accessible.role: Accessible.Button
              Accessible.name: "Resync lighting"
              onClicked: root.resyncLighting()
            }
          }

          Text {
            visible: !!commands.errorMessage
            width: parent.width
            text: commands.errorMessage
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.barApi.foreground
            font.family: root.barApi.fontFamily
            font.pixelSize: root.fontTokens.caption
          }

          // ---------- Brightness ----------
          PanelSeparator { foreground: root.barApi.foreground }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(brHeader.implicitHeight, brValue.implicitHeight)
              PanelSectionHeader {
                id: brHeader
                text: "BRIGHTNESS"
                foreground: root.barApi.foreground
                fontFamily: root.barApi.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                id: brValue
                textFormat: Text.PlainText
                text: root.levelName(brSlider.dragging ? Math.round(brSlider.liveValue) : root.level)
                      + "  " + (brSlider.dragging ? Math.round(brSlider.liveValue) : root.level) + "/" + root.maxLevel
                color: Qt.darker(root.barApi.foreground, 1.4)
                font.family: root.barApi.fontFamily
                font.pixelSize: root.fontTokens.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              width: parent.width
              height: brSlider.implicitHeight + root.spacingTokens.controlGap
              hasCursor: root.cursorActive && root.focusSection === "brightness"
              foreground: root.barApi.foreground
              outline: true

              PanelSlider {
                id: brSlider
                enabled: root.available
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 0
                maximum: root.maxLevel
                step: 1
                integer: true
                tickCount: root.maxLevel + 1
                value: root.level
                onMoved: function(v) { root.setLevel(v) }
                onReleased: function(v) { root.setLevel(v) }
                onRightClicked: root.toggleBacklight()
              }

              HoverHandler {
                onHoveredChanged: if (hovered) {
                  root.cursorActive = true
                  root.focusSection = "brightness"
                  root.selectedIndex = -1
                }
              }
            }
          }

          // ---------- Effect ----------
          PanelSeparator { foreground: root.barApi.foreground }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "EFFECT"
              foreground: root.barApi.foreground
              fontFamily: root.barApi.fontFamily
            }

            Grid {
              id: modeGrid
              width: parent.width
              columns: 3
              spacing: root.spacingTokens.xs
              readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

              Repeater {
                model: root.supportedModes
                OptionPill {
                  required property var modelData
                  required property int index
                  width: modeGrid.cellWidth
                  group: "effect"
                  idx: index
                  on: root.mode === modelData
                  text: AuraControls.modeInfo(modelData).name
                  tooltipText: AuraControls.effectTooltip(modelData, root.multizone)
                  enabled: root.available
                  onClicked: root.setMode(modelData)
                }
              }
            }
          }

          OptionPill {
            visible: root.multizone === true
            width: parent.width
            group: "global"
            idx: 0
            on: false
            enabled: root.available && !commands.modePending
            text: "Replace zones"
            tooltipText: "Replace active zoned lighting with the saved global effect.\nEnables colour, speed and direction editing; keeps brightness."
            onClicked: root.useGlobalEffect()
          }

          // ---------- Colour ----------
          PanelSeparator {
            visible: root.cur.c1 && root.effectEditable
            foreground: root.barApi.foreground
          }

          Column {
            visible: root.cur.c1 && root.effectEditable
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: Math.max(colHeader.implicitHeight, colHex.implicitHeight)
              PanelSectionHeader {
                id: colHeader
                text: "COLOUR"
                foreground: root.barApi.foreground
                fontFamily: root.barApi.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                id: colHex
                textFormat: Text.PlainText
                text: root.hexOf(root.tr, root.tg, root.tb).toUpperCase()
                color: Qt.darker(root.barApi.foreground, 1.4)
                font.family: root.barApi.fontFamily
                font.pixelSize: root.fontTokens.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            // Two-colour effects edit an explicit slot.
            Grid {
              id: targetGrid
              visible: root.cur.c2
              width: parent.width
              columns: 2
              spacing: root.spacingTokens.xs
              readonly property real cellWidth: (width - spacing) / 2

              OptionPill {
                group: "colourTarget"
                idx: 0
                on: root.effectiveColourTarget === 1
                width: targetGrid.cellWidth
                text: "Colour 1"
                tooltipText: "Hue, saturation and RGB sliders edit the first effect colour."
                fontSize: root.fontTokens.caption
                foreground: root.barApi.foreground
                fontFamily: root.barApi.fontFamily
                horizontalPadding: root.spacingTokens.sm
                verticalPadding: root.spacingTokens.controlPaddingY
                bordered: true
                onClicked: root.colourTarget = 1
              }
              OptionPill {
                group: "colourTarget"
                idx: 1
                on: root.effectiveColourTarget === 2
                width: targetGrid.cellWidth
                text: "Colour 2"
                tooltipText: "Hue, saturation and RGB sliders edit the second effect colour."
                fontSize: root.fontTokens.caption
                foreground: root.barApi.foreground
                fontFamily: root.barApi.fontFamily
                horizontalPadding: root.spacingTokens.sm
                verticalPadding: root.spacingTokens.controlPaddingY
                bordered: true
                onClicked: root.colourTarget = 2
              }
            }

            SpectrumSlider {
              section: "hue"
              label: "HUE"
              valueText: Math.round(liveValue) + "°"
              maximum: 359
              step: root.hueStep
              value: root.colourHue
              knobColor: root.hsvHex(liveValue, 1, 1)
              trackGradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0 / 6; color: "#ff0000" }
                GradientStop { position: 1 / 6; color: "#ffff00" }
                GradientStop { position: 2 / 6; color: "#00ff00" }
                GradientStop { position: 3 / 6; color: "#00ffff" }
                GradientStop { position: 4 / 6; color: "#0000ff" }
                GradientStop { position: 5 / 6; color: "#ff00ff" }
                GradientStop { position: 1; color: "#ff0000" }
              }
              onMoved: function(v) { root.setHueSat(v, root.colourSat) }
            }

            SpectrumSlider {
              section: "saturation"
              label: "SATURATION"
              valueText: Math.round(liveValue) + "%"
              maximum: 100
              step: root.satStep
              value: Math.round(root.colourSat * 100)
              knobColor: root.hsvHex(root.colourHue, liveValue / 100, 1)
              trackGradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#ffffff" }
                GradientStop { position: 1; color: root.hsvHex(root.colourHue, 1, 1) }
              }
              onMoved: function(v) { root.setHueSat(root.colourHue, v / 100) }
            }

            Item { width: 1; height: Style.space(2) }

            ChannelSlider { channel: "r"; label: "RED";   amount: root.tr }
            ChannelSlider { channel: "g"; label: "GREEN"; amount: root.tg }
            ChannelSlider { channel: "b"; label: "BLUE";  amount: root.tb }
          }

          // ---------- Speed ----------
          PanelSeparator {
            visible: root.cur.spd && root.effectEditable
            foreground: root.barApi.foreground
          }

          Column {
            visible: root.cur.spd && root.effectEditable
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "SPEED"
              foreground: root.barApi.foreground
              fontFamily: root.barApi.fontFamily
            }

            Grid {
              id: speedGrid
              width: parent.width
              columns: root.speeds.length
              spacing: root.spacingTokens.xs
              readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

              Repeater {
                model: root.speeds
                OptionPill {
                  required property string modelData
                  required property int index
                  width: speedGrid.cellWidth
                  group: "speed"
                  idx: index
                  on: root.speed === modelData
                  text: modelData
                  onClicked: root.setSpeed(modelData)
                }
              }
            }
          }

          // ---------- Direction ----------
          PanelSeparator {
            visible: root.cur.dir && root.effectEditable
            foreground: root.barApi.foreground
          }

          Column {
            visible: root.cur.dir && root.effectEditable
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "DIRECTION"
              foreground: root.barApi.foreground
              fontFamily: root.barApi.fontFamily
            }

            Grid {
              id: dirGrid
              width: parent.width
              columns: root.directions.length
              spacing: root.spacingTokens.xs
              readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

              Repeater {
                model: root.directions
                OptionPill {
                  required property string modelData
                  required property int index
                  width: dirGrid.cellWidth
                  group: "direction"
                  idx: index
                  on: root.direction === modelData
                  text: modelData
                  onClicked: root.setDirection(modelData)
                }
              }
            }
          }

          // ---------- Power ----------
          PanelSeparator {
            visible: root.powerControls.length > 0
            foreground: root.barApi.foreground
          }

          Column {
            visible: root.powerControls.length > 0
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "LIGHTING POWER"
              foreground: root.barApi.foreground
              fontFamily: root.barApi.fontFamily
            }

            Grid {
              id: powerGrid
              width: parent.width
              columns: 2
              spacing: root.spacingTokens.xs
              readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

              Repeater {
                model: root.powerControls
                OptionPill {
                  required property var modelData
                  required property int index
                  width: powerGrid.cellWidth
                  group: "power"
                  idx: index
                  on: modelData.on
                  text: modelData.label
                  tooltipText: AuraControls.powerTooltip(modelData)
                  enabled: root.available
                  onClicked: root.togglePower(index)
                }
              }
            }
          }
        }
      }
    }
  }
}
