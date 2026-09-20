.pragma library

// Capability table matches asusctl/ROG Control Center 6.4, not every field
// that happens to exist in the generic AuraEffect D-Bus structure.
var modes = {
  "0":  {name: "Static", c1: true, c2: false, spd: false, dir: false},
  "1":  {name: "Breathe", c1: true, c2: true, spd: true, dir: false},
  "2":  {name: "Rainbow", c1: false, c2: false, spd: true, dir: false},
  "3":  {name: "Wave", c1: false, c2: false, spd: true, dir: true},
  "4":  {name: "Stars", c1: true, c2: true, spd: true, dir: false},
  "5":  {name: "Rain", c1: false, c2: false, spd: true, dir: false},
  "6":  {name: "Highlight", c1: true, c2: false, spd: true, dir: false},
  "7":  {name: "Laser", c1: true, c2: false, spd: true, dir: false},
  "8":  {name: "Ripple", c1: true, c2: false, spd: true, dir: false},
  "10": {name: "Pulse", c1: true, c2: false, spd: false, dir: false},
  "11": {name: "Comet", c1: true, c2: false, spd: false, dir: false},
  "12": {name: "Flash", c1: true, c2: false, spd: false, dir: false}
}

function modeInfo(id) {
  return modes[String(id)] || {name: "Mode " + id, c1: false, c2: false, spd: false, dir: false}
}

function effectTooltip(mode, multizone) {
  var text = "Load saved " + modeInfo(mode).name + " settings; keep brightness."
  if (multizone === true)
    return text + "\nZoned lighting is preserved. Replace zones to edit colours."
  if (multizone === null)
    return text + "\nColour, speed and direction editing is locked.\nAllow read access to the asusd config to verify zone state."
  return text + "\nColour, speed and direction edits apply globally."
}

function powerTooltip(control) {
  var phase = {boot: "during boot", awake: "while awake", sleep: "during sleep", shutdown: "after shutdown"}[control.field]
  var target = control.zone === -1 ? "keyboard and lightbar" : zoneName(control.zone).toLowerCase()
  var text = (control.on ? "Disable " : "Enable ") + target + " lighting " + phase + "."
  if (control.zone === -1)
    text += "\nShared setting: keyboard and lightbar change together."
  else if (control.field === "awake")
    text += "\nDoes not change boot or sleep settings."
  return text
}

function colourSlot(mode, selected) { return modeInfo(mode).c2 && selected === 2 ? 2 : 1 }

function zoneName(zone) {
  return ({0: "Logo", 1: "Keyboard", 2: "Lightbar", 3: "Lid", 4: "Rear glow", 5: "Keyboard + lightbar", 6: "Ally"})[zone] || "Zone " + zone
}

function powerControls(device, supported, rows) {
  var controls = []
  var fields = ["boot", "awake", "sleep", "shutdown"]
  var labels = ["Boot", "Awake", "Sleep", "Shutdown"]
  var valid = rows.filter(function(row) { return supported.indexOf(row[0]) >= 0 })
  if (device === 1) {
    if (valid.length) {
      controls.push({zone: -1, field: "boot", label: "Shared boot", on: rows.some(function(r) { return r[1] })})
      controls.push({zone: -1, field: "sleep", label: "Shared sleep", on: rows.some(function(r) { return r[3] })})
    }
    valid.forEach(function(row) {
      if ([1, 2, 5].indexOf(row[0]) >= 0)
        controls.push({zone: row[0], field: "awake", label: zoneName(row[0]) + " awake", on: row[2]})
    })
  } else if ([0, 2, 4].indexOf(device) >= 0) {
    if (device === 2) valid = valid.slice(0, 1)
    valid.forEach(function(row) {
      fields.forEach(function(field, i) {
        if (device !== 2 || field !== "shutdown")
          controls.push({zone: row[0], field: field, label: zoneName(row[0]) + " " + labels[i].toLowerCase(), on: row[i + 1]})
      })
    })
  }
  return controls
}

function changePower(rows, control, value) {
  var index = ["boot", "awake", "sleep", "shutdown"].indexOf(control.field) + 1
  return rows.map(function(row) {
    var next = row.slice()
    if (control.zone === -1 || row[0] === control.zone) next[index] = value
    return next
  })
}
