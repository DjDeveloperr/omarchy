#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const vm = require('node:vm');
const fs = require('node:fs');
const strictAssert = require('node:assert/strict');
const source = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8');
const names = ['armBlankTimer', 'runWake', 'runBlank', 'reconcileDisplayPower', 'displayPowerFinished'];
const functions = names.map(name => {
  const start = source.indexOf('  function ' + name + '(');
  strictAssert(start >= 0, 'missing function ' + name);
  const body = source.indexOf('{', start);
  let depth = 1, end = body + 1;
  while (depth && end < source.length) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
    end++;
  }
  return source.slice(start, end);
}).join('\n');

function fixture() {
  const ctx = {
    Date,
    nudgeFingerprint() {},
    idleBlankTimer: {running: false, restarts: 0, stop() {this.running = false;}, restart() {this.running = true; this.restarts++;}},
    displayPowerProcess: {running: false, operation: '', command: []},
    root: {lockRequested: true, requestedDisplayPower: '', logEvent() {}},
  };
  vm.createContext(ctx);
  vm.runInContext(functions + '\n' + names.map(n => 'root.' + n + ' = ' + n + ';').join('\n'), ctx);
  ctx.finish = () => {
    const operation = ctx.displayPowerProcess.operation;
    strictAssert(ctx.displayPowerProcess.running);
    ctx.displayPowerProcess.running = false;
    ctx.root.displayPowerFinished(operation, 0);
  };
  return ctx;
}

// A stale blank cannot finish after the most recent wake: the wake is queued.
{
  const t = fixture();
  t.root.runBlank();
  t.root.runWake();
  strictAssert.equal(t.displayPowerProcess.operation, 'blank');
  strictAssert.equal(t.idleBlankTimer.running, false);
  t.finish();
  strictAssert.equal(t.displayPowerProcess.operation, 'wake');
  strictAssert.equal(t.displayPowerProcess.running, true);
  strictAssert.equal(t.idleBlankTimer.running, false);
  t.finish();
  strictAssert.equal(t.root.displaysBlank, false);
  strictAssert.equal(t.idleBlankTimer.running, true);
  strictAssert.equal(t.idleBlankTimer.restarts, 1);
}
// Repeated wake events coalesce and start the blank countdown only on completion.
{
  const t = fixture();
  t.root.runWake();
  t.root.runWake();
  strictAssert.equal(t.idleBlankTimer.restarts, 0);
  t.finish();
  strictAssert.equal(t.displayPowerProcess.running, false);
  strictAssert.equal(t.idleBlankTimer.restarts, 1);
}
// Unlocking with a blank in flight also finishes at wake, without another timer.
{
  const t = fixture();
  t.root.runBlank();
  t.root.lockRequested = false;
  t.root.runWake();
  t.finish();
  strictAssert.equal(t.displayPowerProcess.operation, 'wake');
  t.finish();
  strictAssert.equal(t.idleBlankTimer.running, false);
}
pass('stale blank/wake ordering, repeated wake, countdown after completion, unlock ordering')
JS
