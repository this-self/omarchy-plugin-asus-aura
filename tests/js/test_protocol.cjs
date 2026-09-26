const assert = require('node:assert/strict');
const {load, plain, fixture} = require('./load.cjs');
const protocol = load('qml/transport/BackendProtocol.js');
const presentation = load('qml/ui/Presentation.js');
const state = fixture();
assert.deepEqual(plain(protocol.parse(JSON.stringify(state))), state);
for (const mutate of [
  s => { s.version = 2; }, s => { s.path = '/bad'; }, s => { s.brightness.levels = []; },
  s => { s.savedEffect.colour1 = [0, 0, 0]; }, s => { s.savedEffect.colour1.red = 256; },
  s => { s.effects[0].fields = null; }, s => { s.device = null; },
  s => { s.powerControls[0].value = 'false'; }, s => { s.zoneState = null; }
]) {
  const invalid = fixture();
  mutate(invalid);
  assert.throws(() => protocol.parse(JSON.stringify(invalid)), /Invalid ASUS state/);
}
for (const text of ['', '{', 'null', '{}']) assert.throws(() => protocol.parse(text));
assert.match(presentation.effectTooltip(state.effects[1], 'global'), /saved Breathe settings; keep brightness/);
assert.match(presentation.effectTooltip(state.effects[1], 'global'), /apply globally/);
assert.match(presentation.effectTooltip(state.effects[1], 'zoned'), /Zoned lighting is preserved/);
assert.match(presentation.effectTooltip(state.effects[1], 'unknown'), /editing is locked/);
assert.match(presentation.effectTooltip(state.effects[1], 'unknown'), /read access/);
assert.match(presentation.powerTooltip(state.powerControls[0]), /Disable keyboard and lightbar lighting during boot/);
assert.match(presentation.powerTooltip(state.powerControls[0]), /change together/);
assert.match(presentation.powerTooltip(state.powerControls[1]), /Enable keyboard and lightbar lighting during sleep/);
assert.match(presentation.powerTooltip(state.powerControls[2]), /Does not change boot or sleep/);
assert.match(presentation.powerTooltip({scope: 'zone', target: 'keyboard', field: 'shutdown', value: false}), /Enable keyboard lighting after shutdown/);
assert.equal(presentation.levelName(0, 3), 'Off');
assert.equal(presentation.levelName(2, 3), 'Medium');
assert.equal(presentation.levelName(5, 10), '5');
console.log('Backend contract and presentation tests passed');
