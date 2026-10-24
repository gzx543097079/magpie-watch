// JavaScriptCore 版场景回归（本机无 Node 时使用）：
// /System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc Tests/Web/scene-regression-jsc.js
// 在仓库根目录运行。只跑事件生命周期，不需要 GPU。
class Element {
  constructor() { this.style = {}; this.children = []; this.classList = { toggle() {} }; this.textContent = ''; this.className = ''; }
  append(...c) { this.children.push(...c); }
  remove() {}
  replaceChildren(...c) { this.children = c; }
  addEventListener() {}
  getContext() { return { createRadialGradient: () => ({ addColorStop() {} }), fillRect() {} }; }
}
const elements = new Map();
const motion = { matches: false, addEventListener(_, cb) { this.changed = cb; } };
let frame;
const g = globalThis;
g.window = g; g.self = g;
g.console = { log() {}, warn() {}, error() {} };
g.URLSearchParams = class { has() { return false; } };
g.innerWidth = 1920; g.innerHeight = 1080; g.devicePixelRatio = 1;
g.location = { search: '', reload() {} };
g.addEventListener = () => {};
g.matchMedia = () => motion;
g.requestAnimationFrame = cb => { frame = cb; };
g.document = {
  hidden: false, addEventListener() {}, createElement: () => new Element(),
  getElementById(id) { if (!elements.has(id)) elements.set(id, new Element()); return elements.get(id); }
};
load('design/three.min.js');
THREE.WebGLRenderer = class {
  constructor() { this.info = { render: { calls: 0 } }; }
  setPixelRatio() {} setClearColor() {} setSize() {}
  render(scene, camera) { scene.updateMatrixWorld(); camera.updateMatrixWorld(); this.info.render.calls++; }
};
load('design/starport.js');

function assert(ok, message) { if (!ok) throw new Error('FAIL: ' + message); }
let stamp = 100;
const step = s => { for (let i = 0; i < s * 20; i++) frame(stamp += 50); };
const state = () => magpieSceneState();
const flow = (id, destinationID = 'm1') => ({ id, agentID: 'a', destinationID, stage: 'incoming', outcome: 'ok', requestTokens: 620, responseTokens: 80 });
const payload = {
  agents: [{ id: 'a', name: 'Agent', calls: 2 }],
  models: [{ id: 'm1', name: 'Model 1' }, { id: 'm2', name: 'Model 2' }],
  online: true, flows: [flow('one'), flow('two', 'm2')], preview: false
};
setMagpieData({ ...payload, online: false }); step(.2);
assert(state().flights.length === 0, 'Offline payload must not create traffic');
assert(state().nodes === 0, 'Offline payload must not show nodes');

setMagpieData(payload); step(.5);
assert(state().flights.length === 2, 'Concurrent routes from the same agent must survive');
assert(state().flights.every(f => f.position[0] < 0), 'Input starts at the agent');
assert(state().nodes === 3, 'Active agent and both active models appear');
step(1.5);
assert(state().nodeList.every(n => n.appear === 1), 'Nodes finish their entrance');
const returning = { ...flow('one'), stage: 'returning' };
setMagpieData({ ...payload, flows: [returning, flow('two', 'm2')] }); step(.3);
const before = state().flights.find(f => f.id === 'one').position[0];
assert(before > 0, 'Output starts at the model');
step(.6);
assert(state().flights.find(f => f.id === 'one').position[0] < before, 'Output travels back toward the agent');
// Model 1 leaves the payload while its output is still returning: it must stay until the light lands.
setMagpieData({ ...payload, models: [{ id: 'm2', name: 'Model 2' }], flows: [flow('two', 'm2')] }); step(.2);
assert(state().flights.some(f => f.id === 'one'), 'A disappearing trace must not cut its return short');
assert(state().nodeList.some(n => n.key === '1:m1' && !n.leaving), 'A model with returning output stays visible');
step(5);
assert(!state().flights.some(f => f.id === 'one'), 'Completed output must retire');
step(2);
assert(!state().nodeList.some(n => n.key === '1:m1'), 'Inactive model fades out and is removed');
setMagpieData({ ...payload, flows: [returning] });
assert(!state().flights.some(f => f.id === 'one'), 'Repeated polling must not replay a completed request');

setMagpieData({ ...payload, accounts: [{ name: '<not-html>', account: 'masked', balance: '5 小时 剩余 22%', remainingPercent: 22 }], cacheTokens: 1000, cacheHitRate: 80, usageFresh: true, quotasFresh: true });
assert(elements.get('stat-hit').textContent === '80.0%', 'cache hit');
assert(elements.get('accounts').children[0].children[0].textContent === '<not-html>', 'account text');
assert(elements.get('accounts').children[0].children[3].children[0].style.width === '22%', 'meter');
setMagpieData({ ...payload, accounts: [], usageAvailable: false, cacheTokens: null, cacheHitRate: null, dashboard: null });
assert(elements.get('stat-input').textContent === '—', 'unmeasured input');
assert(elements.get('periods').children[1].children[1].textContent === '待计量', 'Missing week total says pending, not zero');

const dashboard = { periods: [{ label: '今日', total: 1300, input: 100, output: 50, cacheRead: 900, cacheWrite: 250, cacheShare: 90, calls: 3, cost: 1.5 }, null, null],
  calls: 3, errors: 1, retried: 0, sessions: 2, cost: 1.5, reasoning: 10, ttftMs: 1500, decodeRate: 42.4,
  hours: [{ label: '0', calls: 2, errors: 1, input: 0, output: 0 }, { label: '1', calls: 0, errors: 0, input: 0, output: 0 }],
  agents: [{ name: '<agent>', sub: '智能体', calls: 3, errors: 1, tokens: 1300, cost: 1.5, share: 1 }], models: [] };
setMagpieData({ ...payload, dashboard });
assert(elements.get('periods').children[0].children[1].textContent === '1.3k', 'Today total');
assert(elements.get('efficiency').children[6].children[1].textContent === '1.50 s', 'Average TTFT');
assert(elements.get('efficiency').children[7].children[1].textContent === '42 tok/s', 'Decode rate');
assert(elements.get('hours').children.length === 2, 'Hourly bars');
assert(elements.get('rank-agents').children[0].children[0].textContent === '<agent>', 'Rank names stay plain text');
assert(elements.get('rank-models').children[0].textContent === '等待今日调用', 'Empty rank state');

setMagpieData({ ...payload, operationsFresh: true, operations: [{ purpose: '<call>', source: 'Agent → Model', status: '进行中 · 待结算', active: true, input: null, cache: 0, output: 18, context: 'x' }] });
const operation = elements.get('operations').children[0];
assert(operation.children[0].children[0].textContent === '<call>', 'Operation labels are plain text');
assert(operation.children[2].children[0].textContent === '入 —', 'Pending input must not be shown as zero');
assert(operation.children[2].children[1].textContent === '缓存 0', 'Measured zero must stay visible');

motion.matches = true; motion.changed();
const sceneTime = state().sceneTime; step(1);
assert(state().sceneTime === sceneTime, 'Reduce Motion must freeze environmental time');
assert(state().flights.every(f => !f.visible), 'Reduce Motion must hide moving packets');
motion.matches = false; motion.changed();

setMagpieData({ ...payload, preview: true }); step(6);
assert(state().flights.length > 1, 'Demo must retain overlapping requests');
assert(state().flights.every(f => f.id.startsWith('demo-')), 'demo ids');
setMagpieData(payload);
assert(state().preview === false, 'leave preview');
assert(state().flights.every(f => !f.id.startsWith('demo-')), 'Leaving preview must clear all demo traffic');
setMagpieData({ ...payload, online: false }); step(2);
assert(state().flights.length === 0, 'Disconnect must clear active light streams');
assert(state().nodes === 0, 'Disconnect fades every node out');
print('Passed: offline, active-only nodes, concurrency, both directions, node linger, dashboard, Reduce Motion, demo isolation');
