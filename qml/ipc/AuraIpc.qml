import QtQuick
import Quickshell.Io
import "../app" as App
import "../app/ColourMath.js" as Colour

// Keep injected objects/signals outside IpcHandler: Quickshell interprets the
// handler's own properties and methods as part of the public IPC interface.
QtObject {
  id: root
  required property App.AuraController controller
  signal openRequested()
  signal closeRequested()
  signal toggleRequested()

  readonly property IpcHandler handler: IpcHandler {
    target: "this-self.asus-aura"

    function set(level: string): string { return root.controller.setBrightness(Number(level)) ? "queued" : "invalid, busy or unavailable" }
    function up(): string { return root.controller.adjustBrightness(1) ? "queued" : "busy or unavailable" }
    function down(): string { return root.controller.adjustBrightness(-1) ? "queued" : "busy or unavailable" }
    function resync(): string { return root.controller.resync() ? "started" : "busy or unavailable" }
    function mode(m: string): string { return root.controller.selectMode(Number(m)) ? "queued" : "unsupported, busy or unavailable" }
    function colour(hex: string): string { return root.controller.applyHex(hex) ? "queued" : "invalid, busy or global effect editing unavailable" }
    function speed(value: string): string { return root.controller.setSpeed(value) ? "queued" : "unsupported, busy or unavailable" }
    function direction(value: string): string { return root.controller.setDirection(value) ? "queued" : "unsupported, busy or unavailable" }
    function globalEffect(): string { return root.controller.replaceZones() ? "queued" : "busy or unavailable" }
    function colourSlot(slot: string): string { return root.controller.selectColourSlot(Number(slot)) ? "selected" : "unsupported colour slot" }
    function power(zone: string, field: string, enabled: string): string {
      if (enabled !== "true" && enabled !== "false") return "expected true or false"
      return root.controller.setPower(Number(zone), field, enabled === "true") ? "queued" : "unsupported, busy or unavailable"
    }
    function state(): string {
      var c = root.controller
      var mode = c.currentMode
      return JSON.stringify({
        available: c.available, level: c.level, max: c.maxLevel,
        resyncing: c.resyncing, resyncStatus: c.resyncStatus,
        mode: c.mode, modeName: mode.name, pending: c.pending,
        error: c.errorMessage, deviceType: c.display.device.type,
        zones: c.display.device.rgbZones,
        multizone: c.zoneState === "unknown" ? null : c.zoneState === "zoned",
        effectEditable: c.effectEditable,
        colour1: c.effectEditable && mode.colourCount >= 1 ? Colour.hex(c.effect.colour1) : null,
        colour2: c.effectEditable && mode.colourCount >= 2 ? Colour.hex(c.effect.colour2) : null,
        speed: c.effectEditable && mode.speeds.length ? c.effect.speed : null,
        direction: c.effectEditable && mode.directions.length ? c.effect.direction : null,
        power: c.powerControls.map(function(p) { return {zone: p.zone, field: p.field, label: p.label, on: p.value} })
      })
    }
    function open(): void { root.openRequested() }
    function close(): void { root.closeRequested() }
    function toggle(): void { root.toggleRequested() }
  }
}
