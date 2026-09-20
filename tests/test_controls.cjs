const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.join(__dirname, '..');
const controls = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(root, 'Controls.js'), 'utf8').replace('.pragma library', ''), controls);
const plain = x => JSON.parse(JSON.stringify(x));
const rows = [[1, false, true, false, false], [2, true, true, false, true]];
const old = plain(controls.powerControls(1, [1, 2], rows));
assert.deepEqual(old.map(x => [x.zone, x.field, x.on]), [
  [-1, 'boot', true], [-1, 'sleep', false], [1, 'awake', true], [2, 'awake', true]
]);
assert.deepEqual(plain(controls.changePower(rows, old[0], false)), [
  [1, false, true, false, false], [2, false, true, false, true]
]);
assert.equal(rows[1][1], true, 'must not mutate the old rows');
assert.equal(controls.powerControls(0, [1, 2], rows).length, 8);
assert.equal(controls.powerControls(2, [1], rows).length, 3);
assert.equal(controls.powerControls(255, [1, 2], rows).length, 0);
assert.equal(controls.colourSlot(1, 2), 2);
assert.equal(controls.colourSlot(0, 2), 1);
assert.equal(controls.colourSlot(10, 2), 1);
assert.equal(controls.modeInfo(10).spd, false);
assert.equal(controls.modeInfo(1).spd, true);
assert.equal(controls.modeInfo(3).dir, true);
assert.equal(controls.modeInfo(999).c1, false);

// Exercise the actual queue functions from Commands.qml, with fake processes.
const qml = fs.readFileSync(path.join(root, 'Commands.qml'), 'utf8');
const functions = qml.slice(qml.indexOf('  function fail('), qml.indexOf('\n  Process {'));
const ctx = vm.createContext({
  console, auraPath: '/test', queue: [], activeRequest: null, revision: 0,
  readRevision: 0, modePending: false, helper: '/helper', errorMessage: '',
  writeProc: {running: false}, stateProc: {running: false}, failed() {},
});
ctx.commands = ctx;
Object.defineProperties(ctx, {
  writing: {get: () => ctx.activeRequest !== null || ctx.queue.length > 0},
  reading: {get: () => ctx.stateProc.running},
  resyncing: {get: () => ctx.activeRequest?.kind === 'resync'},
});
vm.runInContext(functions, ctx);
ctx.setBrightness(1);
assert.equal(ctx.activeRequest.value, 1);
ctx.setBrightness(2);
ctx.setBrightness(3);
assert.deepEqual(plain(ctx.queue).map(x => x.value), [3], 'latest pending brightness wins');
ctx.setMode(1);
ctx.setBrightness(0);
assert.deepEqual(plain(ctx.queue).map(x => x.kind), ['brightness', 'mode', 'brightness'], 'never coalesce across a mode barrier');
assert.equal(ctx.modePending, true);
ctx.setEffect(1, 'colour1', [1, 2, 3]);
ctx.setEffect(1, 'colour1', [4, 5, 6]);
ctx.setEffect(1, 'colour2', [7, 8, 9]);
assert.deepEqual(plain(ctx.queue.slice(-2)).map(x => x.field), ['colour1', 'colour2']);
assert.deepEqual(plain(ctx.queue.slice(-2))[0].value, [4, 5, 6]);
let count = 1;
while (ctx.queue.length) {
  ctx.activeRequest = null;
  ctx.writeProc.running = false;
  ctx.pump();
  assert.equal(ctx.writeProc.running, true);
  count++;
}
assert.equal(count, 6, 'all ordered writes drain');
ctx.activeRequest = null;
ctx.writeProc.running = false;
ctx.refresh();
assert.equal(ctx.stateProc.running, true);
assert.equal(ctx.readRevision, ctx.revision);
ctx.stateProc.running = false;
assert.equal(ctx.resync(), false, 'resync waits for write readback');
ctx.syncPending = false; // successful readback (handler is tested below)
assert.equal(ctx.resync(), true);
assert.equal(ctx.setBrightness(2), false, 'resync blocks edits');

// Execute the real process-exit handlers as well: failures cancel dependent
// writes, and a stale read must not stomp an optimistic update.
const exits = [...qml.matchAll(/Component\.onCompleted: exited\.connect\(function\(code\) \{([\s\S]*?)\n    \}\)/g)];
assert.equal(exits.length, 2);
ctx.settle = {restart() { ctx.settles = (ctx.settles || 0) + 1; }};
ctx.stateOutput = {text: JSON.stringify({available: true, path: '/test'})};
ctx.stateErrors = {text: ''};
ctx.writeErrors = {text: 'test failure'};
ctx.stateReceived = state => { ctx.received = state; };
const readExit = vm.runInContext('(function(code) {' + exits[0][1] + '})', ctx);
const writeExit = vm.runInContext('(function(code) {' + exits[1][1] + '})', ctx);
ctx.queue = [{kind: 'effect'}];
writeExit(1);
assert.equal(ctx.queue.length, 0);
assert.equal(ctx.activeRequest, null);
assert.match(ctx.errorMessage, /test failure/);
assert.equal(ctx.resyncStatus, ctx.errorMessage);
ctx.readRevision = ctx.revision - 1;
readExit(0);
assert.equal(ctx.received, undefined, 'stale poll discarded');
ctx.readRevision = ctx.revision;
readExit(0);
assert.equal(ctx.received.available, true);
assert.equal(ctx.syncPending, false);
assert.match(ctx.errorMessage, /test failure/, 'successful refresh must not hide write errors');
ctx.stateErrors.text = 'offline';
readExit(1);
assert.equal(ctx.auraPath, '');
assert.equal(ctx.received.available, false);
assert.match(ctx.errorMessage, /offline/);
readExit(0);
assert.equal(ctx.errorMessage, '', 'read errors clear on recovery');
console.log('Controls, queue, failure recovery and stale-read tests passed');
