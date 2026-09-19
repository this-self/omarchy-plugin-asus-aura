pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Ui
import qs.Commons

// ASUS Aura keyboard UI. Commands.qml owns the asusd command interface.
// Resync re-sends saved power/effect settings while preserving brightness.
Panel {
  id: root
  moduleName: "ifree.kbdbacklight"
  ipcTarget: "ifree.kbdbacklight"
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

  // Keyboard zone (1) power flags.
  property bool pwrBoot: true
  property bool pwrAwake: true
  property bool pwrSleep: false
  property bool pwrShutdown: false
  // Every non-keyboard power row, kept verbatim so writing keyboard flags
  // never clobbers the lightbar.
  property var otherPowerRows: []

  property real wheelAccumulator: 0
  property bool cursorActive: false
  property string focusSection: "brightness"
  property int selectedIndex: -1

  // Which controls each effect actually uses. Numbers verified against this
  // hardware by setting LedMode and reading back asusd's current_mode.
  readonly property var modeMeta: ({
    "0":  { name: "Static",  c1: true,  c2: false, spd: false, dir: false },
    "1":  { name: "Breathe", c1: true,  c2: true,  spd: true,  dir: false },
    "2":  { name: "Rainbow", c1: false, c2: false, spd: true,  dir: false },
    "3":  { name: "Wave",    c1: false, c2: false, spd: true,  dir: true  },
    "10": { name: "Pulse",   c1: true,  c2: false, spd: false, dir: false }
  })
  readonly property var fallbackMeta: ({ name: "Mode", c1: true, c2: false, spd: false, dir: false })
  readonly property var cur: root.modeMeta[String(root.mode)] || root.fallbackMeta

  readonly property var speeds: ["Low", "Med", "High"]
  readonly property var directions: ["Right", "Left", "Up", "Down"]
  readonly property var powerLabels: ["Boot", "Awake", "Sleep", "Shutdown"]
  readonly property var presets: [
    "#ff0000", "#ff7f00", "#ffff00", "#00ff00", "#00ffff",
    "#007fff", "#0000ff", "#7f00ff", "#ff00ff", "#ffffff"
  ]

  // A write is in flight (or pending) — don't let a poll stomp the knob.
  readonly property bool writing: commands.writing

  readonly property int tr: root.colourTarget === 2 ? root.c2r : root.c1r
  readonly property int tg: root.colourTarget === 2 ? root.c2g : root.c1g
  readonly property int tb: root.colourTarget === 2 ? root.c2b : root.c1b

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
    if (!root.available || commands.resyncing) return
    var lvl = root.clampLevel(v)
    if (lvl > 0) root.restoreLevel = lvl
    root.level = lvl
    commands.setBrightness(lvl)
  }

  function adjust(delta) { root.setLevel(root.level + delta) }

  function toggleBacklight() {
    root.setLevel(root.level > 0 ? 0 : (root.restoreLevel > 0 ? root.restoreLevel : 1))
  }

  // Writing LedMode alone makes asusd load that effect's own saved colours and
  // speed, so re-read afterwards instead of assuming ours still apply.
  function setMode(m) {
    if (!root.available || commands.resyncing) return
    root.mode = m
    commands.setMode(m)
  }

  function writeModeData() {
    if (!root.available) return
    commands.setEffect(root.mode,
      [root.c1r, root.c1g, root.c1b], [root.c2r, root.c2g, root.c2b],
      root.speed, root.direction)
  }

  function setChannel(ch, v) {
    if (commands.resyncing) return
    var n = Math.max(0, Math.min(255, Math.round(v)))
    if (root.colourTarget === 2) {
      if (ch === "r") root.c2r = n; else if (ch === "g") root.c2g = n; else root.c2b = n
    } else {
      if (ch === "r") root.c1r = n; else if (ch === "g") root.c1g = n; else root.c1b = n
    }
    colourDebounce.restart()
  }

  function applyPreset(hex) {
    if (commands.resyncing) return
    var c = Qt.color(hex)
    var r = Math.round(c.r * 255), g = Math.round(c.g * 255), b = Math.round(c.b * 255)
    if (root.colourTarget === 2) { root.c2r = r; root.c2g = g; root.c2b = b }
    else { root.c1r = r; root.c1g = g; root.c1b = b }
    root.writeModeData()
  }

  function setSpeed(s) { if (commands.resyncing) return; root.speed = s; root.writeModeData() }
  function setDirection(d) { if (commands.resyncing) return; root.direction = d; root.writeModeData() }

  function writePower() {
    if (!root.available || commands.resyncing) return
    // Keyboard row first, then every other zone unchanged.
    var rows = [[1, root.pwrBoot, root.pwrAwake, root.pwrSleep, root.pwrShutdown]]
    for (var i = 0; i < root.otherPowerRows.length; i++) rows.push(root.otherPowerRows[i])

    commands.setPower(rows)
  }

  function togglePower(idx) {
    if (commands.resyncing) return
    if (idx === 0) root.pwrBoot = !root.pwrBoot
    else if (idx === 1) root.pwrAwake = !root.pwrAwake
    else if (idx === 2) root.pwrSleep = !root.pwrSleep
    else root.pwrShutdown = !root.pwrShutdown
    root.writePower()
  }

  function powerFlag(idx) {
    return idx === 0 ? root.pwrBoot : (idx === 1 ? root.pwrAwake
         : (idx === 2 ? root.pwrSleep : root.pwrShutdown))
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
    if (root.cur.c1) l.push("colour")
    if (root.cur.spd) l.push("speed")
    if (root.cur.dir) l.push("direction")
    l.push("power")
    return l
  }

  function sectionCount(s) {
    if (s === "resync") return 1
    if (s === "effect") return root.supportedModes.length
    if (s === "colour") return root.presets.length
    if (s === "speed") return root.speeds.length
    if (s === "direction") return root.directions.length
    if (s === "power") return 4
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
    else if (s === "power" && i >= 0 && i < 4) root.togglePower(i)
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
    target: "ifree.kbdbacklight"

    function set(level: string): string { root.setLevel(Number(level)); return String(root.level) }
    function up(): string { root.adjust(1); return String(root.level) }
    function down(): string { root.adjust(-1); return String(root.level) }
    function resync(): string { return root.resyncLighting() ? "started" : "busy or unavailable" }
    function mode(m: string): string { root.setMode(Number(m)); return String(root.mode) }
    function colour(hex: string): string { root.applyPreset(hex); return root.hexOf(root.c1r, root.c1g, root.c1b) }
    function state(): string {
      return JSON.stringify({
        available: root.available, level: root.level, max: root.maxLevel,
        resyncing: commands.resyncing, resyncStatus: root.resyncStatus,
        mode: root.mode, modeName: root.cur.name,
        colour1: root.hexOf(root.c1r, root.c1g, root.c1b),
        colour2: root.hexOf(root.c2r, root.c2g, root.c2b),
        speed: root.speed, direction: root.direction,
        power: { boot: root.pwrBoot, awake: root.pwrAwake, sleep: root.pwrSleep, shutdown: root.pwrShutdown }
      })
    }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  // ---------------- Command interface ----------------

  Commands {
    id: commands
    writePending: colourDebounce.running

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

      var others = []
      if (Array.isArray(st.power)) {
        for (var i = 0; i < st.power.length; i++) {
          var row = st.power[i]
          if (Number(row[0]) === 1) {
            root.pwrBoot = !!row[1]; root.pwrAwake = !!row[2]
            root.pwrSleep = !!row[3]; root.pwrShutdown = !!row[4]
          } else {
            others.push(row)
          }
        }
      }
      root.otherPowerRows = others
      root.available = true
    }
  }

  Timer { id: colourDebounce; interval: 130; repeat: false; onTriggered: root.writeModeData() }

  visible: root.available
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
    tooltipText: "Keyboard backlight — " + root.levelName(root.level) + " · " + root.cur.name
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
                text: "Keyboard Aura"
                color: root.barApi.foreground
                font.family: root.barApi.fontFamily
                font.pixelSize: root.fontTokens.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                text: (root.cur.name + " · " + root.levelName(root.level)).toUpperCase()
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
              enabled: root.available && !root.writing && !commands.reading
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
                  text: (root.modeMeta[String(modelData)] || root.fallbackMeta).name
                  onClicked: root.setMode(modelData)
                }
              }
            }
          }

          // ---------- Colour ----------
          PanelSeparator {
            visible: root.cur.c1
            foreground: root.barApi.foreground
          }

          Column {
            visible: root.cur.c1
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

            // Breathe is the only two-colour effect here; pick which one the
            // swatches and sliders below are editing.
            Grid {
              id: targetGrid
              visible: root.cur.c2
              width: parent.width
              columns: 2
              spacing: root.spacingTokens.xs
              readonly property real cellWidth: (width - spacing) / 2

              Button {
                width: targetGrid.cellWidth
                text: "Colour 1"
                fontSize: root.fontTokens.caption
                foreground: root.barApi.foreground
                fontFamily: root.barApi.fontFamily
                horizontalPadding: root.spacingTokens.sm
                verticalPadding: root.spacingTokens.controlPaddingY
                bordered: true
                active: root.colourTarget === 1
                onClicked: root.colourTarget = 1
              }
              Button {
                width: targetGrid.cellWidth
                text: "Colour 2"
                fontSize: root.fontTokens.caption
                foreground: root.barApi.foreground
                fontFamily: root.barApi.fontFamily
                horizontalPadding: root.spacingTokens.sm
                verticalPadding: root.spacingTokens.controlPaddingY
                bordered: true
                active: root.colourTarget === 2
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
            visible: root.cur.spd
            foreground: root.barApi.foreground
          }

          Column {
            visible: root.cur.spd
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
            visible: root.cur.dir
            foreground: root.barApi.foreground
          }

          Column {
            visible: root.cur.dir
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

          Column {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "LIGHT WHEN"
              foreground: root.barApi.foreground
              fontFamily: root.barApi.fontFamily
            }

            Grid {
              id: powerGrid
              width: parent.width
              columns: 4
              spacing: root.spacingTokens.xs
              readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

              Repeater {
                model: root.powerLabels
                OptionPill {
                  required property string modelData
                  required property int index
                  width: powerGrid.cellWidth
                  group: "power"
                  idx: index
                  on: root.powerFlag(index)
                  text: modelData
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
