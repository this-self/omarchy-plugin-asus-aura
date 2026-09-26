.pragma library

// Validate the complete shape before any QML binding consumes a snapshot.
// Hardware policy belongs to Python; these checks describe only the contract.
function integer(value) { return typeof value === "number" && isFinite(value) && Math.floor(value) === value }
function integers(values) { return Array.isArray(values) && values.every(integer) }
function strings(values) { return Array.isArray(values) && values.every(function(v) { return typeof v === "string" }) }
function colour(value) {
  return !!value && [value.red, value.green, value.blue].every(function(v) { return integer(v) && v >= 0 && v <= 255 })
}
function effect(value) {
  return !!value && integer(value.id) && typeof value.name === "string"
    && integer(value.colourCount) && value.colourCount >= 0 && value.colourCount <= 2
    && strings(value.fields) && strings(value.speeds) && strings(value.directions)
}
function power(value) {
  return !!value && typeof value.id === "string" && integer(value.zone)
    && typeof value.field === "string" && ["shared", "zone"].indexOf(value.scope) >= 0
    && typeof value.label === "string" && typeof value.target === "string"
    && typeof value.value === "boolean"
}
function parse(text) {
  var s = JSON.parse(text)
  var d = s && s.device, b = s && s.brightness, e = s && s.savedEffect
  if (!s || s.version !== 1 || typeof s.path !== "string"
      || !/^\/xyz\/ljones\/aura\/[A-Za-z0-9]+_[A-Za-z0-9_]+$/.test(s.path)
      || !d || !integer(d.type) || !integers(d.rgbZones) || !integers(d.powerZones)
      || !b || !integer(b.value) || !integers(b.levels) || !b.levels.length
      || b.levels.indexOf(b.value) < 0 || !integer(s.modeId)
      || !e || !integer(e.modeId) || !colour(e.colour1) || !colour(e.colour2)
      || typeof e.speed !== "string" || typeof e.direction !== "string"
      || !Array.isArray(s.effects) || !s.effects.every(effect)
      || ["global", "zoned", "unknown"].indexOf(s.zoneState) < 0
      || !Array.isArray(s.powerControls) || !s.powerControls.every(power))
    throw new Error("Invalid ASUS state response (expected protocol version 1)")
  return s
}
