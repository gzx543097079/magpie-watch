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

  /* ── 节奏脉搏 ──
     今日模块里的小节奏条并到这里放大：柱高 = 该小时调用量，出错小时柱顶一段红，
     当前小时点亮冒火花；只画到最新有活动的小时，数据同一份 today.series。 */
  function renderPulse(today) {
    const series = today.series || [];
    let end = series.length;
    while (end > 1 && !series[end - 1].calls) end -= 1;
    const hours = series.slice(0, end);
    const maxCalls = Math.max(1, ...hours.map((h) => h.calls || 0));
    const peak = hours.reduce((a, h) => ((h.calls || 0) > (a.calls || 0) ? h : a), hours[0] || {});
    keyed($('pulse-bars'), hours, (h) => h.label,
      () => el('i'),
      (node, h, i) => {
        const cur = i === hours.length - 1;
        node.style.height = Math.max(3, share(h.calls || 0, maxCalls)) + '%';
        node.className = cur ? 'cur' : (h.calls ? '' : 'zero');
        if (h.errors) node.className = (cur ? 'cur ' : '') + 'err';
        node.title = h.label + ' 时 · ' + integer(h.calls) + ' 次 · ' + money(h.cost)
          + (h.errors ? ' · 失败 ' + integer(h.errors) : '');
      });
    // 轴标：每 4 小时一个刻度，其余槽位留空对齐柱位。
    const axis = $('pulse-axis');
    if (!axis.children.length) {
      for (let i = 0; i < 24; i += 1) {
        const tick = el('span');
        if (i % 4 === 0) tick.textContent = String(i).padStart(2, '0') + ' 时';
        axis.append(tick);
      }
    }
    const last = hours[hours.length - 1] || {};
    $('pulse-foot').textContent = hours.length
      ? '峰值 ' + integer(peak.calls || 0) + ' 次 · ' + peak.label + ' 时 · 现已 ' + integer(last.calls || 0) + ' 次'
      : '等待今日序列';
    $('pulse-foot2').textContent = '今日 ' + integer(today.calls) + ' 次'
      + (today.errors ? ' · 失败 ' + integer(today.errors) : '');
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
        node.classList.toggle('bad', !!r.status && r.status !== 200);
        if (r.status && r.status !== 200) md.title = 'HTTP ' + r.status;
      });
    if (!rows.length) $('calls-rows').replaceChildren(el('div', 'empty', '等待请求账本'));
  }

  /* ── 请求解剖：请求账本的聚合维度 + 最近真实耗时 + 上下文构成 ── */
  const median = (list) => {
    if (!list.length) return null;
    const sorted = [...list].sort((a, b) => a - b);
    const mid = sorted.length >> 1;
    return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  };
  const secs = (ms) => ms == null ? '—' : (ms / 1000).toFixed(ms < 10000 ? 2 : 1) + ' 秒';
  const timingText = (ms) => ms == null ? '未上报' : secs(ms);

  let lastAnatomyKey = null;
  let anatomyBlipTimer = 0;
  let anatomyResizeTimer = 0;
  function blipAnatomy() {
    const mod = $('anatomy-mod');
    mod.classList.remove('blip');
    void mod.offsetWidth;
    mod.classList.add('blip');
    clearTimeout(anatomyBlipTimer);
    anatomyBlipTimer = setTimeout(() => mod.classList.remove('blip'), 900);
  }

  function renderAnatomyModels(requests) {
    const groups = [...(((requests && requests.by) || {}).modelAt || [])]
      .sort((a, b) => (b.calls || 0) - (a.calls || 0));
    const top = groups.slice(0, 5);
    const rest = groups.slice(5);
    const items = top;
    if (rest.length) {
      items.push(rest.reduce((sum, m) => ({
        id: '__others', name: '另 ' + rest.length + ' 个', calls: (sum.calls || 0) + (m.calls || 0),
        cost: (sum.cost || 0) + (m.cost || 0), errors: (sum.errors || 0) + (m.errors || 0)
      }), { id: '__others', name: '另 ' + rest.length + ' 个', calls: 0, cost: 0, errors: 0 }));
    }
    const maxCalls = Math.max(1, ...items.map((m) => m.calls || 0));
    keyed($('anatomy-models'), items, (m) => m.id,
      () => {
        const row = el('div', 'an-model');
        const head = el('div');
        head.append(el('b'), el('em'));
        const bar = el('div', 'an-call-bar');
        bar.append(el('i'));
        row.append(head, bar, el('span'));
        return row;
      },
      (node, m) => {
        node.classList.toggle('bad', !!m.errors);
        node.children[0].children[0].textContent = m.name || m.id;
        node.children[0].children[1].textContent = integer(m.calls);
        node.children[1].firstChild.style.width = share(m.calls || 0, maxCalls) + '%';
        node.children[2].textContent = money(m.cost) + (m.errors ? ' · 失败 ' + integer(m.errors) : '');
        node.title = (m.name || m.id) + '\n调用 ' + integer(m.calls) +
          '\n费用 ' + money(m.cost) + '\n失败 ' + integer(m.errors || 0);
      });
    if (!items.length) $('anatomy-models').replaceChildren(el('div', 'empty', '等待模型账本'));
  }

  function renderAnatomyTiming(requests) {
    const list = $('anatomy-timing');
    const firstRow = list.firstElementChild && list.firstElementChild.classList.contains('an-time')
      ? list.firstElementChild.getBoundingClientRect().height : 23;
    const capacity = Math.max(6, Math.min(18, Math.floor(list.clientHeight / Math.max(1, firstRow))));
    const rows = (((requests && requests.rows) || []).filter((r) => r.ms != null)).slice(0, capacity);
    const maxMs = Math.max(1, ...rows.map((r) => r.ms || 0));
    keyed(list, rows,
      (r) => (r.route_id || r.t) + '|' + (r.served || r.model) + '|' + r.ms,
      () => {
        const row = el('div', 'an-time');
        row.append(el('span', 'at'), el('span', 'am'), el('span', 'ap'));
        const track = el('span', 'ar');
        track.append(el('i'), el('b'), el('u'));
        row.append(track, el('span', 'ad'));
        return row;
      },
      (node, r) => {
        const bad = !!r.status && r.status !== 200;
        node.className = 'an-time' + (bad ? ' bad' : '');
        node.children[0].textContent = clockOf(r.t);
        node.children[1].textContent = r.served || r.model || '—';
        const [total, ttft, flow] = node.querySelector('.ar').children;
        total.style.width = share(r.ms || 0, maxMs) + '%';
        const ttftMs = r.ttft_ms;
        const flowMs = r.flow_ms;
        if (ttftMs != null && ttftMs <= (r.ms || 0)) {
          ttft.style.left = share(ttftMs, maxMs) + '%';
          ttft.title = '首字 ' + secs(ttftMs);
        } else {
          ttft.style.left = '-9px';
          ttft.title = '首字未上报';
        }
        if (ttftMs != null && flowMs != null && ttftMs < (r.ms || 0) && flowMs > 0) {
          const from = ttftMs;
          const to = Math.min(r.ms || 0, ttftMs + flowMs);
          flow.style.left = share(from, maxMs) + '%';
          flow.style.width = Math.max(0, share(to - from, maxMs)) + '%';
          flow.title = '生成流 ' + secs(flowMs);
        } else {
          flow.style.width = '0';
        }
        node.children[4].textContent = secs(r.ms);
        node.title = clockOf(r.t) + ' · ' + (r.served || r.model || '—') +
          '\n总时长 ' + secs(r.ms) +
          '\n首字 ' + timingText(r.ttft_ms) +
          '\n生成流 ' + timingText(r.flow_ms) +
          '\n传输 ' + timingText(r.sent_ms) +
          '\n网关 ' + timingText(r.own_ms) +
          '\nHTTP ' + (r.status || '未上报');
      });
    if (!rows.length) list.replaceChildren(el('div', 'empty', '等待耗时账本'));

    const totalList = rows.map((r) => r.ms).filter(Number.isFinite);
    const ttftList = rows.map((r) => r.ttft_ms).filter((v) => v != null);
    const flowList = rows.map((r) => r.flow_ms).filter((v) => v != null);
    const sentList = rows.map((r) => r.sent_ms).filter((v) => v != null);
    const ownList = rows.map((r) => r.own_ms).filter((v) => v != null);
    $('anatomy-timing-meta').textContent =
      '中位 总 ' + secs(median(totalList)) + ' · 首字 ' + secs(median(ttftList)) +
      ' · 生成流 ' + secs(median(flowList)) +
      ' · 传输 ' + secs(median(sentList)) + ' ' + sentList.length + '/' + rows.length +
      ' · 网关 ' + secs(median(ownList)) + ' ' + ownList.length + '/' + rows.length;
    return { rows, failed: rows.filter((r) => r.status && r.status !== 200) };
  }

  function renderAnatomyTokens(requests) {
    const groups = [...(((requests && requests.by) || {}).modelAt || [])]
      .sort((a, b) => ((b.cache_read || 0) + (b.input || 0) + (b.output || 0)) -
                      ((a.cache_read || 0) + (a.input || 0) + (a.output || 0)))
      .slice(0, 6);
    const maxTotal = Math.max(1, ...groups.map((m) => (m.cache_read || 0) + (m.input || 0) + (m.output || 0)));
    keyed($('anatomy-tokens'), groups, (m) => m.id,
      () => {
        const row = el('div', 'an-token');
        const head = el('div');
        head.append(el('b'), el('em'));
        const bar = el('div', 'an-token-bar');
        ['cache', 'in', 'out'].forEach(() => bar.append(el('i')));
        row.append(head, bar, el('span'));
        return row;
      },
      (node, m) => {
        const total = (m.cache_read || 0) + (m.input || 0) + (m.output || 0);
        const pieces = [
          ['cache_read', m.cache_read], ['input', m.input], ['output', m.output]
        ];
        node.children[0].children[0].textContent = m.id;
        node.children[0].children[1].textContent = compact(total);
        [...node.children[1].children].forEach((part, i) => {
          const [label, value] = pieces[i];
          part.style.width = share(value || 0, maxTotal) + '%';
          part.title = label + ' ' + compact(value || 0);
        });
        node.children[2].textContent = '推理 ' + compact(m.reasoning || 0) + '（含输出）';
        node.title = (m.name || m.id) + '\n缓存读 ' + compact(m.cache_read) +
          '\n新输入 ' + compact(m.input) + '\n输出 ' + compact(m.output) +
          '\n推理 ' + compact(m.reasoning) + '（已包含在输出内）';
      });
    if (!groups.length) $('anatomy-tokens').replaceChildren(el('div', 'empty', '等待令牌账本'));
  }

  function renderAnatomy(bundle) {
    const requests = bundle.requests;
    renderAnatomyModels(requests);
    const timing = renderAnatomyTiming(requests);
    renderAnatomyTokens(requests);

    const rows = (requests && requests.rows) || [];
    const newest = rows[0];
    const key = newest ? String(newest.route_id || newest.t) : '';
    if (key && key !== lastAnatomyKey) {
      if (lastAnatomyKey) blipAnatomy();
      lastAnatomyKey = key;
    }

    const running = (((bundle.trace || {}).routes) || []).filter((r) => !r.done).length;
    const bad = timing.failed.length;
    $('anatomy-mod').classList.toggle('alert', bad > 0);
    $('anatomy-note').textContent = '模型分流 · 耗时 · 令牌 · ' + integer(rows.length) + ' 条账本';
    $('anatomy-foot').textContent = rows.length
      ? '最近 ' + integer(timing.rows.length) + ' 条 · 传输/网关字段缺失不推断'
      : '等待请求账本';
    $('anatomy-foot2').textContent = rows.length
      ? '在途 ' + integer(running) + ' · 失败 ' + integer(bad) + ' / ' + integer(rows.length)
      : '';
    $('anatomy-foot2').classList.toggle('bad', bad > 0);
  }

  /* ── 主循环 ── */
  function paint(bundle) {
    const { today, week, month, quotas, history, requests, info } = bundle;
    renderToday(today, week, month);
    renderQuotas(quotas, history);
    renderPulse(today);
    renderCalls(requests);
    renderAnatomy(bundle);
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
        get('/v1/magpie/usage/requests?period=today&limit=120').catch(() => null),
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
    if (lastGood) renderAnatomy(lastGood);
  };

  window.addEventListener('resize', () => {
    clearTimeout(anatomyResizeTimer);
    anatomyResizeTimer = setTimeout(() => {
      if (lastGood) renderAnatomy(lastGood);
    }, 80);
  });

  function tickClock() {
    $('clock').textContent = new Date().toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' });
  }
  tickClock();
  setInterval(tickClock, 1000);

  /* 轮询分两层：主循环 4 秒全量；快循环 1 秒只拉 trace 与请求账本，
     请求解剖和最近调用因此接近实时。trace 只用于当前在途计数。 */
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
        get('/v1/magpie/usage/requests?period=today&limit=120').catch(() => null)
      ]);
      lastGood.trace = trace;
      if (requests) lastGood.requests = requests;
      renderAnatomy(lastGood);
      renderCalls(lastGood.requests);
    } catch (error) {
      // 快循环失败不打扰画面：网关状态交给主循环判定。
    } finally {
      fastBusy = false;
    }
  }
  setInterval(refreshFast, 1000);
})();
