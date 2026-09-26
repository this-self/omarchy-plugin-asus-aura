.pragma library

// Presentation only: capabilities and shared/independent power semantics
// arrive from the backend rather than being inferred from hardware IDs.
function levelName(level, maximum) {
  if (level <= 0) return "Off"
  if (maximum <= 3) return level === 1 ? "Low" : (level === 2 ? "Medium" : "High")
  return String(level)
}
function effectTooltip(effect, zoneState) {
  var text = "Load saved " + effect.name + " settings; keep brightness."
  if (zoneState === "zoned")
    return text + "\nZoned lighting is preserved. Replace zones to edit colours."
  if (zoneState === "unknown")
    return text + "\nColour, speed and direction editing is locked.\nAllow read access to the asusd config to verify zone state."
  return text + "\nColour, speed and direction edits apply globally."
}
function powerTooltip(control) {
  var phase = {boot: "during boot", awake: "while awake", sleep: "during sleep", shutdown: "after shutdown"}[control.field]
  var text = (control.value ? "Disable " : "Enable ") + control.target + " lighting " + phase + "."
  if (control.scope === "shared")
    text += "\nShared setting: keyboard and lightbar change together."
  else if (control.field === "awake")
    text += "\nDoes not change boot or sleep settings."
  return text
}
