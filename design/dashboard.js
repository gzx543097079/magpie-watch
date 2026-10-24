/* Magpie 观测台 · 直接读取本地网关原始 JSON。
   字段不做 Swift 投影：Magpie 加字段时页面立即能显示。 */
(() => {
  'use strict';

  const WHY = { log: '读自日志', clock: '估算', low: '低置信' };
  const POLL_MS = 4000;

  const $ = (id) => document.getElementById(id);
  const compact = (v) => v == null ? '—' : new Intl.NumberFormat('en', { notation: 'compact', maximumFractionDigits: 2 }).format(v);
  const money = (v) => v == null ? '—' : '$' + v.toFixed(2);
  const integer = (v) => v == null ? '—' : Math.round(v).toLocaleString('en');
  const full = (v) => v == null ? '—' : Math.round(v).toLocaleString('en');
  const pct = (v) => v == null ? '—' : (v % 1 === 0 ? v.toFixed(0) : v.toFixed(1)) + '%';
  const share = (a, b) => (!b ? 0 : Math.max(0, Math.min(100, a / b * 100)));

  /* DeepSeek 官方单价（美元 / 百万 token）。Magpie 侧这些调用记在免费额度上，
     所以 cost 恒为 0；这里按官方价折算，只用来回答「白用了多少美元」。 */
  const DS_PRICE = {
    'deepseek-v4.1-flash': { hit: 0.0028, miss: 0.14, out: 0.28 },
    'deepseek-v4.1-pro': { hit: 0.003625, miss: 0.435, out: 0.87 }
  };
  const DS_FALLBACK = { hit: 0.0028, miss: 0.14, out: 0.28 };
  const isDeepSeek = (m) => /deepseek/i.test(m.id || '') || /deepseek/i.test(m.model || '');
  const dsPrice = (m) => DS_PRICE[m.model || ''] || DS_PRICE[String(m.id || '').split('/').pop()] || DS_FALLBACK;
  const dsUsd = (m) => {
    const p = dsPrice(m);
    return ((m.cache_read || 0) * p.hit + (m.input || 0) * p.miss + (m.output || 0) * p.out) / 1e6;
  };

  let maskOn = true;
  let settleTimer = 0;
  let online = true;
  let lastGood = null;

  const mask = (value) => {
    if (!value) return '';
    const text = String(value);
    if (!maskOn || !text.includes('@')) return text;
    const [local, domain] = text.split('@');
    return (local.length > 3 ? local.slice(0, 3) + '…' : '…') + '@' + domain;
  };

  const clockOf = (iso) => {
    if (!iso) return '—';
    const d = new Date(iso);
    if (isNaN(d)) return '—';
    const hm = d.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' });
    return d.toDateString() === new Date().toDateString()
      ? hm
      : (d.getMonth() + 1) + '/' + d.getDate() + ' ' + hm;
  };

  /** 重置倒计时短版：给用尽账号的大数字用（37 分钟 / 2.5 小时 / 3 天）。 */
  const resetShort = (iso) => {
    if (!iso) return '—';
    const d = new Date(iso);
    if (isNaN(d)) return '—';
    const mins = (d - Date.now()) / 60000;
    if (mins < 0) return '待刷新';
    if (mins < 60) return Math.max(1, Math.round(mins)) + ' 分钟';
    if (mins < 2880) return (mins / 60).toFixed(1) + ' 小时';
    return Math.round(mins / 1440) + ' 天';
  };

  const resetText = (iso) => {
    if (!iso) return '无重置';
    const d = new Date(iso);
    if (isNaN(d)) return '—';
    const mins = Math.round((d - Date.now()) / 60000);
    if (mins < 0) return '待刷新';
    if (mins < 90) return mins + ' 分钟后重置';
    if (mins < 2160) return Math.round(mins / 60) + ' 小时后重置';
    return Math.round(mins / 1440) + ' 天后重置';
  };

  const el = (tag, cls, text) => {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text != null) node.textContent = text;
    return node;
  };

  /* 数值变化的辉光短闪：只挂在刚写过的读数上，不闪没变的。 */
  const flash = (node) => { node.classList.remove('tick'); void node.offsetWidth; node.classList.add('tick'); };
  const put = (id, text) => {
    const node = $(id);
    if (node.textContent !== text) { node.textContent = text; flash(node); }
  };

  /** 复用同 key 的 DOM，避免每轮轮询重建导致闪烁。 */
  function keyed(box, items, keyOf, create, update) {
    const existing = new Map([...box.children].map((node) => [node.dataset.key, node]));
    items.forEach((item, i) => {
      const key = String(keyOf(item, i));
      let node = existing.get(key);
      if (!node) {
        node = create(item);
        node.dataset.key = key;
      }
      existing.delete(key);
      if (box.children[i] !== node) box.insertBefore(node, box.children[i] || null);
      update(node, item, i);
    });
    existing.forEach((node) => node.remove());
  }

  async function get(path) {
    const response = await fetch(path, { cache: 'no-store' });
    if (!response.ok) throw new Error(path + ' → ' + response.status);
    return response.json();
  }

  /* ── 今日 ── */
  function renderToday(today, week, month, daily) {
    put('cost', money(today.cost));
    $('today-note').textContent =
      integer(today.calls) + ' 次 · ' + compact((today.input || 0) + (today.output || 0) + (today.cache_read || 0)) + ' 令牌';

    // 缓存命中率：命中读 / (新输入 + 命中读)。这是唯一能说明「省了多少」的比率。
    const hit = today.cache_read || 0;
    const billed = (today.input || 0) + hit;
    const rate = share(hit, billed);
    put('cache-rate', billed ? pct(rate) : '—');
    $('cache-bar').style.width = rate + '%';
    $('cache-sub').textContent = billed
      ? compact(hit) + ' 命中 / ' + compact(billed) + ' 输入'
      : '今日还没有输入';

    // DeepSeek 等价美元：官方价折算（Magpie 侧实记免费），进五格读数。
    const ds = (today.models || []).filter(isDeepSeek);
    const usd = ds.reduce((s, m) => s + dsUsd(m), 0);
    const dsCalls = ds.reduce((s, m) => s + (m.calls || 0), 0);

    // 迷你仪表：生成速度 / 首字。
    put('mini-speed', today.decode_ms ? Math.round(today.decode_out / (today.decode_ms / 1000)) + ' 字/秒' : '—');
    put('mini-ttft', today.timed ? (today.ttft_ms / today.timed / 1000).toFixed(1) + ' 秒' : '—');

    // 流程一行：只用一维读数，失败带比率（推理含在输出内，不重复列）。
    const flow = [['输入', compact(today.input)], ['输出', compact(today.output)],
                  ['缓存读', compact(today.cache_read)],
                  ['失败', integer(today.errors) + ' / ' + pct(share(today.errors, today.calls))],
                  ['会话', integer(today.sessionCount)]];
    $('flow').innerHTML = flow.map(([k, v]) => `${k} <b>${v}</b>`).join('<i>·</i>');

    const cells = [
      ['本周', money(week && week.cost)], ['30 日', money(month && month.cost)],
      ['令牌总量', compact((today.input || 0) + (today.output || 0) + (today.cache_read || 0))],
      ['等价', ds.length ? '$' + usd.toFixed(usd < 1 ? 3 : 2) : '—']
    ];
    keyed($('cells'), cells, ([k]) => k,
      () => { const d = el('div'); d.append(el('span'), el('b')); return d; },
      (node, [k, v]) => {
        node.firstChild.textContent = k;
        node.lastChild.textContent = v;
        node.title = k === '等价'
          ? (ds.length ? 'DeepSeek 官方价折算 · ' + integer(dsCalls) + ' 次调用' : '今日未走 DeepSeek')
          : '';
      });

    $('today-foot').textContent =
      '本周 ' + integer(week && week.calls) + ' 次 · 30 日 ' + integer(month && month.calls) + ' 次';
    $('today-foot2').textContent = today.credited != null ? '已计费 ' + today.credited + ' 次' : '';

    // series 是整天的 24 个小时桶，末尾那些还没到的小时永远是 0；去尾画 24 小时节奏。
    const series = today.series || [];
    let end = series.length;
    while (end > 1 && !series[end - 1].calls) end -= 1;
    const hours = series.slice(0, end);
    const maxCalls = Math.max(1, ...hours.map((h) => h.calls || 0));
    const peak = hours.reduce((a, h) => ((h.calls || 0) > (a.calls || 0) ? h : a), hours[0] || {});
    const box = $('rhythm');
    if (!box.dataset.ready) {
      const head = el('div', 'rhythm-head');
      head.append(el('span', null, '24 小时节奏'), el('b'));
      head.dataset.key = 'head';
      box.append(head, el('div', 'rhythm-bars'));
      box.dataset.ready = '1';
    }
    const bars = box.querySelector('.rhythm-bars');
    keyed(bars, hours, (h) => h.label,
      () => el('i'),
      (node, h, i) => {
        const cur = i === hours.length - 1;
        node.style.height = Math.max(3, share(h.calls || 0, maxCalls)) + '%';
        node.className = cur ? 'cur' : ((h.calls || 0) ? '' : 'zero');
        if (h.errors) node.className = (cur ? 'cur' : '') + ' err';
        node.title = h.label + ' 时 · ' + integer(h.calls) + ' 次 · ' + money(h.cost)
          + (h.errors ? ' · 失败 ' + integer(h.errors) : '');
      });
    box.querySelector('.rhythm-head b').textContent = hours.length
      ? '峰值 ' + integer(peak.calls || 0) + ' 次 · ' + peak.label + ' 时'
      : '';
  }

  /* ── 额度 ── */
  /** 燃尽速度 → 估算用尽：只用当前窗口内的真实下降，重置先到就不估。 */
  function burnEstimate(line) {
    const pts = (line && line.points) || [];
    if (pts.length < 3) return null;
    const start = pts[pts.length - 1].start;
    const win = (start ? pts.filter((p) => p.start === start) : pts).slice();
    if (win.length < 3) return null;
    const first = win[0], last = win[win.length - 1];
    if (last.left <= 0) return null;
    const hours = (new Date(last.at) - new Date(first.at)) / 3.6e6;
    if (hours < 0.25 || first.left <= last.left) return null;
    const rate = (first.left - last.left) / hours;      // 每小时烧掉的百分点
    if (rate < 0.5) return null;                        // 几乎没在烧，估了也是噪声
    const etaH = last.left / rate;
    if (last.resetsAt) {
      const resetH = (new Date(last.resetsAt) - Date.now()) / 3.6e6;
      if (etaH >= resetH) return null;                  // 重置会先来
    }
    return { name: line.name, etaH };
  }
  const etaText = (h) => h < 1 ? Math.max(1, Math.round(h * 60)) + ' 分钟' : h < 48 ? h.toFixed(1) + ' 小时' : Math.round(h / 24) + ' 天';
  function renderQuotas(quotas, history) {
    const accounts = quotas.data || [];
    // 整块右侧全给额度：按账号分组，每个账号列出它所有窗口，不折叠、不裁切。
    const groups = accounts.map((q) => {
      const seen = new Set();
      const wins = (q.windows || []).filter((w) => {
        // Cursor 的 Total 与 Cursor Models 数值全等，视为重复窗口只留一个。
        const fingerprint = w.used + '/' + w.remaining;
        if (w.name === 'Total' && seen.has(fingerprint)) return false;
        seen.add(fingerprint);
        return true;
      });
      // 同一个账号里，余量最紧的窗口排在最上面。
      const rank = (w) => (typeof w.remaining === 'number' ? w.remaining : w.unit === 'credits' ? 200 : 150);
      wins.sort((a, b) => rank(a) - rank(b));
      return { q, wins, key: q.provider + '|' + q.name + '|' + q.plan + '|' + q.user };
    });
    // 账号之间同样按最紧的那个窗口升序：用尽和将尽的账号一眼看到。
    const worst = (g) => (g.wins.length ? Math.min(...g.wins.map((w) => (typeof w.remaining === 'number' ? w.remaining : 300))) : 400);
    groups.sort((a, b) => worst(a) - worst(b));

    // 没有额度窗口的账号不各占一行：它们没有读数，堆在底部反而把有读数的账号挤扁。
    const shown = groups.filter((g) => g.wins.length);
    const idle = groups.filter((g) => !g.wins.length);
    const items = idle.length ? shown.concat([{ key: '__idle', idle }]) : shown;

    keyed($('quota-list'), items, (g) => g.key,
      () => {
        // 电源墙单元：标题（灯+名+状态词）→ 大燃料条 → 主读数行 → 小字收拢行。
        const box = el('div', 'q-group');
        const head = el('h3');
        head.append(el('b'), el('i'), el('em'));
        const bar = el('div', 'q-bar');
        const fill = el('i');
        fill.append(el('span', null), el('span', 'qp2'));   // 电流粒子
        bar.append(fill);
        const main = el('div', 'q-main');
        main.append(el('b'), el('em'), el('span'));
        box.append(head, bar, main, el('div', 'q-sub'));
        return box;
      },
      (node, g) => {
        if (g.idle) {
          // 无窗口账号合成一行：一句总数 + 悬停看全名单。
          const names = g.idle.map((x) => mask(x.q.name || x.q.provider));
          const tally = new Map();
          names.forEach((n) => tally.set(n, (tally.get(n) || 0) + 1));
          node.className = 'q-idle';
          node.replaceChildren(
            el('b', null, '无额度窗口 ' + g.idle.length + ' 个'),
            el('span', null, [...tally].map(([n, c]) => (c > 1 ? n + ' ×' + c : n)).join(' · ')));
          node.title = g.idle.map((x) => (x.q.name || x.q.provider) + (x.q.plan ? ' · ' + x.q.plan : '')).join('\n');
          return;
        }

        const head = node.querySelector('h3');
        const bar = node.querySelector('.q-bar i');
        const main = node.querySelector('.q-main');
        const sub = node.querySelector('.q-sub');
        const name = g.q.name || g.q.provider;
        head.children[0].textContent = mask(name);
        // plan 里常常已经写着账号名（如「ZCODE START PLAN」），重复就不再排一遍。
        const plan = g.q.plan && !String(g.q.plan).toUpperCase().includes(String(name).toUpperCase())
          && !String(name).toUpperCase().includes(String(g.q.plan).toUpperCase()) ? g.q.plan : '';
        head.children[1].textContent = plan ? mask(plan) : '';
        // 账号状态分诊：用尽 > 紧张(≤20%) > 临近重置(<90min) > 正常，一眼读。
        const stOf = (w) => {
          if (typeof w.remaining === 'number' && w.remaining <= 0) return 3;
          if (typeof w.remaining === 'number' && w.remaining <= 20) return 2;
          const ra = w.resetsAt && !isNaN(new Date(w.resetsAt)) ? new Date(w.resetsAt).getTime() : null;
          return (ra != null && ra - Date.now() < 90 * 60000) ? 1 : 0;
        };
        const st = Math.max(0, ...g.wins.map(stOf));
        node.classList.remove('st-ok', 'st-warn', 'st-bad', 'gone');
        node.classList.add(st >= 2 ? 'st-bad' : (st === 1 ? 'st-warn' : 'st-ok'));
        if (st >= 3) node.classList.add('gone');
        head.children[2].textContent = ['正常', '临近重置', '紧张', '用尽'][st];
        head.children[2].className = st >= 3 ? 'on out' : (st >= 2 ? 'on bad' : (st === 1 ? 'on warn' : 'on'));

        // 燃料计取最紧窗口；其余窗口折进小字行。
        const lead = g.wins[0];
        bar.style.width = share(lead.remaining || 0, 100) + '%';
        if (st >= 3) {
          // 已用尽：状态词说了「用尽」，大数字回答下一个问题——多久恢复。
          main.children[0].textContent = '重置倒计时';
          main.children[1].textContent = resetShort(lead.resetsAt);
          main.children[2].textContent = lead.resetsAt ? clockOf(lead.resetsAt) + ' 恢复' : '';
        } else {
          main.children[0].textContent = lead.name || '额度';
          main.children[1].textContent = typeof lead.remaining === 'number' ? pct(lead.remaining) : (lead.display || '—');
          main.children[2].textContent = resetText(lead.resetsAt);
        }

        // 估算燃尽：history 里点位最多的窗口线。
        const rec = ((history && history.data) || []).find((h) => h.provider === g.q.provider && h.user === g.q.user);
        let bestLine = null;
        ((rec && rec.lines) || []).forEach((ln) => {
          if (!bestLine || (ln.points || []).length > (bestLine.points || []).length) bestLine = ln;
        });
        g.eta = bestLine ? burnEstimate(bestLine) : null;

        // 小字行：其余窗口「名 剩余」串 + 估算 + 占用，一行收拢。
        const bits = [];
        g.wins.slice(1).forEach((w) => {
          bits.push(w.name + ' ' + (typeof w.remaining === 'number' ? pct(w.remaining) : (w.display || '—')));
        });
        if (g.eta && g.eta.name === lead.name) bits.push('估算 ' + etaText(g.eta.etaH) + ' 用尽');
        if (lead.holds && lead.holds.tokens) bits.push(compact(lead.holds.tokens) + ' 令牌已占');
        sub.textContent = bits.join(' · ');
      });
    if (!groups.length) $('quota-list').replaceChildren(el('div', 'empty', '等待账号额度'));

    const wins = groups.flatMap((g) => g.wins);
    const nearest = wins.filter((w) => w.resetsAt && !isNaN(new Date(w.resetsAt)))
      .sort((a, b) => new Date(a.resetsAt) - new Date(b.resetsAt))[0];
    const noWin = groups.filter((g) => !g.wins.length).length;
    const fastest = shown.map((g) => g.eta).filter(Boolean).sort((a, b) => a.etaH - b.etaH)[0];
    $('quota-note').textContent = shown.length + ' 账号 · ' + wins.length + ' 窗口 · 按余量升序';
    $('quota-foot').textContent = nearest ? '最近重置 · ' + resetText(nearest.resetsAt) : '';
    $('quota-foot').classList.toggle('soon',
      !!nearest && (new Date(nearest.resetsAt) - Date.now()) / 60000 < 90);
    $('quota-foot2').textContent = noWin
      ? '另有 ' + noWin + ' 个账号未上报窗口'
      : (fastest ? '最快燃尽 · ' + fastest.name + ' · 估算 ' + etaText(fastest.etaH) + ' 用尽' : '');
    $('quota-foot2').classList.toggle('soon', !noWin && !!fastest);
  }

  /* ── 模型矩阵 ──
     usage.models 按 provider/model@账号 拆分，这里按模型名聚合成今日矩阵；
     智能体的活动状态由星系行星表达，成本归属在「令牌消耗明细」窗口。 */
  function renderModels(today) {
    const agg = new Map();
    (today.models || []).forEach((m) => {
      const key = m.model || String(m.id || '').split(' @ ')[0] || '未知模型';
      const g = agg.get(key) || { name: key, calls: 0, cost: 0, errors: 0, timed: 0, ttft_ms: 0, decode_ms: 0, decode_out: 0 };
      g.calls += m.calls || 0;
      g.cost += m.cost || 0;
      g.errors += m.errors || 0;
      g.timed += m.timed || 0;
      g.ttft_ms += m.ttft_ms || 0;
      g.decode_ms += m.decode_ms || 0;
      g.decode_out += m.decode_out || 0;
      agg.set(key, g);
    });
    const all = [...agg.values()].sort((a, b) => (b.cost || 0) - (a.cost || 0));
    // 两行三列，多出的模型并进「另 N 个」。
    const models = all.slice(0, 6);
    if (all.length > 6) {
      models.push(all.slice(6).reduce((acc, m) => ({
        name: '另 ' + (all.length - 6) + ' 个',
        cost: (acc.cost || 0) + (m.cost || 0), calls: (acc.calls || 0) + (m.calls || 0),
        errors: (acc.errors || 0) + (m.errors || 0)
      }), {}));
    }
    const maxCost = Math.max(0.0001, ...models.map((m) => m.cost || 0));
    keyed($('model-list'), models, (m) => m.name,
      () => {
        const row = el('div', 'a');
        row.append(el('b'), el('em'), el('span'));
        const share = el('div', 'share');
        share.append(el('i'));
        row.append(share);
        return row;
      },
      (node, m) => {
        node.children[0].textContent = m.name;
        node.children[1].textContent = money(m.cost);
        const bits = [integer(m.calls) + ' 次'];
        if (m.timed) bits.push('首字 ' + (m.ttft_ms / m.timed / 1000).toFixed(1) + ' 秒');
        if (m.decode_ms) bits.push(Math.round(m.decode_out / (m.decode_ms / 1000)) + ' 字/秒');
        if (m.errors) bits.push('失败 ' + m.errors);
        node.children[2].textContent = bits.join(' · ');
        // 占比条按成本：钱花在哪块模型上一眼看。
        node.children[3].firstChild.style.width = share(m.cost || 0, maxCost) + '%';
        if (m.errors) node.children[3].firstChild.style.background = 'linear-gradient(90deg, #b44a4a, var(--void))';
        else node.children[3].firstChild.style.background = '';
      });
    if (!models.length) $('model-list').replaceChildren(el('div', 'empty', '等待模型用量'));
    $('model-foot').textContent = all.length + ' 模型 · 今日 ' + money(today.cost);
  }

  /* ── 最近调用：请求账本（usage/requests）的明细带，两行最新真实调用 ── */
  function renderCalls(requests) {
    const rows = ((requests && requests.rows) || []).slice(0, 2);
    keyed($('calls-rows'), rows, (r) => r.t + '|' + (r.session || '') + '|' + (r.model || ''),
      () => {
        const row = el('div', 'c-row fresh');
        ['t', 'ag', 'md', 'out', 'ms', 'cost'].forEach((c) => row.append(el('span', c)));
        return row;
      },
      (node, r) => {
        const [t, ag, md, out, ms, cost] = node.children;
        t.textContent = clockOf(r.t);
        ag.textContent = mask(r.agentName || r.agent);
        md.textContent = r.served || r.model;
        out.replaceChildren(el('b', null, compact(r.out)), document.createTextNode(' 出'));
        ms.textContent = r.ms ? (r.ms / 1000).toFixed(1) + ' 秒' : '—';
        cost.textContent = r.priced ? money(r.cost) : '未计价';
        node.classList.toggle('bad', !!r.status);
        if (r.status) md.title = 'HTTP ' + r.status;
      });
    if (!rows.length) $('calls-rows').replaceChildren(el('div', 'empty', '等待请求账本'));
  }

  /* ── 链路共享读数：trace 路由整理与统计 ── */
  const median = (list) => {
    if (!list.length) return null;
    const s = [...list].sort((a, b) => a - b);
    const mid = s.length >> 1;
    return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
  };
  const secs = (ms) => ms == null ? '—' : (ms / 1000).toFixed(ms < 10000 ? 2 : 1) + ' 秒';

  /* 签名动作：新路由到达时链路机柜四角亮一下。首轮不闪，之后每来一条闪一次。 */
  let lastRouteKey = null;
  let blipTimer = 0;
  function blipRoute() {
    const mod = $('route-mod');
    mod.classList.remove('blip');
    void mod.offsetWidth;
    mod.classList.add('blip');
    clearTimeout(blipTimer);
    blipTimer = setTimeout(() => mod.classList.remove('blip'), 900);
  }

  // 失败原因沿用网关的 fail 标记，画面上只留一行中文。
  const FAIL = { quota: '额度用尽', timeout: '超时', rate: '限流', auth: '鉴权失败',
                 network: '网络中断', server: '上游故障', context: '上下文超长' };
  const failLabel = (p) => (typeof p.fail === 'number' ? 'HTTP ' + p.fail : FAIL[p.fail] || '失败');

  /** 把 trace 路由整理成这一块要用的形状。只取需要的字段，不做推断。 */
  function readLive(trace) {
    const now = trace && trace.now ? new Date(trace.now).getTime() : Date.now();
    const routes = (trace && trace.routes) || [];
    const rows = routes.map((r) => {
      const tryBad = (r.tries || []).find((t) => t.fail || (t.status && t.status !== 200));
      const bad = !!(r.error || (r.status && r.status !== 200) || tryBad);
      const start = new Date((r.tries && r.tries[0] && r.tries[0].start) || r.time).getTime();
      return {
        id: String(r.id || r.seq),
        at: start,
        label: new Date(start).toTimeString().slice(0, 8),
        agent: r.agent || '—',
        model: r.served || String(r.model || '').split('/').pop() || '—',
        provider: r.provider || (r.tries && r.tries[0] && r.tries[0].id || '').split('@')[0] || '—',
        folder: r.folder || '—',
        done: r.done !== false,
        bad,
        why: bad ? failLabel(tryBad || r) : '',
        ms: r.ms || null,
        ttft: r.ttft || null,
        out: r.out || 0,
        tokens: r.tokens || 0,
        tries: (r.tries || []).length,
        elapsed: r.done === false ? Math.max(0, now - start) : (r.ms || null)
      };
    });
    return rows;
  }

  /**   /* ── 实时链路：智能体 → 网关 → 模型，回复原路返回 ──
     trace 是 4 秒快照，不是逐 token 流：每条真实路由在首次出现时回放一次往返，
     在途路由停在模型处脉冲等待，快照确认完成后才放行回程。空闲不伪造流量。 */
  const routeReduceQuery = matchMedia('(prefers-reduced-motion: reduce)');
  const ROUTE_C = { request: '#6ff2ff', response: '#9fd1ff', fail: '#ff7a7a', direct: '#b18cff', directBack: '#dcc9ff', link: 'rgba(96, 158, 220, 0.34)', chip: 'rgba(9, 24, 44, 0.85)', edge: 'rgba(96, 158, 220, 0.42)' };
  const ROUTE_T = { req1: 700, req2: 800, res1: 1100, res2: 1100, fastK: 0.6 };
  const ROUTE_NODE_TTL = 30000;   // 智能体/模型芯片只在触发后 30 秒内存在，没再触发就退场
  const routeTrips = new Map();   // route id -> 进行中的行程
  const routeSpent = new Set();   // 已回放过的 route id：同一条路由只播一次
  const routeNodes = { agents: new Map(), models: new Map() }; // name -> { state: in|live|out, since, y }
  const routeRipples = [];        // 包裹进出网关的涟漪
  let routeCoreAlpha = 0;         // 3D 核心的入场淡入
  let routeCoreKick = 0;          // 包裹穿过网关时球体的弹跳脉冲（0–1，衰减）
  const gwEnergyRef = { n: 0 };   // 本帧过境 + 停泊的包裹数，驱动核心转速与亮度
  let routeBoot = false;          // 首帧只回放最新几条，历史路由不补播
  let routeRaf = 0;
  let routeLastTs = 0;
  let routeLayoutBusy = false;    // 节点还在淡入/淡出/重排时保持循环

  /** TTL 内真实触发过的名字：活动时刻 = 开始 +（已完成的）耗时，按最近活动排序。 */
  function recentNames(rows, key, cap, ttl) {
    const newest = new Map(); // name -> 最近一次活动的 epoch ms
    rows.forEach((r) => {
      if (!r[key]) return;
      const activeAt = r.at + (r.done ? (r.ms || 0) : 0);
      const prev = newest.get(r[key]);
      if (prev == null || activeAt > prev) newest.set(r[key], activeAt);
    });
    const cut = Date.now() - ttl;
    return [...newest.entries()]
      .filter(([, at]) => at >= cut)
      .sort((a, b) => b[1] - a[1])
      .slice(0, cap)
      .map(([name]) => name);
  }

  /** 拓扑对账：活跃行程的端点优先占位，其余按最近活跃补足；离开的节点淡出。 */
  function syncRouteNodes(kind, desiredNames, now) {
    const reg = routeNodes[kind];
    const desired = new Set(desiredNames);
    desiredNames.forEach((name) => {
      const node = reg.get(name);
      if (!node) reg.set(name, { state: 'in', since: now, y: null });
      else if (node.state === 'out') { node.state = 'in'; node.since = now; }
    });
    reg.forEach((node, name) => {
      if (!desired.has(name) && node.state !== 'out') { node.state = 'out'; node.since = now; }
      if (node.state === 'out' && now - node.since > 600) reg.delete(name);
    });
  }

  /** 三次贝塞尔上取点：控制点取水平中点，得到平滑的 S 形链路。 */
  function legPoints(x0, y0, x1, y1) {
    const mx = (x0 + x1) / 2;
    return [x0, y0, mx, y0, mx, y1, x1, y1];
  }
  function cubicAt(p, t) {
    const u = 1 - t;
    const a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
    return [a * p[0] + b * p[2] + c * p[4] + d * p[6], a * p[1] + b * p[3] + c * p[5] + d * p[7]];
  }

  /* 事件火花：状态无关的瞬态粒子（位置由 时间×速度 推出，无需逐帧积分）。 */
  const routeSparks = [];
  function spawnSparks(x, y, color, n, speed) {
    const t = performance.now();
    for (let i = 0; i < n; i += 1) {
      const a = Math.random() * Math.PI * 2;
      const v = speed * (0.5 + Math.random() * 0.9);
      routeSparks.push({
        x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v,
        at: t, life: 360 + Math.random() * 340, color, size: 0.7 + Math.random() * 1.2
      });
    }
    while (routeSparks.length > 150) routeSparks.shift();
  }
  function drawRouteSparks(ctx, now) {
    for (let i = routeSparks.length - 1; i >= 0; i -= 1) {
      const s = routeSparks[i];
      const age = now - s.at;
      if (age > s.life) { routeSparks.splice(i, 1); continue; }
      const k = age / s.life;
      ctx.globalAlpha = (1 - k) * 0.85;
      ctx.fillStyle = s.color;
      ctx.beginPath();
      ctx.arc(s.x + s.vx * age, s.y + s.vy * age, s.size * (1 - 0.5 * k), 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  function drawRouteComet(ctx, p, t0, t1, color, width, now, reduce) {
    ctx.save();
    ctx.lineCap = 'round';
    ctx.shadowColor = color;
    ctx.shadowBlur = 7;
    // 宽辉光尾流：先沿路径铺一层又宽又淡的光，尾迹长度比彗尾更长。
    if (!reduce) {
      const wakeT0 = Math.max(-0.1, t0 - 0.35);
      ctx.globalAlpha = 0.11;
      ctx.lineWidth = width * 3.4;
      ctx.strokeStyle = color;
      ctx.beginPath();
      for (let s = 0; s <= 10; s += 1) {
        const [wx, wy] = cubicAt(p, wakeT0 + (t1 - wakeT0) * (s / 10));
        if (s === 0) ctx.moveTo(wx, wy); else ctx.lineTo(wx, wy);
      }
      ctx.stroke();
    }
    // 粒子流：一串光点沿路径传输（近头部大而亮，向尾端小而暗），像数据在管道里流动。
    const DOTS = 9;
    for (let k = 0; k < DOTS; k += 1) {
      const tt = t1 - (k / DOTS) * (t1 - t0);
      const [dx2, dy2] = cubicAt(p, tt);
      const fade = 1 - k / DOTS;
      ctx.globalAlpha = 0.16 + 0.74 * fade * fade;
      ctx.fillStyle = k < 3 ? '#dffcff' : color;
      ctx.beginPath();
      ctx.arc(dx2, dy2, Math.max(0.6, width * (1.35 - k * 0.11)), 0, Math.PI * 2);
      ctx.fill();
    }
    const [hx, hy] = cubicAt(p, t1);
    ctx.globalAlpha = 1;
    ctx.fillStyle = '#eafcff';
    ctx.beginPath();
    ctx.arc(hx, hy, width * 0.85 + 0.6, 0, Math.PI * 2);
    ctx.fill();
    // 头部十字耀斑：横向沿运动方向、纵向垂直，能量感十足。
    const flare = width * 2.6 + 2.5;
    ctx.globalAlpha = 0.75;
    ctx.strokeStyle = '#f4feff';
    ctx.lineWidth = 0.8;
    const [px0, py0] = cubicAt(p, Math.max(0, t1 - 0.02));
    const dx = hx - px0, dy = hy - py0;
    const len = Math.hypot(dx, dy) || 1;
    const nx = dx / len, ny = dy / len;
    ctx.beginPath();
    ctx.moveTo(hx - nx * flare, hy - ny * flare);
    ctx.lineTo(hx + nx * flare, hy + ny * flare);
    ctx.moveTo(hx - ny * flare * 0.55, hy + nx * flare * 0.55);
    ctx.lineTo(hx + ny * flare * 0.55, hy - nx * flare * 0.55);
    ctx.stroke();
    // 环绕电火花：两颗微光绕彗星头部旋转，运动中不断喷出细小尾焰。
    if (!reduce) {
      for (let i = 0; i < 2; i += 1) {
        const a = now / 140 + i * Math.PI;
        ctx.globalAlpha = 0.85;
        ctx.fillStyle = '#dffcff';
        ctx.beginPath();
        ctx.arc(hx + Math.cos(a) * (width + 3), hy + Math.sin(a) * (width + 3), 0.8, 0, Math.PI * 2);
        ctx.fill();
      }
      if (Math.random() < 0.8) spawnSparks(hx, hy, color, 1, 0.02);
    }
    ctx.restore();
  }

  /** 网关 3D 核心：常驻科幻能量核——经纬线框球 + 双陀螺环 + 环绕粒子群 + 纬度能量波 + 发光核。
      待机慢转呼吸；运转随吞吐加速变亮，包裹穿过时球体弹跳放射光刺。 */
  const ROUTE_ORBITERS = Array.from({ length: 26 }, (_, i) => ({
    a: (i / 26) * Math.PI * 2 + (i % 3) * 0.7,          // 初始相位
    inc: 0.35 + (i % 5) * 0.42,                          // 轨道倾角（绕 X）
    r: 1.12 + ((i * 7) % 10) / 10 * 0.5,                 // 轨道半径系数
    sp: 0.55 + ((i * 13) % 7) / 7 * 0.9,                 // 角速度系数
    warm: i % 3 === 0                                    // 少量冰蓝粒子，其余青
  }));
  /* 吸积盘：同一倾斜平面上的致密粒子环，开普勒速度（内圈快外圈慢）。 */
  const ROUTE_DISK = Array.from({ length: 130 }, (_, i) => ({
    a: (i * 2.39996) % (Math.PI * 2),                    // 黄金角分布，均匀不扎堆
    r: 1.02 + ((i * 17) % 100) / 100 * 0.72,             // 半径系数 1.02–1.74
    sp: 0.9 / Math.sqrt(1.02 + ((i * 17) % 100) / 100 * 0.72), // 开普勒：1/√r
    s: 0.55 + ((i * 11) % 10) / 10 * 0.6                 // 粒子大小
  }));
  /* 背景星尘：舞台内缓慢漂移的微光点。 */
  const ROUTE_DUST = Array.from({ length: 42 }, (_, i) => ({
    x: ((i * 37) % 100) / 100,
    y: ((i * 61) % 100) / 100,
    sp: 0.004 + ((i * 13) % 7) / 7 * 0.01,
    tw: (i * 0.9) % (Math.PI * 2)
  }));
  let routeCorePhase = 0;         // 粒子相位累积器（平滑变速）
  let routeCoreLastNow = 0;
  let routeCoreWaveAt = -9e9;     // 上一次纬度能量波发射时刻

  function drawGatewayCore(ctx, cx, cy, now, reduce, alpha, energy) {
    const dt = Math.max(0, Math.min(64, now - routeCoreLastNow)) / 1000;
    routeCoreLastNow = now;
    routeCorePhase += dt * (reduce ? 0.25 : 0.55 + 2.4 * energy);
    const breath = reduce ? 0 : Math.sin(now / 900);
    const R = 22 * (1 + 0.07 * breath * (1 - energy) + 0.12 * routeCoreKick);
    // 经线随相位累积器旋转：能量变化时加速而不跳变。
    const yaw = reduce ? 0.6 : routeCorePhase * 1.6;
    const tilt = -0.38;
    const sinT = Math.sin(tilt), cosT = Math.cos(tilt);
    const SEG = 32;
    const glowK = 0.75 + 0.5 * energy + 0.35 * routeCoreKick;
    const proj = (x, y, z) => [cx + x, cy + y * cosT - z * sinT, y * sinT + z * cosT];
    ctx.save();
    // 能量光晕：核心能量越足，外面这团光越亮。
    {
      const haloR = R * (1.55 + 0.5 * energy + 0.3 * routeCoreKick);
      const halo = ctx.createRadialGradient(cx, cy, R * 0.15, cx, cy, haloR);
      halo.addColorStop(0, 'rgba(111, 242, 255, ' + Math.min(0.34, 0.07 + 0.18 * energy + 0.12 * routeCoreKick).toFixed(3) + ')');
      halo.addColorStop(1, 'rgba(111, 242, 255, 0)');
      ctx.fillStyle = halo;
      ctx.fillRect(cx - haloR, cy - haloR, haloR * 2, haloR * 2);
    }
    ctx.strokeStyle = ROUTE_C.request;
    const strokeCircle3D = (points, base, widthBoost) => {
      for (let i = 0; i < points.length; i += 1) {
        const a = proj(...points[i]);
        const b = proj(...points[(i + 1) % points.length]);
        const k = ((a[2] + b[2]) / 2 / R + 1) / 2;
        ctx.globalAlpha = Math.min(1, alpha * base * glowK * (0.22 + 0.55 * k));
        ctx.lineWidth = 0.7 + 0.6 * k + (widthBoost || 0);
        ctx.beginPath();
        ctx.moveTo(a[0], a[1]);
        ctx.lineTo(b[0], b[1]);
        ctx.stroke();
      }
    };
    // 主球：6 经线随 yaw 旋转 + 3 纬线（运转时整体更亮）。
    for (let m = 0; m < 6; m += 1) {
      const yawM = yaw + (m * Math.PI) / 6;
      const pts = [];
      for (let s = 0; s < SEG; s += 1) {
        const t = (s / SEG) * Math.PI * 2;
        pts.push([R * Math.sin(t) * Math.cos(yawM), R * Math.cos(t), R * Math.sin(t) * Math.sin(yawM)]);
      }
      strokeCircle3D(pts, 0.4);
    }
    for (let j = -1; j <= 1; j += 1) {
      const h = (R * j) / 2;
      const r = Math.sqrt(Math.max(0, R * R - h * h));
      const pts = [];
      for (let s = 0; s < SEG; s += 1) {
        const t = (s / SEG) * Math.PI * 2;
        pts.push([r * Math.cos(t), h, r * Math.sin(t)]);
      }
      strokeCircle3D(pts, 0.34);
    }
    // 双陀螺环：两条不同倾角的大圆轨道，粒子沿其飞行使旋转可见。
    const ringTilt = (inc, sign) => {
      const ci = Math.cos(inc), si = Math.sin(inc);
      const pts = [];
      for (let s = 0; s < SEG; s += 1) {
        const t = (s / SEG) * Math.PI * 2;
        const x = R * 1.32 * Math.cos(t), z = R * 1.32 * sign * Math.sin(t);
        pts.push([x, z * si, z * ci]);
      }
      return pts;
    };
    strokeCircle3D(ringTilt(1.05, 1), 0.5, energy * 0.5);
    strokeCircle3D(ringTilt(0.55, -1), 0.42, energy * 0.5);
    // 吸积盘：同一倾斜平面（与第一条陀螺环同角）的致密粒子环，开普勒速度内快外慢。
    {
      const inc = 1.05, ci = Math.cos(inc), si = Math.sin(inc);
      const diskN = reduce ? 40 : Math.round(55 + 75 * Math.min(1, energy + 0.3));
      for (let i = 0; i < diskN; i += 1) {
        const p = ROUTE_DISK[i];
        const ang = p.a + routeCorePhase * p.sp * 1.35;
        const x = R * p.r * Math.cos(ang), z = R * p.r * Math.sin(ang);
        const [px, py, pz] = proj(x, z * si, z * ci);
        const k = (pz / (R * p.r) + 1) / 2;   // 深度 0（后）–1（前）
        ctx.globalAlpha = alpha * (0.10 + 0.34 * k) * (0.55 + 0.45 * energy);
        ctx.fillStyle = p.r < 1.25 ? '#d9fdff' : (i % 4 === 0 ? ROUTE_C.response : ROUTE_C.request);
        ctx.beginPath();
        ctx.arc(px, py, p.s * (0.7 + 0.5 * k), 0, Math.PI * 2);
        ctx.fill();
      }
    }
    // 纬度能量波：每 ~2.2s（运转更频繁）一道亮环从赤道向两极扫。
    const waveEvery = reduce ? 1e9 : 2400 - energy * 1300;
    if (now - routeCoreWaveAt > waveEvery) routeCoreWaveAt = now;
    const waveK = (now - routeCoreWaveAt) / 1100;
    if (waveK >= 0 && waveK < 1) {
      const wh = Math.sin(waveK * Math.PI) * R * 0.94;
      const wr = Math.sqrt(Math.max(0, R * R - wh * wh));
      const pts = [];
      for (let s = 0; s < SEG; s += 1) {
        const t = (s / SEG) * Math.PI * 2;
        pts.push([wr * Math.cos(t), wh, wr * Math.sin(t)]);
      }
      ctx.save();
      ctx.shadowColor = ROUTE_C.request;
      ctx.shadowBlur = 6;
      strokeCircle3D(pts, 0.85 * (1 - waveK * 0.55));
      ctx.restore();
    }
    // 环绕粒子：沿各自倾斜轨道飞行，数量与速度随能量；带短拖尾。
    const activeCount = reduce ? 8 : Math.round(8 + 18 * Math.min(1, energy + 0.25));
    for (let i = 0; i < activeCount; i += 1) {
      const p = ROUTE_ORBITERS[i];
      const ang = routeCorePhase * p.sp + p.a;
      const orbit = (theta) => {
        const x = R * p.r * Math.cos(theta), z = R * p.r * Math.sin(theta);
        const ci = Math.cos(p.inc), si = Math.sin(p.inc);
        return proj(x, z * si, z * ci);
      };
      const [px, py] = orbit(ang);
      const [tx, ty] = orbit(ang - 0.38);
      ctx.save();
      ctx.strokeStyle = p.warm ? ROUTE_C.response : ROUTE_C.request;
      ctx.globalAlpha = alpha * 0.5 * glowK;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(tx, ty);
      ctx.lineTo(px, py);
      ctx.stroke();
      ctx.globalAlpha = alpha * Math.min(1, 0.55 + 0.45 * energy);
      ctx.fillStyle = p.warm ? ROUTE_C.response : '#d9fdff';
      ctx.beginPath();
      ctx.arc(px, py, 1.15 + energy * 0.6, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }
    // 中心发光核：随能量与弹跳变亮。
    {
      const nucR = 5 + 1.8 * energy + 3 * routeCoreKick;
      const nuc = ctx.createRadialGradient(cx, cy, 0, cx, cy, nucR);
      nuc.addColorStop(0, 'rgba(234, 252, 255, ' + (0.5 + 0.35 * energy + 0.3 * routeCoreKick).toFixed(3) + ')');
      nuc.addColorStop(0.55, 'rgba(111, 242, 255, ' + (0.22 + 0.2 * energy).toFixed(3) + ')');
      nuc.addColorStop(1, 'rgba(111, 242, 255, 0)');
      ctx.fillStyle = nuc;
      ctx.fillRect(cx - nucR, cy - nucR, nucR * 2, nucR * 2);
    }
    // 过境光刺：包裹穿过网关时从球面放射的短芒。
    if (routeCoreKick > 0.04) {
      const len = 5 + 10 * routeCoreKick;
      for (let i = 0; i < 8; i += 1) {
        const a = (i / 8) * Math.PI * 2 + 0.4;
        const [x0, y0] = proj(R * Math.cos(a), R * Math.sin(a) * 0.4, R * Math.sin(a) * 0.9);
        const [x1, y1] = proj((R + len) * Math.cos(a), (R + len) * Math.sin(a) * 0.4, (R + len) * Math.sin(a) * 0.9);
        ctx.globalAlpha = alpha * routeCoreKick * 0.65;
        ctx.strokeStyle = '#eafcff';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(x0, y0);
        ctx.lineTo(x1, y1);
        ctx.stroke();
      }
    }
    ctx.restore();
  }

  /** 每帧重排舞台：芯片位置只依赖画布尺寸，数据依赖只读。 */
  function drawRouteStage(now, rows, todayCalls) {
    const canvas = $('route-canvas');
    const rect = canvas.getBoundingClientRect();
    if (!rect.width || !rect.height) return;
    const dpr = Math.min(devicePixelRatio || 1, 2);
    if (canvas.width !== Math.round(rect.width * dpr) || canvas.height !== Math.round(rect.height * dpr)) {
      canvas.width = Math.round(rect.width * dpr);
      canvas.height = Math.round(rect.height * dpr);
    }
    const ctx = canvas.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, rect.width, rect.height);
    const W = rect.width, H = rect.height;
    const running = rows.filter((r) => !r.done).length;
    const stageIdle = routeTrips.size === 0 && running === 0;

    // 发光层统一加性混光：光是叠出来的，不是画出来的；芯片面板最后回到普通混合保证可读。
    ctx.globalCompositeOperation = 'lighter';
    const energy = Math.min(1, (stageIdle ? 0 : 0.3) + 0.25 * Math.min(3, gwEnergyRef.n) + 0.5 * routeCoreKick);
    // 背景星尘：舞台内缓慢漂移的微光点，随能量略亮。
    {
      const dustA = 0.10 + 0.10 * energy;
      ctx.fillStyle = '#9fd8ff';
      ROUTE_DUST.forEach((d) => {
        const x = ((d.x + now * d.sp / 100000) % 1) * W;
        ctx.globalAlpha = dustA * (0.5 + 0.5 * Math.sin(now / 900 + d.tw));
        ctx.beginPath();
        ctx.arc(x, d.y * H, 0.7, 0, Math.PI * 2);
        ctx.fill();
      });
      ctx.globalAlpha = 1;
    }

    // 拓扑：登记表驱动——新节点淡入、离场节点淡出、位置缓动重排；
    // 活跃行程的端点在 syncRouteNodes 里优先占位，这里只读登记表。
    // 两个登记表都空（完全没有触发的智能体/模型）时只剩网关自己的呼吸核心。
    routeLayoutBusy = false;
    const reduce = routeReduceQuery.matches;

    // 星系几何：中央恒星 + 两侧椭圆轨道上的行星（智能体在左、模型在右）。
    const cx = W / 2, cy = H / 2, starR = 30;
    const laneH = 46;
    const alphaOf = (node) => {
      if (reduce) return node.state === 'out' ? 0 : 1;
      if (node.state === 'in') return Math.min(1, (now - node.since) / 500);
      if (node.state === 'out') return Math.max(0, 1 - (now - node.since) / 600);
      return 1;
    };
    // 布局：在册节点缓动到目标轨道位（稳定序）；再按椭圆参数算出本帧行星坐标（含缓慢轨道漂移）。
    // sideSign：-1 左侧（智能体），+1 右侧（模型）。node.px/py = 行星当前位置，rx/ry = 轨道半径。
    const layout = (reg, sideSign) => {
      if (!reduce) reg.forEach((n) => { if (n.state === 'in' && now - n.since > 500) n.state = 'live'; });
      const live = [...reg.entries()].filter(([, n]) => n.state !== 'out');
      live.forEach(([name, node], i) => {
        const target = ((i + 1) / (live.length + 1)) * (H - laneH - 12) + 6 + laneH / 2;
        if (node.y == null || reduce) node.y = target;
        else {
          node.y += (target - node.y) * 0.22;
          if (Math.abs(target - node.y) > 0.75) routeLayoutBusy = true;
        }
        const rx = Math.min(W * 0.36, 360);
        const ry = Math.max(44, Math.abs(node.y - cy));
        // 轨道角：左侧 θ≈π，右侧 θ≈0；叠加缓慢漂移，行星在轨道上轻轻游动。
        const phi = Math.asin(Math.max(-1, Math.min(1, (node.y - cy) / ry)));
        const theta0 = sideSign < 0 ? Math.PI - phi : phi;
        const drift = reduce ? 0 : Math.sin(now / 4200 + i * 2.1) * 0.055;
        const theta = theta0 + drift;
        node.rx = rx; node.ry = ry;
        node.px = cx + rx * Math.cos(theta);
        node.py = cy + ry * Math.sin(theta);
      });
      reg.forEach((node) => {
        if (node.state === 'out' && node.y != null && node.px == null) {
          node.px = cx + Math.min(W * 0.36, 360) * sideSign;
          node.py = node.y;
        }
      });
    };
    layout(routeNodes.agents, -1);
    layout(routeNodes.models, 1);

    // 网关底光 + 3D 核心：核心常驻——待机慢转呼吸，运转随吞吐（在途+过境数）加速变亮。
    routeCoreAlpha += (1 - routeCoreAlpha) * (reduce ? 1 : 0.06);
    if (routeCoreAlpha < 0.98) routeLayoutBusy = true;
    routeCoreKick *= reduce ? 0 : 0.90;
    if (routeCoreKick > 0.02) routeLayoutBusy = true;
    const gwGlow = stageIdle
      ? 0.08 + routeCoreAlpha * (reduce ? 0.02 : 0.02 + 0.06 * (0.5 + 0.5 * Math.sin(now / 700)))
      : 0.08 + routeCoreAlpha * (0.04 + 0.07 * energy);
    const gwGlowR = Math.min(W, H) * 0.2;
    const underglow = ctx.createRadialGradient(W / 2, H / 2, 0, W / 2, H / 2, gwGlowR);
    underglow.addColorStop(0, 'rgba(111, 242, 255, ' + gwGlow.toFixed(3) + ')');
    underglow.addColorStop(1, 'rgba(111, 242, 255, 0)');
    ctx.fillStyle = underglow;
    ctx.fillRect(W / 2 - gwGlowR, H / 2 - gwGlowR, gwGlowR * 2, gwGlowR * 2);
    // 3D 核心常驻：能量驱动转速与亮度；待机时是慢转呼吸态。
    if (routeCoreAlpha > 0.02) drawGatewayCore(ctx, W / 2, H / 2, now, reduce, routeCoreAlpha, energy);

    // 先算活跃端点：链路辉光要在虚线下面垫一层（直连单独记，不点亮通往恒星的束）。
    const activeAgents = new Set(), activeModels = new Set();
    const directAgents = new Set(), directModels = new Set();
    routeTrips.forEach((trip) => {
      if (trip.kind === 'direct') {
        if (trip.phase === 'd1' || trip.phase === 'd2') {
          directAgents.add(trip.agent);
          directModels.add(trip.model);
        }
        return;
      }
      if (trip.phase === 'req1' || trip.phase === 'req2' || trip.phase === 'res2') activeAgents.add(trip.agent);
      if (trip.phase === 'parked' || trip.phase === 'res1') activeModels.add(trip.model);
      if (trip.phase === 'done' && now - trip.startedAt <= 600) activeAgents.add(trip.agent);
    });

    // 轨道弧线：每颗行星一条淡淡的椭圆轨道（含行星的漂移余量）。
    ctx.save();
    ctx.setLineDash([1, 6]);
    routeNodes.agents.forEach((node, name) => {
      const alpha = alphaOf(node);
      if (node.rx == null || alpha <= 0.02) return;
      ctx.globalAlpha = alpha * (activeAgents.has(name) ? 0.22 : 0.10);
      ctx.strokeStyle = ROUTE_C.request;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.ellipse(cx, cy, node.rx, node.ry, 0, 0, Math.PI * 2);
      ctx.stroke();
    });
    routeNodes.models.forEach((node, name) => {
      const alpha = alphaOf(node);
      if (node.rx == null || alpha <= 0.02) return;
      ctx.globalAlpha = alpha * (activeModels.has(name) ? 0.22 : 0.10);
      ctx.strokeStyle = ROUTE_C.response;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.ellipse(cx, cy, node.rx, node.ry, 0, 0, Math.PI * 2);
      ctx.stroke();
    });
    // 引力束：活跃行星与恒星之间一道流动的光束（宽辉光垫底 + 流动虚线）。
    ctx.setLineDash([2, 5]);
    ctx.lineDashOffset = -(now / 38) % 7;
    const beam = (node, name, active, accent) => {
      if (!active || node.px == null) return;
      const alpha = alphaOf(node);
      const p = legPoints(node.px, node.py, cx, cy);
      ctx.save();
      ctx.setLineDash([]);
      ctx.globalAlpha = alpha * 0.16;
      ctx.strokeStyle = accent;
      ctx.lineWidth = 4.5;
      ctx.beginPath();
      ctx.moveTo(p[0], p[1]);
      ctx.bezierCurveTo(p[2], p[3], p[4], p[5], p[6], p[7]);
      ctx.stroke();
      ctx.restore();
      ctx.globalAlpha = alpha * 0.6;
      ctx.strokeStyle = accent;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(p[0], p[1]);
      ctx.bezierCurveTo(p[2], p[3], p[4], p[5], p[6], p[7]);
      ctx.stroke();
    };
    routeNodes.agents.forEach((node, name) => beam(node, name, activeAgents.has(name), 'rgba(111, 242, 255, 0.9)'));
    routeNodes.models.forEach((node, name) => beam(node, name, activeModels.has(name), 'rgba(159, 209, 255, 0.9)'));
    ctx.restore();

    // 待机声呐：都未触发（无行程无在途、芯片也全部退场）时，网关一圈圈向外呼吸。
    if (stageIdle && !routeNodes.agents.size && !routeNodes.models.size && routeCoreAlpha > 0.02 && !reduce) {
      for (let i = 0; i < 2; i += 1) {
        const p = ((now / 2600) + i * 0.5) % 1;
        const r = starR + 8 + p * Math.min(H, W) * 0.3;
        ctx.save();
        ctx.globalAlpha = routeCoreAlpha * (1 - p) * 0.34;
        ctx.strokeStyle = ROUTE_C.request;
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.arc(W / 2, H / 2, r, 0, Math.PI * 2);
        ctx.stroke();
        ctx.restore();
      }
    }

    // 包裹：沿引力束移动的彗星；在途的停在行星旁脉冲。端点坐标取行星当前位置，漂移时彗星跟着走。
    let parkedCount = 0;
    let transit = 0;
    routeTrips.forEach((trip) => {
      const an = routeNodes.agents.get(trip.agent);
      const mn = routeNodes.models.get(trip.model);
      if (!an || !mn || an.px == null || mn.px == null) return;
      // 引力束：行星边缘 → 恒星中心 → 对侧行星边缘。
      const leg1 = legPoints(an.px + 9, an.py, cx, cy);
      const leg2 = legPoints(cx, cy, mn.px - 9, mn.py);
      const elapsed = now - trip.startedAt;
      const speed = trip.fast ? ROUTE_T.fastK : 1;
      if (trip.phase === 'req1') {
        const t = Math.min(1, elapsed / (ROUTE_T.req1 * speed));
        activeAgents.add(trip.agent);
        transit += 1;
        drawRouteComet(ctx, leg1, Math.max(0, t - 0.3), t, trip.color, trip.width, now, reduce);
        if (t >= 1) {
          trip.phase = 'req2'; trip.startedAt = now;
          routeRipples.push({ x: cx, y: cy, at: now, color: trip.color });
          routeCoreKick = Math.min(1, routeCoreKick + 0.55);   // 恒星弹一下
          spawnSparks(cx, cy, trip.color, 4, 0.05);            // 坠入恒星：迸几颗火花
        }
      } else if (trip.phase === 'req2') {
        const t = Math.min(1, elapsed / (ROUTE_T.req2 * speed));
        activeAgents.add(trip.agent);
        transit += 1;
        drawRouteComet(ctx, leg2, Math.max(0, t - 0.3), t, trip.color, trip.width, now, reduce);
        if (t >= 1) {
          trip.phase = trip.park ? 'parked' : 'res1'; trip.startedAt = now;
          const [mx, my2] = cubicAt(leg2, 1);
          routeRipples.push({ x: mx, y: my2, at: now, color: trip.color });
          spawnSparks(mx, my2, trip.color, 10, 0.09);          // 命中模型行星：冲击波 + 火花迸射
        }
      } else if (trip.phase === 'parked') {
        parkedCount += 1;
        activeModels.add(trip.model);
        // 停在模型处：一颗常亮包裹 + 呼吸环 + 两颗电子环绕，快照确认完成才放行。
        const [px, py] = cubicAt(leg2, 1);
        ctx.save();
        ctx.fillStyle = trip.color;
        ctx.shadowColor = trip.color;
        ctx.shadowBlur = 8;
        ctx.beginPath();
        ctx.arc(px, py, trip.width * 0.85 + 0.6, 0, Math.PI * 2);
        ctx.fill();
        const pulse = 5 + 3 * Math.sin(now / 260);
        ctx.strokeStyle = trip.color;
        ctx.globalAlpha = 0.55;
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.arc(px, py, pulse + 3, 0, Math.PI * 2);
        ctx.stroke();
        if (!reduce) {
          for (let i = 0; i < 2; i += 1) {
            const ea = now / 220 + i * Math.PI;
            ctx.globalAlpha = 0.9;
            ctx.fillStyle = '#dffcff';
            ctx.beginPath();
            ctx.arc(px + Math.cos(ea) * (pulse + 5), py + Math.sin(ea) * (pulse + 5) * 0.4, 0.9, 0, Math.PI * 2);
            ctx.fill();
          }
        }
        ctx.restore();
      } else if (trip.phase === 'res1') {
        activeModels.add(trip.model);
        transit += 1;
        const t = Math.min(1, elapsed / (ROUTE_T.res1 * speed));
        const back = [leg2[6], leg2[7], leg2[4], leg2[5], leg2[2], leg2[3], leg2[0], leg2[1]];
        drawRouteComet(ctx, back, Math.max(0, t - 0.3), t, trip.color, trip.width, now, reduce);
        if (t >= 1) {
          trip.phase = 'res2'; trip.startedAt = now;
          routeRipples.push({ x: cx, y: cy, at: now, color: trip.color });
          routeCoreKick = Math.min(1, routeCoreKick + 0.55);   // 恒星弹一下
          spawnSparks(cx, cy, trip.color, 4, 0.05);            // 离开恒星：迸几颗火花
        }
      } else if (trip.phase === 'res2') {
        const t = Math.min(1, elapsed / (ROUTE_T.res2 * speed));
        const back = [leg1[6], leg1[7], leg1[4], leg1[5], leg1[2], leg1[3], leg1[0], leg1[1]];
        drawRouteComet(ctx, back, Math.max(0, t - 0.3), t, trip.color, trip.width, now, reduce);
        transit += 1;
        activeAgents.add(trip.agent);
        if (t >= 1) {
          trip.phase = 'done'; trip.startedAt = now;
          spawnSparks(an.px, an.py, trip.color, 8, 0.07);      // 落地智能体行星：火花绽开
        }
      } else if (trip.kind === 'direct' && (trip.phase === 'd1' || trip.phase === 'd2')) {
        // 直连旁路：agent 行星 ⇢ 模型行星的下方弧线，绕开恒星——不经网关，不点亮恒星。
        const ax = an.px + 9, mx2 = mn.px - 9;
        const ctrlY = Math.min(H - 12, Math.max(cy + 46, (an.py + mn.py) / 2 + 64));
        const arc = [ax, an.py, (ax + mx2) / 2, ctrlY, (ax + mx2) / 2, ctrlY, mx2, mn.py];
        ctx.save();
        ctx.setLineDash([2, 5]);
        ctx.globalAlpha = 0.30;
        ctx.strokeStyle = ROUTE_C.direct;
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(arc[0], arc[1]);
        ctx.bezierCurveTo(arc[2], arc[3], arc[4], arc[5], arc[6], arc[7]);
        ctx.stroke();
        ctx.restore();
        const dur = trip.phase === 'd1' ? 900 : 1000;
        const t = Math.min(1, elapsed / dur);
        const path = trip.phase === 'd1'
          ? arc
          : [arc[6], arc[7], arc[4], arc[5], arc[2], arc[3], arc[0], arc[1]];
        drawRouteComet(ctx, path, Math.max(0, t - 0.3), t,
          trip.phase === 'd1' ? ROUTE_C.direct : (trip.bad ? ROUTE_C.fail : ROUTE_C.directBack),
          trip.width, now, reduce);
        if (t >= 1) {
          if (trip.phase === 'd1') {
            trip.phase = 'd2'; trip.startedAt = now;
            spawnSparks(mx2, mn.py, ROUTE_C.direct, 8, 0.08);           // 到达模型行星
            routeRipples.push({ x: mx2, y: mn.py, at: now, color: ROUTE_C.direct });
          } else {
            trip.phase = 'done'; trip.startedAt = now;
            spawnSparks(ax, an.py, trip.bad ? ROUTE_C.fail : ROUTE_C.directBack, 8, 0.07);  // 回到智能体行星
          }
        }
      } else if (trip.phase === 'done') {
        // 落地一闪：行星外圈快速收敛的光环。
        const k = Math.min(1, elapsed / 500);
        if (k < 1) {
          ctx.save();
          ctx.strokeStyle = trip.color;
          ctx.globalAlpha = 0.7 * (1 - k);
          ctx.lineWidth = 1.4;
          ctx.beginPath();
          ctx.arc(an.px, an.py, 8 + 16 * k, 0, Math.PI * 2);
          ctx.stroke();
          ctx.restore();
          activeAgents.add(trip.agent);
        }
      }
    });

    // 本帧能量：过境 + 停泊的包裹数（下一帧的核心转速/亮度用）。
    gwEnergyRef.n = transit + parkedCount;

    // 涟漪：包裹进出网关的一圈水波。
    for (let i = routeRipples.length - 1; i >= 0; i -= 1) {
      const rp = routeRipples[i];
      const k = (now - rp.at) / 520;
      if (k >= 1) { routeRipples.splice(i, 1); continue; }
      ctx.save();
      ctx.globalAlpha = 0.5 * (1 - k);
      ctx.strokeStyle = rp.color;
      ctx.lineWidth = 1.2;
      ctx.beginPath();
      ctx.arc(rp.x, rp.y, 3 + 16 * k, 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();
    }
    // 事件火花：命中/过站/落地迸出的粒子。
    drawRouteSparks(ctx, now);

    // 行星与恒星标注：回到普通混合保证可读。行星 = 亮面朝恒星的球体 + 大气辉光 + 名称标注。
    const agentCalls = new Map(), modelMs = new Map();
    rows.forEach((r) => {
      agentCalls.set(r.agent, (agentCalls.get(r.agent) || 0) + 1);
      if (r.ms) {
        const list = modelMs.get(r.model) || [];
        list.push(r.ms);
        modelMs.set(r.model, list);
      }
    });
    ctx.globalCompositeOperation = 'source-over';
    // 屏保概览：全屏时画布标注一起放大（星系是屏保的主角）。
    const big = document.body.classList.contains('fullscreen');
    const drawPlanet = (node, accent, active, label, sub, litSign, calls, ringed) => {
      const alpha = alphaOf(node);
      if (node.px == null || alpha <= 0.02) return;
      // 半径随活跃度：常去的天体更大；入场从 30% 缩放到位（物质化）。
      const r = (8 + Math.min(5, calls * 0.45) + (active ? 1 : 0)) * (node.state === 'in' && !reduce ? 0.3 + 0.7 * alpha : 1);
      const x = node.px, y = node.py;
      ctx.save();
      ctx.globalAlpha = alpha;
      // 大气辉光：向外扩散的渐变光晕（加性），不是一块色饼。
      ctx.globalCompositeOperation = 'lighter';
      const haloR = r * (active ? 3.4 : 2.3);
      const halo = ctx.createRadialGradient(x, y, r * 0.55, x, y, haloR);
      halo.addColorStop(0, accent);
      halo.addColorStop(1, 'rgba(0, 0, 0, 0)');
      ctx.globalAlpha = alpha * (active ? 0.36 : 0.16);
      ctx.fillStyle = halo;
      ctx.beginPath();
      ctx.arc(x, y, haloR, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalCompositeOperation = 'source-over';
      // 光环（部分行星）：后半环 → 球体 → 前半环，穿环的深度感。
      const ringTilt = 0.42;
      const drawRingArc = (from, to, a) => {
        ctx.globalAlpha = alpha * a;
        ctx.strokeStyle = accent;
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.ellipse(x, y, r * 2.05, r * 0.5, ringTilt, from, to);
        ctx.stroke();
      };
      if (ringed) drawRingArc(Math.PI, Math.PI * 2, 0.35);
      // 球体底色：深空里的暗球，背光面更沉。
      ctx.globalAlpha = alpha;
      const base = ctx.createRadialGradient(x - litSign * r * 0.4, y - r * 0.45, r * 0.2, x, y, r * 1.1);
      base.addColorStop(0, '#16283e');
      base.addColorStop(1, '#060d18');
      ctx.fillStyle = base;
      ctx.beginPath();
      ctx.arc(x, y, r, 0, Math.PI * 2);
      ctx.fill();
      // 受光面：晨昏线——恒星一侧扫进球内的光（裁剪在球内）。
      ctx.save();
      ctx.beginPath();
      ctx.arc(x, y, r, 0, Math.PI * 2);
      ctx.clip();
      const lx = x + litSign * r * 1.15, ly = y - r * 0.15;
      const lit = ctx.createRadialGradient(lx, ly, 0, lx, ly, r * 1.9);
      lit.addColorStop(0, '#eafdff');
      lit.addColorStop(0.35, accent);
      lit.addColorStop(1, 'rgba(0, 0, 0, 0)');
      ctx.globalAlpha = alpha * (active ? 0.95 : 0.75);
      ctx.fillStyle = lit;
      ctx.fillRect(x - r - 1, y - r - 1, r * 2 + 2, r * 2 + 2);
      ctx.restore();
      // 临边光弧：朝恒星一侧发亮的新月边。
      ctx.globalAlpha = alpha * (active ? 0.95 : 0.6);
      ctx.strokeStyle = '#f0feff';
      ctx.lineWidth = 1.3;
      ctx.shadowColor = accent;
      ctx.shadowBlur = active ? 8 : 4;
      const midA = litSign > 0 ? 0 : Math.PI;
      ctx.beginPath();
      ctx.arc(x, y, r - 0.4, midA - 1.15, midA + 1.15);
      ctx.stroke();
      ctx.shadowBlur = 0;
      if (ringed) drawRingArc(0, Math.PI, 0.5);
      // 标注：名称为主，读数淡一档收在下面。
      ctx.globalAlpha = alpha;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'alphabetic';
      ctx.fillStyle = active ? '#eafcff' : '#dbe9f6';
      ctx.font = (big ? '500 12.5px ' : '500 9.5px ') + 'ui-monospace, "SF Mono", Menlo, monospace';
      ctx.fillText(label, x, y + r + (big ? 18 : 14), 150);
      ctx.globalAlpha = alpha * 0.75;
      ctx.fillStyle = '#7e95ad';
      ctx.font = (big ? '400 10.5px ' : '400 8px ') + 'ui-monospace, "SF Mono", Menlo, monospace';
      ctx.fillText(sub, x, y + r + (big ? 32 : 24), 150);
      ctx.restore();
    };
    routeNodes.agents.forEach((node, name) => drawPlanet(node, ROUTE_C.request, activeAgents.has(name) || directAgents.has(name),
      mask(name), integer(agentCalls.get(name) || 0) + ' 次', 1, agentCalls.get(name) || 0,
      (name.charCodeAt(0) + name.length) % 3 === 0));
    routeNodes.models.forEach((node, name) => drawPlanet(node, ROUTE_C.response, activeModels.has(name) || directModels.has(name),
      name, secs(median(modelMs.get(name) || [])), -1, (modelMs.get(name) || []).length,
      (name.charCodeAt(0) + name.length) % 3 === 1));
    // 恒星标注：网关溶入恒星本体，只在下方留一行铭牌。
    ctx.save();
    ctx.globalAlpha = 0.92 * routeCoreAlpha;
    ctx.textAlign = 'center';
    ctx.fillStyle = '#f2f9ff';
    ctx.font = (big ? '600 13px ' : '600 10.5px ') + 'ui-monospace, "SF Mono", Menlo, monospace';
    ctx.fillText('MAGPIE 网关', cx, cy + (big ? 50 : 44));
    ctx.fillStyle = '#7e95ad';
    ctx.font = (big ? '400 11px ' : '400 8.5px ') + 'ui-monospace, "SF Mono", Menlo, monospace';
    ctx.fillText('今日 ' + integer(todayCalls) + ' · 在途 ' + running, cx, cy + (big ? 66 : 56));
    ctx.restore();
  }

  /** 舞台主循环：有移动包 30fps，只剩停泊 8fps；节点淡入淡出与重排期间保持循环，落地闪放完才停帧。 */
  function routeTick(ts) {
    const rows = routeTick.rows || [];
    let active = false;
    let moving = false;
    routeTrips.forEach((trip) => {
      if (trip.phase === 'done') {
        // 落地一闪还在收敛（≤600ms），保持循环直到放完。
        if (ts - trip.startedAt <= 600) active = true;
      } else {
        active = true;
        if (trip.phase !== 'parked') moving = true;
      }
    });
    if (!active) {
      [routeNodes.agents, routeNodes.models].forEach((reg) => reg.forEach((n) => {
        if (n.state !== 'live') active = true;
      }));
    }
    // 待机呼吸：没有触发的智能体和模型时，网关自己做声呐呼吸，循环保持低频运转。
    const breathing = routeTick.idle && !routeReduceQuery.matches;
    if (!active && !breathing && !routeLayoutBusy && !routeRipples.length && !routeSparks.length) {
      routeRaf = 0;
      drawRouteStage(ts, rows, routeTick.todayCalls || 0);
      return;
    }
    const minDelta = moving ? 1000 / 30 : breathing ? 1000 / 24 : 1000 / 8;
    if (ts - routeLastTs >= minDelta) {
      routeLastTs = ts;
      try {
        drawRouteStage(ts, rows, routeTick.todayCalls || 0);
      } catch (err) {
        // 画布一帧失败不让整条显示链停摆：记到控制台，下一帧继续。
        console.warn('route stage frame error:', err);
      }
    }
    routeRaf = requestAnimationFrame(routeTick);
  }

  function renderRouteStage(bundle) {
    const rows = readLive(bundle.trace);
    const reduce = routeReduceQuery.matches;
    const now = performance.now();

    // 拓扑对账：活跃行程（含直连）的端点优先占位，其次按最近活跃；进出场走淡入淡出。
    // 直连调用：请求账本里 provider=session-unknown 且 session_provider 以 account: 开头——
    // 本机会话直连服务商，不经网关路由，trace 里没有，只在账本里留记录。
    const isDirect = (r) => r.agent && r.provider === 'session-unknown'
      && String(r.session_provider || '').startsWith('account:');
    const directRows = ((bundle.requests && bundle.requests.rows) || [])
      .filter((r) => isDirect(r) && Date.now() - new Date(r.t).getTime() <= ROUTE_NODE_TTL);
    const tripAgentNames = [], tripModelNames = [];
    routeTrips.forEach((t) => {
      if (t.phase !== 'done') {
        if (!tripAgentNames.includes(t.agent)) tripAgentNames.push(t.agent);
        if (!tripModelNames.includes(t.model)) tripModelNames.push(t.model);
      }
    });
    directRows.forEach((r) => {
      if (!tripAgentNames.includes(r.agent)) tripAgentNames.push(r.agent);
      const m = r.served || r.model;
      if (m && !tripModelNames.includes(m)) tripModelNames.push(m);
    });
    const agentNames = [...new Set([...tripAgentNames, ...recentNames(rows, 'agent', 3, ROUTE_NODE_TTL)])].slice(0, 3);
    const modelNames = [...new Set([...tripModelNames, ...recentNames(rows, 'model', 3, ROUTE_NODE_TTL)])].slice(0, 3);
    syncRouteNodes('agents', agentNames, now);
    syncRouteNodes('models', modelNames, now);

    // 快照对账：新路由开程（每条只播一次），已在途的确认完成后放行回程。
    const seenIds = new Set();
    if (!routeBoot) {
      routeBoot = true;
      // 首帧：只有 30 秒内还有活动的路由算「新闻」，更早的历史直接标记已回放。
      rows.forEach((r) => {
        if (Date.now() - (r.at + (r.ms || 0)) > ROUTE_NODE_TTL) routeSpent.add(r.id);
      });
    }
    rows.forEach((r) => {
      seenIds.add(r.id);
      if (routeSpent.has(r.id)) return;
      // 只回放 30 秒内仍有活动的路由（长请求按其完整生命周期算）；更老的不补播。
      if (r.done && Date.now() - (r.at + (r.ms || 0)) > ROUTE_NODE_TTL) { routeSpent.add(r.id); return; }
      let trip = routeTrips.get(r.id);
      if (!trip) {
        if (reduce) return; // 减少动态：不播包，只在静态图上标注
        trip = {
          id: r.id, agent: r.agent, model: r.model,
          phase: 'req1', startedAt: now,
          color: ROUTE_C.request, width: 1.4 + Math.min(2.2, Math.log10((r.tokens || 1) + 1) * 0.55),
          park: !r.done, fast: r.done, out: r.out || 0, bad: r.bad
        };
        routeTrips.set(r.id, trip);
      } else if (trip.phase === 'parked' && r.done) {
        trip.phase = 'res1';
        trip.startedAt = now;
        trip.color = r.bad ? ROUTE_C.fail : ROUTE_C.response;
        trip.width = 1.4 + Math.min(2.2, Math.log10((r.out || 1) + 1) * 0.55);
        trip.bad = r.bad;
      }
    });
    // 直连调用回放：账本里 30 秒内的直连行，每条沿旁路弧播一次（agent ⇢ 模型，不经恒星）。
    directRows.forEach((r) => {
      const key = 'd:' + r.t + '|' + (r.model || '');
      seenIds.add(key);
      if (routeSpent.has(key) || routeTrips.has(key)) return;
      if (reduce) { routeSpent.add(key); return; }
      routeTrips.set(key, {
        id: key, kind: 'direct', agent: r.agent, model: r.served || r.model,
        phase: 'd1', startedAt: now,
        color: ROUTE_C.direct, width: 1.4 + Math.min(2.2, Math.log10(((r.in || 0) + (r.out || 0) || 1) + 1) * 0.55),
        park: false, fast: true, out: r.out || 0, bad: !!r.status
      });
    });
    // 落地闪收敛完的行程移入墓碑集，让主循环可以真正停帧；同 id 不再重播。
    routeTrips.forEach((trip, id) => {
      if (trip.phase === 'done' && now - trip.startedAt > 600) {
        routeTrips.delete(id);
        routeSpent.add(id);
      }
    });
    // 网关重启或路由滑出窗口：清掉不再存在的行程（未回放完的不再补播）。
    [...routeTrips.keys()].forEach((id) => {
      if (!seenIds.has(id)) routeTrips.delete(id);
    });
    routeSpent.forEach((id) => { if (!seenIds.has(id)) routeSpent.delete(id); });
    // 墓碑集上限：只记住最近 300 条，内存有界。
    while (routeSpent.size > 300) routeSpent.delete(routeSpent.values().next().value);
    // 进行中行程上限：只保留最近 7 条，优先让已完成的让路；被挤出的不再重播。
    while (routeTrips.size > 7) {
      const entries = [...routeTrips.entries()].sort((a, b) => a[1].startedAt - b[1].startedAt);
      const victim = entries.find(([, t]) => t.phase === 'done') || entries[0];
      routeTrips.delete(victim[0]);
      routeSpent.add(victim[0]);
    }

    // 签名动作：新路由到达时链路机柜四角亮一下；同时开程回放。
    const newestKey = rows.length ? rows[rows.length - 1].id : null;
    if (newestKey && newestKey !== lastRouteKey) {
      if (lastRouteKey) blipRoute();
      lastRouteKey = newestKey;
    }

    const running = rows.filter((r) => !r.done).length;
    const idle = !routeTrips.size && !running;
    // 页脚吸收原实时数据流的关键读数：在途 / 中位耗时 / 失败。
    const okMsList = rows.filter((r) => r.done && r.ms).map((r) => r.ms);
    const badCount = rows.filter((r) => r.bad).length;
    $('route-foot').textContent = '快照回放 · 秒级轮询 · 非逐令牌观测';
    const directTail = directRows.length ? ' · 直连 ' + directRows.length : '';
    $('route-foot2').textContent = !rows.length && !directRows.length
      ? '等待第一条路由'
      : idle
        ? '网关待机 · 中位 ' + secs(median(okMsList)) + ' · 最近 ' + rows.length + ' 条' + directTail
        : '在途 ' + running + ' · 中位 ' + secs(median(okMsList)) + (badCount ? ' · 失败 ' + badCount : '') + directTail;
    $('route-note').textContent = '智能体 → 网关 → 模型' + (directRows.length ? '（紫=直连）' : '') + ' · 秒级快照回放';

    routeTick.rows = rows;
    routeTick.todayCalls = (bundle.today && bundle.today.calls) || 0;
    routeTick.idle = idle;
    if (reduce) {
      if (routeRaf) { cancelAnimationFrame(routeRaf); routeRaf = 0; }
      drawRouteStage(now, rows, routeTick.todayCalls);
      return;
    }
    if (!routeRaf) {
      routeLastTs = 0;
      routeRaf = requestAnimationFrame(routeTick);
    }
  }

  /* ── 主循环 ── */
  function paint(bundle) {
    const { today, week, month, quotas, history, requests, info } = bundle;
    renderToday(today, week, month);
    renderQuotas(quotas, history);
    renderModels(today);
    renderCalls(requests);
    renderRouteStage(bundle);
    // 顶栏：网关铭牌（版本 + 模型数）+ 状态灯 + 时钟。
    $('gw-meta').textContent = info ? '网关 v' + (info.version || '?') + ' · ' + (info.models || '?') + ' 模型' : '';
    $('gw-label').textContent = online ? '网关在线' : '网关离线';
    $('source-note').textContent = '数据仅取自 127.0.0.1:3425 · 邮箱已遮蔽 · ' +
      (online ? '网关在线' : '网关离线 · 保留上次数据') +
      (bundle.at ? ' · 快照 ' + clockOf(new Date(bundle.at).toISOString()) : '');
    document.body.classList.toggle('offline', !online);
  }

  async function refresh() {
    try {
      const [today, week, month, quotas, trace, history, requests, info] = await Promise.all([
        get('/v1/magpie/usage?period=today'),
        get('/v1/magpie/usage?period=7d'),
        get('/v1/magpie/usage?period=30d'),
        get('/v1/magpie/quotas'),
        get('/v1/magpie/trace'),
        // 燃尽曲线数据：单独容错——拿不到只是少画一条线，不算离线。
        get('/v1/magpie/quotas/history').catch(() => null),
        // 请求账本：单独容错——拿不到只少两行明细。
        get('/v1/magpie/usage/requests?period=today&limit=6').catch(() => null),
        // 网关铭牌（版本/模型数）：单独容错。
        get('/').catch(() => null)
      ]);
      online = true;
      lastGood = { today, week, month, quotas, trace, history, requests, info, at: Date.now() };
      paint(lastGood);
    } catch (error) {
      online = false;
      // 保留上一次成功的数据，只把状态标记为离线。
      if (lastGood) paint(lastGood);
      document.body.classList.add('offline');
    }
  }

  /* ── Swift 注入入口 ── */
  window.setMagpieConfig = ({ mask: maskValue = true } = {}) => {
    maskOn = maskValue;
    if (lastGood) paint(lastGood);
  };

  window.setMagpieStatus = ({ online: up = true } = {}) => {
    online = !!up;
    if (lastGood) paint(lastGood);
  };

  window.setMagpieLayout = ({ fullscreen = false, left = 100, right = 0, bottom = 28 } = {}) => {
    document.documentElement.style.setProperty('--dock-left', (fullscreen ? 0 : left) + 'px');
    document.documentElement.style.setProperty('--dock-right', (fullscreen ? 0 : right) + 'px');
    document.documentElement.style.setProperty('--dock-bottom', (fullscreen ? 0 : bottom) + 'px');
    // 进出全屏时给整块画面一次展开：先压暗再抬起，配合窗口淡入，不是硬切。
    const body = document.body;
    if (body.classList.contains('fullscreen') === fullscreen) return;
    body.classList.toggle('fullscreen', fullscreen);
    body.classList.remove('settling');
    // 强制回流一次，重复进入全屏也能重新播放同一段动画。
    void body.offsetWidth;
    body.classList.add('settling');
    clearTimeout(settleTimer);
    settleTimer = setTimeout(() => body.classList.remove('settling'), 1100);
  };

  function tickClock() {
    $('clock').textContent = new Date().toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' });
  }
  tickClock();
  setInterval(tickClock, 1000);

  /* 轮询分两层：主循环 4 秒全量；快循环 1 秒只拉 trace 与请求账本，
     星系舞台与最近调用因此接近实时。trace 是快照语义，不声称逐令牌流。 */
  (async function loop() {
    for (;;) {
      await refresh();
      await new Promise((resolve) => setTimeout(resolve, POLL_MS));
    }
  })();

  let fastBusy = false;
  async function refreshFast() {
    if (fastBusy || !lastGood) return;
    fastBusy = true;
    try {
      const [trace, requests] = await Promise.all([
        get('/v1/magpie/trace'),
        get('/v1/magpie/usage/requests?period=today&limit=6').catch(() => null)
      ]);
      lastGood.trace = trace;
      if (requests) lastGood.requests = requests;
      renderRouteStage(lastGood);
      renderCalls(lastGood.requests);
    } catch (error) {
      // 快循环失败不打扰画面：网关状态交给主循环判定。
    } finally {
      fastBusy = false;
    }
  }
  setInterval(refreshFast, 1000);
})();
