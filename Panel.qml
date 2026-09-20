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
  // Which colour the swatches and RGB sliders edit: 1 or 2.
  property int colourTarget: 1

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
  readonly property var presets: [
    "#ff0000", "#ff7f00", "#ffff00", "#00ff00", "#00ffff",
    "#007fff", "#0000ff", "#7f00ff", "#ff00ff", "#ffffff"
  ]

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

  function applyPreset(hex) {
    if (!root.effectEditable || !root.cur.c1 || commands.resyncing || !/^#[0-9a-fA-F]{6}$/.test(hex)) return false
    var c = Qt.color(hex)
    var r = Math.round(c.r * 255), g = Math.round(c.g * 255), b = Math.round(c.b * 255)
    if (root.effectiveColourTarget === 2) { root.c2r = r; root.c2g = g; root.c2b = b }
    else { root.c1r = r; root.c1g = g; root.c1b = b }
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
    var l = ["brightness", "resync", "effect"]
    if (root.multizone === true) l.push("global")
    if (root.effectEditable) {
      if (root.cur.c2) l.push("colourTarget")
      if (root.cur.c1) l.push("colour")
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
    if (s === "colour") return root.presets.length
    if (s === "speed") return root.speeds.length
    if (s === "direction") return root.directions.length
    if (s === "power") return root.powerControls.length
    return 0  // brightness: lone slider, sentinel -1
  }

  function sectionFirstIndex(s) { return s === "brightness" ? -1 : 0 }

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
    var max = root.sectionCount(root.focusSection) - 1
    root.selectedIndex = Math.max(0, Math.min(max, root.selectedIndex + delta))
  }

  function activateCursor() {
    var s = root.focusSection
    var i = root.selectedIndex
    if (s === "effect" && i >= 0 && i < root.supportedModes.length) root.setMode(root.supportedModes[i])
    else if (s === "colour" && i >= 0 && i < root.presets.length) root.applyPreset(root.presets[i])
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
    if (root.focusSection === "brightness") { root.selectedIndex = -1; return }
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
    function colour(hex: string): string { return root.applyPreset(hex) ? "queued" : "invalid, busy or global effect editing unavailable" }
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

  // ---------------- Bar button ----------------

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌌"
    tooltipText: root.available ? "ASUS Aura Lighting — " + root.levelName(root.level) + " · " + root.cur.name : "ASUS Aura — service unavailable"
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
    // fractional swatch height cannot leave a subpixel scroll range.
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
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

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
              anchors.right: parent.right
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

          // ---------- Recovery ----------
          Column {
            width: parent.width
            spacing: Style.space(6)

            OptionPill {
              width: parent.width
              group: "resync"
              idx: 0
              on: false
              enabled: root.available && !root.writing && !commands.reading && !commands.syncPending
              text: commands.resyncing ? "Resyncing…" : "Resync lighting"
              onClicked: root.resyncLighting()
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.resyncStatus || "Lights stuck off? Re-send settings at the current brightness."
              wrapMode: Text.Wrap
              color: Qt.darker(root.barApi.foreground, 1.4)
              font.family: root.barApi.fontFamily
              font.pixelSize: root.fontTokens.caption
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
                  enabled: root.available
                  onClicked: root.setMode(modelData)
                }
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Text {
              width: parent.width
              text: root.multizone === null
                ? "Cannot verify global/zoned state. Effect editing is disabled; daemon config must be readable."
                : root.multizone
                  ? "Zoned lighting is active. asusd does not expose its saved per-zone colours over D-Bus. Global edits are blocked to preserve it."
                  : root.supportedZones.length
                    ? "Editing the global effect. " + root.supportedZones.length + " RGB zones are advertised; reliable saved-zone editing is not available through this asusd interface."
                    : "Editing the global effect. No separate RGB zones are advertised."
              wrapMode: Text.Wrap
              color: Qt.darker(root.barApi.foreground, 1.4)
              font.family: root.barApi.fontFamily
              font.pixelSize: root.fontTokens.caption
            }

            OptionPill {
              visible: root.multizone === true
              width: parent.width
              group: "global"
              idx: 0
              on: false
              enabled: root.available && !commands.modePending
              text: "Use global effect (replace zones)"
              onClicked: root.useGlobalEffect()
            }
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
                fontSize: root.fontTokens.caption
                foreground: root.barApi.foreground
                fontFamily: root.barApi.fontFamily
                horizontalPadding: root.spacingTokens.sm
                verticalPadding: root.spacingTokens.controlPaddingY
                bordered: true
                onClicked: root.colourTarget = 2
              }
            }

            Grid {
              id: swatchGrid
              width: parent.width
              columns: root.presets.length
              spacing: root.spacingTokens.xs
              readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

              Repeater {
                model: root.presets
                Rectangle {
                  id: swatch
                  required property string modelData
                  required property int index
                  width: swatchGrid.cellWidth
                  height: swatchGrid.cellWidth
                  radius: Style.cornerRadius > 0 ? Style.space(4) : 0
                  color: modelData
                  border.width: (root.cursorActive && root.focusSection === "colour"
                                 && root.selectedIndex === index) ? 2 : 1
                  border.color: (root.cursorActive && root.focusSection === "colour"
                                 && root.selectedIndex === index)
                                ? root.barApi.foreground : Qt.darker(root.barApi.foreground, 2.0)

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: {
                      root.cursorActive = true
                      root.focusSection = "colour"
                      root.selectedIndex = swatch.index
                    }
                    onClicked: root.applyPreset(swatch.modelData)
                  }
                }
              }
            }

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
          PanelSeparator { foreground: root.barApi.foreground }

          Text {
            width: parent.width
            text: root.deviceType === 1
              ? "Boot and Sleep are shared by keyboard and lightbar. Awake is independent. This controller ignores Shutdown."
              : root.deviceType === 2
                ? "This TUF controller has no independent Shutdown setting."
                : root.powerControls.length ? "Power settings apply to each named lighting zone."
                : "No verified power controls are available for this controller."
            wrapMode: Text.Wrap
            color: Qt.darker(root.barApi.foreground, 1.4)
            font.family: root.barApi.fontFamily
            font.pixelSize: root.fontTokens.caption
          }

          Column {
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
