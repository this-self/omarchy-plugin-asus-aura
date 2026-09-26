const assert = require('node:assert/strict');
const {load, plain} = require('./load.cjs');
const colour = load('qml/app/ColourMath.js');
assert.deepEqual(plain(colour.hsvToRgb(0, 1, 1)), {red: 255, green: 0, blue: 0});
assert.deepEqual(plain(colour.hsvToRgb(120, 1, 1)), {red: 0, green: 255, blue: 0});
assert.deepEqual(plain(colour.hsvToRgb(240, 0.5, 1)), {red: 128, green: 128, blue: 255});
assert.deepEqual(plain(colour.hsvToRgb(200, 0, 0.5)), {red: 128, green: 128, blue: 128});
assert.equal(colour.rgbToHsv({red: 0, green: 0, blue: 255}).h, 240);
assert.equal(colour.rgbToHsv({red: 0, green: 0, blue: 0}).s, 0);
for (const c of [{red: 127, green: 187, blue: 179}, {red: 255, green: 127, blue: 0}, {red: 12, green: 34, blue: 56}]) {
  const t = colour.rgbToHsv(c);
  assert.deepEqual(plain(colour.hsvToRgb(t.h, t.s, t.v)), c);
  assert.deepEqual(plain(colour.fromHex(colour.hex(c))), c);
}
assert.deepEqual(plain(colour.fromHex('#aB00fF')), {red: 171, green: 0, blue: 255});
for (const invalid of ['#fff', 'ff0000', '#gg0000', '#00000000', '', null]) assert.equal(colour.fromHex(invalid), null);
for (const invalid of [null, {}, {red: 256, green: 0, blue: 0}, {red: 1.1, green: 0, blue: 0}, {red: true, green: 0, blue: 0}]) assert.equal(colour.valid(invalid), false);
console.log('Colour conversion and validation tests passed');
