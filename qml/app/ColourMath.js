.pragma library

// RGB is a named value; hue is degrees, saturation/value are in 0..1.
function hsvToRgb(h, s, v) {
  var f = function(n) {
    var k = (n + h / 60) % 6
    return Math.round((v - v * s * Math.max(0, Math.min(k, 4 - k, 1))) * 255)
  }
  return {red: f(5), green: f(3), blue: f(1)}
}

function rgbToHsv(colour) {
  var r = colour.red / 255, g = colour.green / 255, b = colour.blue / 255
  var mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn, h = 0
  if (d) {
    if (mx === r) h = ((g - b) / d) % 6
    else if (mx === g) h = (b - r) / d + 2
    else h = (r - g) / d + 4
    h *= 60
    if (h < 0) h += 360
  }
  return {h: h, s: mx ? d / mx : 0, v: mx}
}

function valid(colour) {
  return !!colour && [colour.red, colour.green, colour.blue].every(function(v) {
    return typeof v === "number" && isFinite(v) && Math.round(v) === v && v >= 0 && v <= 255
  })
}
function hex(colour) {
  return "#" + [colour.red, colour.green, colour.blue].map(function(v) {
    var s = Math.max(0, Math.min(255, Math.round(v))).toString(16)
    return s.length < 2 ? "0" + s : s
  }).join("")
}
function fromHex(value) {
  if (typeof value !== "string" || !/^#[0-9a-fA-F]{6}$/.test(value)) return null
  return {red: parseInt(value.slice(1, 3), 16), green: parseInt(value.slice(3, 5), 16), blue: parseInt(value.slice(5, 7), 16)}
}
function hsvHex(h, s, v) { return hex(hsvToRgb(h, s, v)) }
