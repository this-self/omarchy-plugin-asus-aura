const assert = require('node:assert/strict');
const {load, plain, fixture} = require('./load.cjs');
const queue = load('qml/transport/RequestQueue.js');
const snapshot = fixture();
function ready() {
  return queue.finishRead(queue.startRead(queue.create()), snapshot, '').state;
}

assert.equal(queue.enqueue(queue.create(), {kind: 'brightness', value: 1}), null);
let state = ready();
const original = state;
state = queue.startWrite(queue.enqueue(state, {kind: 'brightness', value: 1}));
assert.equal(original.pending.length, 0, 'transitions do not mutate old state');
assert.equal(state.active.value, 1);
state = queue.enqueue(state, {kind: 'brightness', value: 2});
state = queue.enqueue(state, {kind: 'brightness', value: 3});
assert.deepEqual(plain(state.pending).map(r => r.value), [3]);
state = queue.enqueue(state, {kind: 'mode', value: 1});
state = queue.enqueue(state, {kind: 'brightness', value: 0});
assert.deepEqual(plain(state.pending).map(r => r.kind), ['brightness', 'mode', 'brightness']);
assert.equal(state.modePending, true);
state = queue.enqueue(state, {kind: 'effect', mode: 1, field: 'colour1', value: [1, 2, 3]});
state = queue.enqueue(state, {kind: 'effect', mode: 1, field: 'colour1', value: [4, 5, 6]});
state = queue.enqueue(state, {kind: 'effect', mode: 1, field: 'colour2', value: [7, 8, 9]});
assert.deepEqual(plain(state.pending.slice(-2)).map(r => r.field), ['colour1', 'colour2']);
assert.deepEqual(plain(state.pending.slice(-2))[0].value, [4, 5, 6]);
let count = 0;
while (state.active || state.pending.length) {
  state = queue.startWrite(state);
  state = queue.finishWrite(state, '');
  count++;
}
assert.equal(count, 6);
assert.equal(state.modePending, true, 'mode lock extends through final readback');
assert.equal(state.syncPending, true);
assert.equal(queue.enqueue(state, {kind: 'resync'}), null);
state = queue.startRead(state);
assert.equal(state.readRevision, state.revision);
state = queue.finishRead(state, snapshot, '').state;
assert.equal(state.modePending, false);
assert.equal(state.syncPending, false);
state = queue.startWrite(queue.enqueue(state, {kind: 'resync'}));
assert.equal(queue.resyncing(state), true);
assert.equal(queue.enqueue(state, {kind: 'brightness', value: 2}), null);
state = queue.finishWrite(state, 'test failure');
assert.equal(state.active, null);
assert.equal(state.resyncStatus, state.error);
state = queue.finishRead(queue.startRead(state), snapshot, '').state;
assert.match(state.error, /test failure/, 'readback retains write errors');

state = ready();
state = queue.startRead(state);
state = queue.startWrite(queue.enqueue(state, {kind: 'mode', value: 2}));
state = queue.enqueue(state, {kind: 'brightness', value: 3});
const stale = queue.finishRead(state, snapshot, 'old read failure');
assert.equal(stale.stale, true);
assert.equal(stale.state.modePending, true);
assert.equal(stale.state.path, snapshot.path);
assert.equal(stale.state.error, '');
state = queue.finishWrite(stale.state, 'mode failed');
assert.equal(state.pending.length, 0, 'failure cancels dependent writes');
state = queue.finishRead(queue.startRead(state), snapshot, '').state;
assert.match(state.error, /mode failed/);
state = queue.finishRead(queue.startRead(state), null, 'offline').state;
assert.equal(state.path, '');
assert.equal(state.error, 'Read: offline');
state = queue.finishRead(queue.startRead(state), snapshot, '').state;
assert.equal(state.error, '', 'read errors clear on recovery');

// A stale read can also finish after all newer writes have already drained.
state = queue.startRead(ready());
state = queue.finishWrite(queue.startWrite(queue.enqueue(state, {kind: 'brightness', value: 1})), '');
assert.equal(queue.finishRead(state, snapshot, '').stale, true);

// Different modes, power targets and field barriers must not coalesce.
state = ready();
for (const request of [
  {kind: 'effect', mode: 1, field: 'colour1'}, {kind: 'effect', mode: 4, field: 'colour1'},
  {kind: 'power', zone: 1, field: 'awake'}, {kind: 'power', zone: 2, field: 'awake'},
  {kind: 'power', zone: 2, field: 'boot'}, {kind: 'power', zone: 2, field: 'awake'}
]) state = queue.enqueue(state, request);
assert.equal(state.pending.length, 6);
assert.equal(queue.startRead(state), state, 'no poll starts while writes are pending');
console.log('Queue ordering, barriers, recovery and revision tests passed');
