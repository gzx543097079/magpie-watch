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
  let anatomyResizeTimer = 0;
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

  /** 在途请求正在抽的账号。try.id 经 route.order 解出 who，对不上就不点亮。 */
  function liveByAccount(trace) {
    const map = new Map();
    ((trace && trace.routes) || []).forEach((route) => {
      if (route.done !== false) return;
      const order = route.order || [];
      (route.tries || []).forEach((t) => {
        if (t.done !== false) return;
        const id = String(t.id || '');
        const hit = order.find((o) => o.id === id);
        let provider = String((hit && hit.provider) || route.provider || '').toLowerCase();
        let user = String((hit && hit.who) || '').toLowerCase();
        if (!user && id.includes('@')) {
          const cut = id.indexOf('@');
          provider = provider || id.slice(0, cut).toLowerCase();
          user = id.slice(cut + 1).toLowerCase();
        }
        if (!provider || !user) return;
        const key = provider + '|' + user;
        map.set(key, (map.get(key) || 0) + 1);
      });
    });
    return map;
  }

  let quotaLiveKeys = new Set();
  let quotaBlipTimer = 0;
  function syncQuotaLive(trace) {
    const live = liveByAccount(trace);
    const now = new Set(live.keys());
    const rose = [...now].some((k) => !quotaLiveKeys.has(k));
    quotaLiveKeys = now;
    document.querySelectorAll('#quota-list .q-group[data-acct]').forEach((node) => {
      const n = live.get(node.dataset.acct) || 0;
      node.classList.toggle('live', n > 0);
      const em = node.querySelector('h3 em');
      if (!em) return;
      if (n > 0) {
        em.textContent = n > 1 ? '回答中 ×' + n : '回答中';
        em.classList.add('live');
      } else {
        em.textContent = em.dataset.status || em.textContent;
        em.classList.remove('live');
      }
    });
    const note = $('quota-note');
    if (note && note.dataset.base != null) {
      note.textContent = live.size ? note.dataset.base + ' · 回答中 ' + live.size : note.dataset.base;
    }
    if (rose) {
      const mod = $('quota-mod');
      if (mod) {
        mod.classList.remove('blip');
        void mod.offsetWidth;
        mod.classList.add('blip');
        clearTimeout(quotaBlipTimer);
        quotaBlipTimer = setTimeout(() => mod.classList.remove('blip'), 700);
      }
    }
  }

  function renderQuotas(quotas, history, trace) {
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
        node.dataset.acct = String(g.q.provider || '').toLowerCase() + '|' + String(g.q.user || '').toLowerCase();
        const status = ['正常', '临近重置', '紧张', '用尽'][st];
        head.children[2].dataset.status = status;
        head.children[2].textContent = status;
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
    const note = $('quota-note');
    note.dataset.base = shown.length + ' 账号 · ' + wins.length + ' 窗口 · 按余量升序';
    note.textContent = note.dataset.base;
    syncQuotaLive(trace);
    $('quota-foot').textContent = nearest ? '最近重置 · ' + resetText(nearest.resetsAt) : '';
    $('quota-foot').classList.toggle('soon',
      !!nearest && (new Date(nearest.resetsAt) - Date.now()) / 60000 < 90);
    $('quota-foot2').textContent = noWin
      ? '另有 ' + noWin + ' 个账号未上报窗口'
      : (fastest ? '最快燃尽 · ' + fastest.name + ' · 估算 ' + etaText(fastest.etaH) + ' 用尽' : '');
    $('quota-foot2').classList.toggle('soon', !noWin && !!fastest);
  }

  /* ── 上下文窗口：magpie context.js 的 ctxCard。
     格子算法原样：窗口均分 400 格，parts 按 token 占比着色，空格是剩余窗口。
     取在途请求；没有在途就取最近一次带 prompt 的。不编造。 */
  const CTX_PARTS = ['system', 'tools', 'memory', 'files', 'results', 'chat'];
  const CTX_NAMES = {
    system: '系统指令', tools: '工具定义', memory: '记忆与项目规则',
    files: '文件与图片', results: '工具执行返回', chat: '对话历史'
  };
  const CTX_SHORT = {
    system: '系统', tools: '工具', memory: '记忆',
    files: '文件', results: '返回', chat: '对话'
  };
  const CTX_CELLS = 400;

  function ctxFmt(n) {
    n = Math.max(0, Math.round(n || 0));
    const short = (x, d) => x.toFixed(d).replace(/\.0+$/, '');
    if (n >= 1e6) return short(n / 1e6, n >= 1e7 ? 1 : 2) + 'M';
    if (n >= 1e3) return short(n / 1e3, n >= 1e5 ? 0 : 1) + 'K';
    return String(n);
  }

  function ctxHealth(fill) {
    return fill < 0.75 ? ['ok', '健康'] : fill < 0.9 ? ['warn', '在涨'] : ['bad', '将近满'];
  }

  function ctxCacheOf(route) {
    const list = route.usage || [];
    const u = list[list.length - 1];
    if (!u) return null;
    const read = u.cache_read || u.cacheRead || 0;
    const total = (u.in || 0) + read + (u.cache_write || u.cacheWrite || 0);
    if (!total) return null;
    return { read, total };
  }

  function ctxCellsOf(p, windowSize) {
    const tokens = p.tokens || 0;
    const scale = Math.max(windowSize, tokens, 1);
    const used = Math.min(CTX_CELLS, Math.round((tokens / scale) * CTX_CELLS));
    const parts = CTX_PARTS
      .map((k) => (p.parts || []).find((x) => x.kind === k))
      .filter((x) => x && x.tokens > 0);
    const sum = parts.reduce((s, x) => s + x.tokens, 0) || 1;
    const want = parts.map((x) => (x.tokens / sum) * used);
    const got = want.map((w) => Math.max(1, Math.floor(w)));
    let left = used - got.reduce((s, n) => s + n, 0);
    const order = want.map((w, i) => [w - Math.floor(w), i]).sort((a, b) => b[0] - a[0]);
    for (let j = 0; left > 0 && order.length; j = (j + 1) % order.length, left -= 1) {
      got[order[j][1]] += 1;
    }
    for (let j = got.length - 1; left < 0 && j >= 0; j -= 1) {
      while (left < 0 && got[j] > 1) { got[j] -= 1; left += 1; }
    }
    const cells = [];
    parts.forEach((x, pi) => {
      for (let c = 0; c < got[pi]; c += 1) cells.push(x.kind);
    });
    while (cells.length < CTX_CELLS) cells.push(null);
    return cells.slice(0, CTX_CELLS);
  }

  function latestPromptRoute(trace) {
    const routes = ((trace && trace.routes) || []).filter((r) => {
      const p = r.prompt;
      return p && (p.tokens || (p.parts || []).length);
    });
    const live = routes.filter((r) => r.done === false);
    const pool = live.length ? live : routes;
    return pool[pool.length - 1] || null;
  }

  function renderContext(trace) {
    const route = latestPromptRoute(trace);
    const body = $('ctx-body');
    const waffle = $('ctx-waffle');
    const legend = $('ctx-legend');
    const health = $('ctx-health');
    const cacheBox = $('ctx-cache-box');
    if (!route) {
      body.classList.add('is-empty');
      $('ctx-note').textContent = '等待上下文窗口';
      $('ctx-foot').textContent = '';
      $('ctx-foot2').textContent = '';
      waffle.replaceChildren();
      legend.replaceChildren();
      return;
    }
    body.classList.remove('is-empty');
    const p = route.prompt;
    const tokens = p.tokens || 0;
    const windowSize = p.window || 0;
    const fill = windowSize ? tokens / windowSize : 0;
    const live = route.done === false;
    const state = live ? 'live' : p.counted ? 'counted' : 'est';
    const stateWord = live ? '回答中' : p.counted ? '已计量' : '估算';
    const model = route.served || route.model || '';
    put('ctx-used', ctxFmt(tokens));
    $('ctx-win').textContent = windowSize ? '/ ' + ctxFmt(windowSize) : '令牌';
    if (windowSize) {
      const [tone, word] = ctxHealth(fill);
      health.hidden = false;
      health.className = 'ctx-health ' + tone;
      health.textContent = word;
      $('ctx-sub').textContent = Math.round(fill * 100) + '% · 剩余 ' + ctxFmt(Math.max(0, windowSize - tokens));
    } else {
      health.hidden = true;
      $('ctx-sub').textContent = '窗口大小未知';
    }
    const cache = ctxCacheOf(route);
    cacheBox.classList.toggle('none', !cache);
    if (cache) {
      put('ctx-cache', Math.round(cache.read / cache.total * 100) + '%');
      $('ctx-cache-sub').textContent = ctxFmt(cache.read) + ' 命中 · ' + ctxFmt(cache.total - cache.read) + ' 新';
    } else {
      $('ctx-cache').textContent = '—';
      $('ctx-cache-sub').textContent = live ? '供应商应答后可读' : '供应商未给出';
    }
    const st = $('ctx-state');
    st.className = 'ctx-state ' + state;
    $('ctx-state-word').textContent = stateWord;
    $('ctx-note').textContent = (mask(route.agentName || route.agent) || 'agent')
      + (model ? ' · ' + model : '');

    const cells = ctxCellsOf(p, windowSize);
    if (waffle.children.length !== CTX_CELLS) {
      waffle.replaceChildren();
      const frag = document.createDocumentFragment();
      for (let i = 0; i < CTX_CELLS; i += 1) frag.append(el('i'));
      waffle.append(frag);
    }
    for (let i = 0; i < CTX_CELLS; i += 1) {
      const cls = cells[i] ? 'k-' + cells[i] : 'free';
      if (waffle.children[i].className !== cls) waffle.children[i].className = cls;
    }
    waffle.setAttribute('aria-label',
      ctxFmt(tokens) + (windowSize ? ' / ' + ctxFmt(windowSize) : '') + ' 令牌');

    const partOf = new Map((p.parts || []).map((x) => [x.kind, x]));
    const legs = CTX_PARTS
      .filter((k) => (partOf.get(k) || {}).tokens > 0)
      .map((k) => ({ kind: k, tokens: partOf.get(k).tokens }));
    if (windowSize && windowSize > tokens) {
      legs.push({ kind: 'free', tokens: windowSize - tokens });
    }
    keyed(legend, legs, (x) => x.kind,
      (x) => {
        const node = el('span', 'ctx-leg');
        node.append(el('i', x.kind === 'free' ? 'free' : 'k-' + x.kind), el('span', 'n'), el('span', 'v'));
        return node;
      },
      (node, x) => {
        node.children[0].className = x.kind === 'free' ? 'free' : 'k-' + x.kind;
        node.children[1].textContent = x.kind === 'free' ? '剩余' : (CTX_SHORT[x.kind] || x.kind);
        node.children[2].textContent = ctxFmt(x.tokens);
        node.title = x.kind === 'free' ? '剩余空间' : (CTX_NAMES[x.kind] || x.kind);
      });

    const turns = p.turns;
    $('ctx-foot').textContent = (mask(route.agentName || route.agent) || '')
      + (turns ? ' · ' + integer(turns) + ' 轮' : '');
    $('ctx-foot2').textContent = stateWord
      + (p.counted ? ' · 供应商计量' : ' · 按请求估算');
  }

  /* ── 实时路由：内嵌 magpie 路由舞台 ──
     源码 plugins/routing：#rt 里只露出 .rt-stage（agent → hub → 账号行），
     其余标题、策略说明、页脚、账本由 skin.css 藏掉。magpie 的 JS 一行不改。 */
  const rtWrap = $('rt-live'), rtFrame = $('rt-frame'), rtNote = $('routing-note');

  function rtFit() {
    if (!rtWrap.clientWidth || !rtWrap.clientHeight) return;
    // magpie 舞台三列（agent 124 + hub 124 + 账号行）在 ~920×280 最接近原页截图
    const z = Math.max(0.55, Math.min(1.85,
      Math.min(rtWrap.clientWidth / 920, rtWrap.clientHeight / 280)));
    rtFrame.style.width = Math.round(rtWrap.clientWidth / z) + 'px';
    rtFrame.style.height = Math.round(rtWrap.clientHeight / z) + 'px';
    rtFrame.style.transform = 'scale(' + z.toFixed(4) + ')';
  }
  new ResizeObserver(rtFit).observe(rtWrap);

  async function rtWake() {
    try {
      const res = await fetch('/live-config', { cache: 'no-store' });
      if (!res.ok) throw new Error('not ready');
      rtFrame.src = '/magpie/?view=routing&theme=dark';
      rtNote.textContent = 'magpie · 路由舞台';
    } catch {
      rtNote.textContent = '正在连接 magpie web…';
      setTimeout(rtWake, 5000);
    }
  }
  rtWake();

  /* ── 主循环 ── */
  function paint(bundle) {
    const { today, week, month, quotas, history, info, trace } = bundle;
    renderToday(today, week, month);
    renderQuotas(quotas, history, trace);
    renderContext(trace);
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
      const [today, week, month, quotas, trace, history, info] = await Promise.all([
        get('/v1/magpie/usage?period=today'),
        get('/v1/magpie/usage?period=7d'),
        get('/v1/magpie/usage?period=30d'),
        get('/v1/magpie/quotas'),
        get('/v1/magpie/trace'),
        // 燃尽曲线数据：单独容错——拿不到只是少画一条线，不算离线。
        get('/v1/magpie/quotas/history').catch(() => null),
        // 网关铭牌（版本/模型数）：单独容错。
        get('/').catch(() => null)
      ]);
      online = true;
      lastGood = { today, week, month, quotas, trace, history, info, at: Date.now() };
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

  window.addEventListener('resize', () => {
    clearTimeout(anatomyResizeTimer);
    anatomyResizeTimer = setTimeout(() => {
      }, 80);
  });

  function tickClock() {
    $('clock').textContent = new Date().toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' });
  }
  tickClock();
  setInterval(tickClock, 1000);

  /* 轮询分两层：主循环 4 秒全量；快循环 1 秒只拉 trace，
     上下文格子与额度「回答中」因此接近实时。trace 只用于当前在途。 */
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
      const trace = await get('/v1/magpie/trace');
      lastGood.trace = trace;
      renderContext(trace);
      syncQuotaLive(trace);
    } catch (error) {
      // 快循环失败不打扰画面：网关状态交给主循环判定。
    } finally {
      fastBusy = false;
    }
  }
  setInterval(refreshFast, 1000);
})();
