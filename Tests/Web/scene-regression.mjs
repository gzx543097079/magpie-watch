// Runs the production scene's event lifecycle without a GPU. Render QA uses the app.
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const root = new URL('../../', import.meta.url);
class Element {
  style = {}; children = []; classList = { toggle() {} };
  append(...children) { this.children.push(...children); }
  remove() {}
  replaceChildren(...children) { this.children = children; }
  addEventListener() {}
  getContext() { return { createRadialGradient: () => ({ addColorStop() {} }), fillRect() {} }; }
}

export async function runSceneRegression() {
  const elements = new Map();
  const motion = { matches: false, addEventListener(_, callback) { this.changed = callback; } };
  let frame;
  const context = vm.createContext({
    console: { log() {}, warn() {}, error() {} }, URLSearchParams,
    innerWidth: 1920, innerHeight: 1080, devicePixelRatio: 1,
    location: { search: '', reload() {} }, addEventListener() {},
    matchMedia: () => motion, requestAnimationFrame: callback => { frame = callback; },
    document: {
      hidden: false, addEventListener() {}, createElement: () => new Element(),
      getElementById(id) { if (!elements.has(id)) elements.set(id, new Element()); return elements.get(id); }
    }
  });
  context.window = context; context.self = context;
  vm.runInContext(await readFile(new URL('design/three.min.js', root), 'utf8'), context);
  context.THREE.WebGLRenderer = class {
    info = { render: { calls: 0 } };
    setPixelRatio() {} setClearColor() {} setSize() {}
    render(scene, camera) { scene.updateMatrixWorld(); camera.updateMatrixWorld(); this.info.render.calls++; }
  };
  vm.runInContext(await readFile(new URL('design/starport.js', root), 'utf8'), context);
  let stamp = 100;
  const step = seconds => { for (let i = 0; i < seconds * 20; i++) frame(stamp += 50); };
  const state = () => context.magpieSceneState();
  const flow = (id, destinationID = 'm1') => ({ id, agentID: 'a', destinationID, stage: 'incoming', outcome: 'ok', requestTokens: 620, responseTokens: 80 });
  const payload = {
    agents: [{ id: 'a', name: 'Agent', calls: 2 }],
    models: [{ id: 'm1', name: 'Model 1' }, { id: 'm2', name: 'Model 2' }],
    online: true, flows: [flow('one'), flow('two', 'm2')], preview: false
  };
  context.setMagpieData({ ...payload, online: false }); step(.2);
  assert.equal(state().flights.length, 0, 'Offline payload must not create traffic');

  context.setMagpieData(payload); step(.5);
  assert.equal(state().flights.length, 2, 'Concurrent routes from the same agent must survive');
  assert.ok(state().flights.every(f => f.position[0] < 0), 'Input starts at the agent');
  const returning = { ...flow('one'), stage: 'returning' };
  context.setMagpieData({ ...payload, flows: [returning, flow('two', 'm2')] }); step(.3);
  const before = state().flights.find(f => f.id === 'one').position[0];
  assert.ok(before > 0, 'Output starts at the model');
  step(.6);
  assert.ok(state().flights.find(f => f.id === 'one').position[0] < before, 'Output travels back toward the agent');
  context.setMagpieData({ ...payload, flows: [] }); step(.2);
  assert.ok(state().flights.some(f => f.id === 'one'), 'A disappearing trace must not cut its return short');
  step(5);
  assert.ok(!state().flights.some(f => f.id === 'one'), 'Completed output must retire');
  context.setMagpieData({ ...payload, flows: [returning] });
  assert.ok(!state().flights.some(f => f.id === 'one'), 'Repeated polling must not replay a completed request');

  context.setMagpieData({ ...payload, accounts: [{ name: '<not-html>', account: 'masked', balance: '5 小时 剩余 22%', remainingPercent: 22 }], cacheTokens: 1000, cacheHitRate: 80, usageFresh: true, quotasFresh: true });
  assert.equal(elements.get('stat-hit').textContent, '80.0%');
  assert.equal(elements.get('accounts').children[0].children[0].textContent, '<not-html>');
  assert.equal(elements.get('accounts').children[0].children[3].children[0].style.width, '22%');
  context.setMagpieData({ ...payload, accounts: [], usageAvailable: false, cacheTokens: null, cacheHitRate: null });
  assert.equal(elements.get('stat-input').textContent, '—');
  assert.equal(elements.get('stat-hit').textContent, '—');

  context.setMagpieData({ ...payload, operationsFresh: true, operations: [{ purpose: '<call>', source: 'Agent → Model', status: '进行中 · 待结算', active: true, input: null, cache: 0, output: 18, context: '上下文主项 · 工具执行返回 1k tok' }] });
  const operation = elements.get('operations').children[0];
  assert.equal(operation.children[0].children[0].textContent, '<call>', 'Operation labels are plain text');
  assert.equal(operation.children[2].children[0].textContent, '入 —', 'Pending input must not be shown as zero');
  assert.equal(operation.children[2].children[1].textContent, '缓存 0', 'Measured zero must stay visible');
  context.setMagpieData({ ...payload, operationsFresh: false });
  assert.equal(elements.get('operations-fresh').textContent, '上次数据');

  motion.matches = true; motion.changed();
  const sceneTime = state().sceneTime; step(1);
  assert.equal(state().sceneTime, sceneTime, 'Reduce Motion must freeze environmental time');
  assert.ok(state().flights.every(f => !f.visible), 'Reduce Motion must hide moving packets');
  motion.matches = false; motion.changed();

  context.setMagpieData({ ...payload, preview: true }); step(6);
  assert.ok(state().flights.length > 1, 'Demo must retain overlapping requests');
  assert.ok(state().flights.every(f => f.id.startsWith('demo-')));
  assert.notEqual(elements.get('operations').children[0].children[0].children[0].textContent, '<call>', 'Demo must replace private live operations');
  context.setMagpieData(payload);
  assert.equal(state().preview, false);
  assert.ok(state().flights.every(f => !f.id.startsWith('demo-')), 'Leaving preview must clear all demo traffic');
  context.setMagpieData({ ...payload, online: false }); step(.1);
  assert.equal(state().flights.length, 0, 'Disconnect must clear active light streams');
  return 'Passed: offline, concurrency, both directions, completion, deduplication, Reduce Motion, demo isolation, desktop statistics and operation accounting';
}

if (typeof process !== 'undefined' && process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  console.log(await runSceneRegression());
}
