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

  const agoText = (ms) => {
    if (ms == null) return '—';
    const s = Math.round(ms / 1000);
    if (s < 60) return s + ' 秒';
    if (s < 3600) return Math.round(s / 60) + ' 分钟';
    return (s / 3600).toFixed(1) + ' 小时';
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
      integer(today.calls) + ' 次 · ' + compact((today.input || 0) + (today.output || 0) + (today.cache_read || 0)) + ' tok';

    // 缓存命中率：命中读 / (新输入 + 命中读)。这是唯一能说明「省了多少」的比率。
    const hit = today.cache_read || 0;
    const billed = (today.input || 0) + hit;
    const rate = share(hit, billed);
    put('cache-rate', billed ? pct(rate) : '—');
    $('cache-bar').style.width = rate + '%';
    $('cache-sub').textContent = billed
      ? compact(hit) + ' 命中 / ' + compact(billed) + ' 输入'
      : '今日还没有输入';

    // DeepSeek 等价美元：官方价折算，标明 Magpie 侧实际记为免费。
    const ds = (today.models || []).filter(isDeepSeek);
    const usd = ds.reduce((s, m) => s + dsUsd(m), 0);
    const freeCalls = ds.reduce((s, m) => s + (m.cost ? 0 : (m.calls || 0)), 0);
    put('equiv-usd', ds.length ? '$' + usd.toFixed(usd < 1 ? 3 : 2) : '—');
    $('equiv-note').textContent = ds.length
      ? '按官方价折算 · ' + integer(ds.reduce((s, m) => s + (m.calls || 0), 0)) + ' 次调用' +
        (freeCalls ? '（' + integer(freeCalls) + ' 次实记免费）' : '') : '今日未走 DeepSeek';

    const flow1 = [['新输入', compact(today.input)], ['输出', compact(today.output)],
                   ['缓存读', compact(today.cache_read)], ['缓存写', compact(today.cache_write)],
                   ['推理', compact(today.reasoning)]];
    const flow2 = [['失败', integer(today.errors) + ' / ' + pct(share(today.errors, today.calls))],
                   ['重试', integer(today.retried)], ['会话', integer(today.sessionCount)],
                   ['未计价', integer(today.unpriced)], ['credits', (today.credits || 0).toFixed(2)],
                   ['计时', pct(share(today.timed, today.calls))]];
    [['flow1', flow1], ['flow2', flow2]].forEach(([id, list]) => {
      $(id).innerHTML = list.map(([k, v]) => `${k} <b>${v}</b>`).join('<i>·</i>');
    });

    const cells = [
      ['本周', money(week && week.cost)], ['30 日', money(month && month.cost)],
      ['总 tok', compact((today.input || 0) + (today.output || 0) + (today.cache_read || 0))],
      ['每调用', today.calls ? '$' + (today.cost / today.calls).toFixed(3) : '—']
    ];
    keyed($('cells'), cells, ([k]) => k,
      () => { const d = el('div'); d.append(el('span'), el('b')); return d; },
      (node, [k, v]) => { node.firstChild.textContent = k; node.lastChild.textContent = v; });

    $('today-foot').textContent =
      '本周 ' + integer(week && week.calls) + ' 次 · 30 日 ' + integer(month && month.calls) + ' 次';
    $('today-foot2').textContent = today.credited != null ? '已计费 ' + today.credited + ' 次' : '';

    // series 是整天的 24 个小时桶，末尾那些还没到的小时永远是 0；
    // 去掉尾部空桶再取最后三个，才不会把三个空桶当成最近三小时。
    const series = today.series || [];
    let end = series.length;
    while (end > 3 && !series[end - 1].calls) end -= 1;
    const hours = series.slice(0, end).slice(-3).reverse();
    const rhMax = Math.max(1, ...(today.series || []).map((h) => h.calls || 0));
    const box = $('recent-hours');
    if (!box.dataset.ready) {
      const title = el('span', null, '最近三小时');
      title.dataset.key = 'title';
      box.append(title);
      box.dataset.ready = '1';
    }
    keyed(box, hours, (h) => h.label,
      () => {
        const row = el('div', 'rh');
        const track = el('div', 'track');
        track.append(el('i'));
        row.append(el('b'), track, el('b'), el('em'));
        return row;
      },
      (node, h) => {
        const kids = node.children;
        kids[0].textContent = h.label + ' 时';
        kids[1].firstChild.style.width = share(h.calls || 0, rhMax) + '%';
        kids[2].textContent = integer(h.calls) + ' 次';
        kids[3].textContent = money(h.cost) + ' · 推理 ' + compact(h.reasoning);
      });
  }

  /* ── 额度 ── */
  function renderQuotas(quotas) {
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
        const box = el('div', 'q-group');
        const head = el('h3');
        head.append(el('b'), el('i'), el('em'));
        // 行放在内层容器里：keyed 会清掉所有不认识的子节点，标题不能和它们同级。
        box.append(head, el('div', 'q-rows'));
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
        const name = g.q.name || g.q.provider;
        head.children[0].textContent = mask(name);
        // plan 里常常已经写着账号名（如「ZCODE START PLAN」），重复就不再排一遍。
        const plan = g.q.plan && !String(g.q.plan).toUpperCase().includes(String(name).toUpperCase())
          && !String(name).toUpperCase().includes(String(g.q.plan).toUpperCase()) ? g.q.plan : '';
        head.children[1].textContent = plan ? mask(plan) : '';
        // 在岗标记放在账号行尾，不占窗口行的位置。
        head.children[2].textContent = g.q.last ? '在岗' : g.wins.length + ' 窗口';
        head.children[2].classList.toggle('on', !!g.q.last);

        keyed(node.querySelector('.q-rows'), g.wins, (w) => w.name,
          () => {
            const row = el('div', 'q');
            const top = el('div', 'q-top');
            top.append(el('b'), el('em'));
            const track = el('div', 'track');
            track.append(el('i'));
            row.append(top, track, el('div', 'q-sub'));
            return row;
          },
          (row, w) => {
            const name = row.children[0].children[0];
            const value = row.children[0].children[1];
            const bar = row.children[1].firstChild;
            const sub = row.children[2];

            name.textContent = w.name || '额度';
            const low = typeof w.remaining === 'number' && w.remaining <= 20;
            row.classList.toggle('low', low);
            row.classList.toggle('out', typeof w.remaining === 'number' && w.remaining <= 0);
            // 临近重置走琥珀通道：与 resetText 的「N 分钟后重置」同一档。
            const resetAt = w.resetsAt && !isNaN(new Date(w.resetsAt)) ? new Date(w.resetsAt).getTime() : null;
            const minsToReset = resetAt != null ? Math.round((resetAt - Date.now()) / 60000) : null;
            row.classList.toggle('soon', minsToReset != null && minsToReset >= 0 && minsToReset < 90);
            value.textContent =
              w.remaining <= 0 ? '用尽' : (typeof w.remaining === 'number' ? pct(w.remaining) : (w.display || '—'));
            bar.style.width = share(w.remaining || 0, 100) + '%';

            const bits = [resetText(w.resetsAt)];
            if (w.holds && w.holds.tokens) {
              bits.push(compact(w.holds.tokens) + ' tok 已占');
            } else if (w.amount != null && w.limit != null) {
              // credits 窗口用「已用 / 总额」表达，不再叠加 0/300 credits 这类原始串。
              bits.push(compact(w.amount) + ' / ' + compact(w.limit) + (w.unit && w.unit !== '%' ? ' ' + w.unit : ''));
            } else if (w.display && !/^\s*\d+\s*\/\s*\d+\s+credits?\s*$/i.test(w.display)) {
              bits.push(w.display);
            }
            if (w.holdsWhy) bits.push(WHY[w.holdsWhy] || w.holdsWhy);
            sub.textContent = bits.filter(Boolean).join(' · ');
          });
      });
    if (!groups.length) $('quota-list').replaceChildren(el('div', 'empty', '等待账号额度'));

    const wins = groups.flatMap((g) => g.wins);
    const nearest = wins.filter((w) => w.resetsAt && !isNaN(new Date(w.resetsAt)))
      .sort((a, b) => new Date(a.resetsAt) - new Date(b.resetsAt))[0];
    const noWin = groups.filter((g) => !g.wins.length).length;
    $('quota-note').textContent = shown.length + ' 账号 · ' + wins.length + ' 窗口 · 按余量升序';
    $('quota-foot').textContent = nearest ? '最近重置 · ' + resetText(nearest.resetsAt) : '';
    $('quota-foot').classList.toggle('soon',
      !!nearest && (new Date(nearest.resetsAt) - Date.now()) / 60000 < 90);
    $('quota-foot2').textContent = noWin ? '另有 ' + noWin + ' 个账号未上报窗口' : '全部账号均已上报窗口';
  }

  /* ── 智能体 ── */
  function renderAgents(today) {
    // 行高只够四行，多出的智能体并进「另 N 个」，不做裁切。
    const all = [...(today.agents || [])].sort((a, b) => (b.cost || 0) - (a.cost || 0));
    const agents = all.slice(0, 3);
    if (all.length > 3) {
      agents.push(all.slice(3).reduce((acc, a) => ({
        id: '__more', name: '另 ' + (all.length - 3) + ' 个',
        cost: (acc.cost || 0) + (a.cost || 0), calls: (acc.calls || 0) + (a.calls || 0),
        errors: (acc.errors || 0) + (a.errors || 0)
      }), {}));
    }
    keyed($('agent-list'), agents, (a) => a.id || a.name,
      () => { const row = el('div', 'a'); row.append(el('b'), el('em'), el('span')); return row; },
      (node, a) => {
        node.children[0].textContent = mask(a.name || a.id);
        node.children[1].textContent = money(a.cost);
        const bits = [integer(a.calls) + ' 次'];
        if (a.timed) bits.push((a.ttft_ms / a.timed / 1000).toFixed(1) + 's 首字');
        if (a.decode_ms) bits.push(Math.round(a.decode_out / (a.decode_ms / 1000)) + ' t/s');
        if (a.errors) bits.push('失败 ' + a.errors);
        if (a.reasoning) bits.push('推理 ' + compact(a.reasoning));
        node.children[2].textContent = bits.join(' · ');
      });
    if (!agents.length) $('agent-list').replaceChildren(el('div', 'empty', '等待智能体用量'));
    $('agent-foot').textContent = integer(today.calls) + ' 次 · ' + money(today.cost);
  }

  /* ── 链路共享读数：trace 路由整理与统计 ── */
  const median = (list) => {
    if (!list.length) return null;
    const s = [...list].sort((a, b) => a - b);
    const mid = s.length >> 1;
    return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
  };
  const secs = (ms) => ms == null ? '—' : (ms / 1000).toFixed(ms < 10000 ? 2 : 1) + 's';

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
  const ROUTE_C = { request: '#6ff2ff', response: '#9fd1ff', fail: '#ff7a7a', link: 'rgba(96, 158, 220, 0.34)', chip: 'rgba(9, 24, 44, 0.85)', edge: 'rgba(96, 158, 220, 0.42)' };
  const ROUTE_T = { req1: 700, req2: 800, res1: 1100, res2: 1100, fastK: 0.6 };
  const routeTrips = new Map();   // route id -> 进行中的行程
  const routeSpent = new Set();   // 已回放过的 route id：同一条路由只播一次
  const routeNodes = { agents: new Map(), models: new Map() }; // name -> { state: in|live|out, since, y }
  const routeRipples = [];        // 包裹进出网关的涟漪
  let routeBoot = false;          // 首帧只回放最新几条，历史路由不补播
  let routeRaf = 0;
  let routeLastTs = 0;
  let routeLayoutBusy = false;    // 节点还在淡入/淡出/重排时保持循环

  /** 最近 60 条里真实出现过的名字，按最近活跃排序。 */
  function recentNames(rows, key, cap) {
    const list = [];
    for (let i = rows.length - 1; i >= 0; i -= 1) {
      const name = rows[i][key];
      if (name && !list.includes(name)) list.push(name);
      if (list.length >= cap) break;
    }
    return list;
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

  function drawRouteChip(ctx, x, y, w, h, title, sub, accent, glow, alpha) {
    ctx.save();
    ctx.globalAlpha = alpha == null ? 1 : alpha;
    ctx.shadowColor = glow ? accent : 'transparent';
    ctx.shadowBlur = glow ? 12 : 0;
    ctx.fillStyle = ROUTE_C.chip;
    ctx.strokeStyle = glow ? accent : ROUTE_C.edge;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.roundRect(x, y, w, h, 3);
    ctx.fill();
    ctx.stroke();
    ctx.shadowBlur = 0;
    ctx.fillStyle = glow ? '#ffffff' : '#f2f9ff';
    ctx.font = '600 10.5px ui-monospace, "SF Mono", Menlo, monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'alphabetic';
    ctx.fillText(title, x + w / 2, y + h / 2 - 1, w - 10);
    ctx.fillStyle = glow ? accent : '#7e95ad';
    ctx.font = '400 8.5px ui-monospace, "SF Mono", Menlo, monospace';
    ctx.fillText(sub, x + w / 2, y + h / 2 + 11, w - 10);
    ctx.restore();
  }

  function drawRouteComet(ctx, p, t0, t1, color, width) {
    const steps = 10;
    ctx.save();
    ctx.lineCap = 'round';
    ctx.shadowColor = color;
    ctx.shadowBlur = 7;
    // 外圈柔光：一次更宽更淡的描边，给彗星体积感。
    ctx.globalAlpha = 0.09;
    ctx.lineWidth = width * 2.8;
    ctx.strokeStyle = color;
    {
      const [sx, sy] = cubicAt(p, t0);
      const [ex, ey] = cubicAt(p, t1);
      ctx.beginPath();
      ctx.moveTo(sx, sy);
      ctx.lineTo(ex, ey);
      ctx.stroke();
    }
    // 尾巴：淡 → 亮两段，头部一颗亮点。
    for (let i = 0; i < steps; i += 1) {
      const a = t0 + (t1 - t0) * (i / steps);
      const b = t0 + (t1 - t0) * ((i + 1) / steps);
      ctx.strokeStyle = color;
      ctx.globalAlpha = 0.12 + 0.7 * (i / steps);
      ctx.lineWidth = width * (0.5 + 0.5 * (i / steps));
      ctx.beginPath();
      const [x0, y0] = cubicAt(p, a);
      const [x1, y1] = cubicAt(p, b);
      ctx.moveTo(x0, y0);
      ctx.lineTo(x1, y1);
      ctx.stroke();
    }
    const [hx, hy] = cubicAt(p, t1);
    ctx.globalAlpha = 1;
    ctx.fillStyle = '#eafcff';
    ctx.beginPath();
    ctx.arc(hx, hy, width * 0.85 + 0.6, 0, Math.PI * 2);
    ctx.fill();
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

    // 拓扑：登记表驱动——新节点淡入、离场节点淡出、位置缓动重排；
    // 活跃行程的端点在 syncRouteNodes 里优先占位，这里只读登记表。
    routeLayoutBusy = false;
    const reduce = routeReduceQuery.matches;
    if (!routeNodes.agents.size && !routeNodes.models.size) {
      ctx.fillStyle = '#7e95ad';
      ctx.font = '400 10px "Avenir Next", "PingFang SC", sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText('等待第一条路由', W / 2, H / 2 + 4);
      return;
    }

    const agentW = Math.min(148, W * 0.16), modelW = Math.min(158, W * 0.17), gwW = 108, chipH = 34;
    const agentX = 4, modelX = W - modelW - 4, gwX = (W - gwW) / 2;
    const alphaOf = (node) => {
      if (reduce) return node.state === 'out' ? 0 : 1;
      if (node.state === 'in') return Math.min(1, (now - node.since) / 500);
      if (node.state === 'out') return Math.max(0, 1 - (now - node.since) / 600);
      return 1;
    };
    // 布局：在册节点缓动到目标位（稳定序，避免每次轮询跳位）；退场节点原地淡出。
    const layout = (reg) => {
      if (!reduce) reg.forEach((n) => { if (n.state === 'in' && now - n.since > 500) n.state = 'live'; });
      const live = [...reg.entries()].filter(([, n]) => n.state !== 'out');
      const pos = new Map();
      live.forEach(([name, node], i) => {
        const target = ((i + 1) / (live.length + 1)) * (H - chipH - 8) + 4 + chipH / 2;
        if (node.y == null || reduce) node.y = target;
        else {
          node.y += (target - node.y) * 0.22;
          if (Math.abs(target - node.y) > 0.75) routeLayoutBusy = true;
        }
        pos.set(name, node.y);
      });
      reg.forEach((node, name) => { if (node.state === 'out' && node.y != null) pos.set(name, node.y); });
      return pos;
    };
    const agentPos = layout(routeNodes.agents);
    const modelPos = layout(routeNodes.models);

    // 网关底光：待机时呼吸，忙碌时恒定微光——机舱的核心总有一点亮。
    const gwGlow = stageIdle ? (reduce ? 0.10 : 0.10 + 0.06 * Math.sin(now / 700)) : 0.08;
    const gwGlowR = Math.min(W, H) * 0.42;
    const underglow = ctx.createRadialGradient(W / 2, H / 2, 0, W / 2, H / 2, gwGlowR);
    underglow.addColorStop(0, 'rgba(111, 242, 255, ' + gwGlow.toFixed(3) + ')');
    underglow.addColorStop(1, 'rgba(111, 242, 255, 0)');
    ctx.fillStyle = underglow;
    ctx.fillRect(W / 2 - gwGlowR, H / 2 - gwGlowR, gwGlowR * 2, gwGlowR * 2);

    // 链路底图：虚线，随节点一起淡入淡出。
    ctx.save();
    ctx.setLineDash([2, 5]);
    routeNodes.agents.forEach((node, name) => {
      const y = agentPos.get(name);
      const alpha = alphaOf(node);
      if (y == null || alpha <= 0.02) return;
      const p = legPoints(agentX + agentW, y, gwX, H / 2);
      ctx.globalAlpha = alpha;
      ctx.strokeStyle = ROUTE_C.link;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(p[0], p[1]);
      ctx.bezierCurveTo(p[2], p[3], p[4], p[5], p[6], p[7]);
      ctx.stroke();
    });
    routeNodes.models.forEach((node, name) => {
      const y = modelPos.get(name);
      const alpha = alphaOf(node);
      if (y == null || alpha <= 0.02) return;
      const p = legPoints(gwX + gwW, H / 2, modelX, y);
      ctx.globalAlpha = alpha;
      ctx.strokeStyle = ROUTE_C.link;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(p[0], p[1]);
      ctx.bezierCurveTo(p[2], p[3], p[4], p[5], p[6], p[7]);
      ctx.stroke();
    });
    ctx.restore();

    // 待机声呐：没有触发的智能体和模型时，网关自己一圈圈向外呼吸。
    if (stageIdle && !reduce) {
      for (let i = 0; i < 2; i += 1) {
        const p = ((now / 2600) + i * 0.5) % 1;
        const r = gwW / 2 + 6 + p * Math.min(H, W) * 0.32;
        ctx.save();
        ctx.globalAlpha = (1 - p) * 0.34;
        ctx.strokeStyle = ROUTE_C.request;
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.arc(W / 2, H / 2, r, 0, Math.PI * 2);
        ctx.stroke();
        ctx.restore();
      }
    }

    // 包裹：沿链路移动的彗星；在途的停在模型处脉冲。端点坐标取节点当前位置，重排时彗星跟着走。
    const activeAgents = new Set(), activeModels = new Set();
    let parkedCount = 0;
    let transit = 0;
    routeTrips.forEach((trip) => {
      const an = routeNodes.agents.get(trip.agent);
      const mn = routeNodes.models.get(trip.model);
      if (!an || !mn || an.y == null || mn.y == null) return;
      const ay = an.y, my = mn.y;
      const leg1 = legPoints(agentX + agentW, ay, gwX, H / 2);
      const leg2 = legPoints(gwX + gwW, H / 2, modelX, my);
      const elapsed = now - trip.startedAt;
      const speed = trip.fast ? ROUTE_T.fastK : 1;
      if (trip.phase === 'req1') {
        const t = Math.min(1, elapsed / (ROUTE_T.req1 * speed));
        activeAgents.add(trip.agent);
        transit += 1;
        drawRouteComet(ctx, leg1, Math.max(0, t - 0.3), t, trip.color, trip.width);
        if (t >= 1) {
          trip.phase = 'req2'; trip.startedAt = now;
          routeRipples.push({ x: gwX, y: H / 2, at: now, color: trip.color });
        }
      } else if (trip.phase === 'req2') {
        const t = Math.min(1, elapsed / (ROUTE_T.req2 * speed));
        activeAgents.add(trip.agent);
        transit += 1;
        drawRouteComet(ctx, leg2, Math.max(0, t - 0.3), t, trip.color, trip.width);
        if (t >= 1) { trip.phase = trip.park ? 'parked' : 'res1'; trip.startedAt = now; }
      } else if (trip.phase === 'parked') {
        parkedCount += 1;
        activeModels.add(trip.model);
        // 停在模型处：一颗常亮包裹 + 呼吸环，快照确认完成才放行。
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
        ctx.restore();
      } else if (trip.phase === 'res1') {
        activeModels.add(trip.model);
        transit += 1;
        const t = Math.min(1, elapsed / (ROUTE_T.res1 * speed));
        const back = [leg2[6], leg2[7], leg2[4], leg2[5], leg2[2], leg2[3], leg2[0], leg2[1]];
        drawRouteComet(ctx, back, Math.max(0, t - 0.3), t, trip.color, trip.width);
        if (t >= 1) {
          trip.phase = 'res2'; trip.startedAt = now;
          routeRipples.push({ x: gwX + gwW, y: H / 2, at: now, color: trip.color });
        }
      } else if (trip.phase === 'res2') {
        const t = Math.min(1, elapsed / (ROUTE_T.res2 * speed));
        const back = [leg1[6], leg1[7], leg1[4], leg1[5], leg1[2], leg1[3], leg1[0], leg1[1]];
        drawRouteComet(ctx, back, Math.max(0, t - 0.3), t, trip.color, trip.width);
        transit += 1;
        activeAgents.add(trip.agent);
        if (t >= 1) { trip.phase = 'done'; trip.startedAt = now; }
      } else if (trip.phase === 'done') {
        // 落地一闪：智能体芯片外圈快速收敛。
        const k = Math.min(1, elapsed / 500);
        if (k < 1) {
          ctx.save();
          ctx.strokeStyle = trip.color;
          ctx.globalAlpha = 0.7 * (1 - k);
          ctx.lineWidth = 1.4;
          ctx.beginPath();
          ctx.arc(agentX + agentW, ay, 8 + 16 * k, 0, Math.PI * 2);
          ctx.stroke();
          ctx.restore();
          activeAgents.add(trip.agent);
        }
      }
    });

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

    // 芯片：智能体 / 网关 / 模型。智能体名按遮蔽设置渲染。
    const agentCalls = new Map(), modelMs = new Map();
    rows.forEach((r) => {
      agentCalls.set(r.agent, (agentCalls.get(r.agent) || 0) + 1);
      if (r.ms) {
        const list = modelMs.get(r.model) || [];
        list.push(r.ms);
        modelMs.set(r.model, list);
      }
    });
    routeNodes.agents.forEach((node, name) => {
      const y = agentPos.get(name);
      const alpha = alphaOf(node);
      if (y == null || alpha <= 0.02) return;
      drawRouteChip(ctx, agentX, y - chipH / 2, agentW, chipH,
        mask(name), integer(agentCalls.get(name) || 0) + ' 次', ROUTE_C.request, activeAgents.has(name), alpha);
    });
    routeNodes.models.forEach((node, name) => {
      const y = modelPos.get(name);
      const alpha = alphaOf(node);
      if (y == null || alpha <= 0.02) return;
      drawRouteChip(ctx, modelX, y - chipH / 2, modelW, chipH,
        name, secs(median(modelMs.get(name) || [])), ROUTE_C.response, activeModels.has(name), alpha);
    });
    drawRouteChip(ctx, gwX, H / 2 - chipH / 2, gwW, chipH, 'MAGPIE 网关',
      '今日 ' + integer(todayCalls) + ' · 在途 ' + running,
      ROUTE_C.request, parkedCount > 0 || running > 0 || transit > 0);
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
    if (!active && !breathing && !routeLayoutBusy && !routeRipples.length) {
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

    // 拓扑对账：活跃行程的端点优先占位，其次按最近活跃；进出场走淡入淡出。
    const tripAgentNames = [], tripModelNames = [];
    routeTrips.forEach((t) => {
      if (t.phase !== 'done') {
        if (!tripAgentNames.includes(t.agent)) tripAgentNames.push(t.agent);
        if (!tripModelNames.includes(t.model)) tripModelNames.push(t.model);
      }
    });
    const agentNames = [...new Set([...tripAgentNames, ...recentNames(rows, 'agent', 3)])].slice(0, 3);
    const modelNames = [...new Set([...tripModelNames, ...recentNames(rows, 'model', 3)])].slice(0, 3);
    syncRouteNodes('agents', agentNames, now);
    syncRouteNodes('models', modelNames, now);

    // 快照对账：新路由开程（每条只播一次），已在途的确认完成后放行回程。
    const seenIds = new Set();
    if (!routeBoot) {
      routeBoot = true;
      // 首帧：只有最新 3 条算「新闻」，其余历史路由直接标记已回放。
      rows.slice(0, Math.max(0, rows.length - 3)).forEach((r) => routeSpent.add(r.id));
    }
    rows.forEach((r) => {
      seenIds.add(r.id);
      if (routeSpent.has(r.id)) return;
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
    $('route-foot').textContent = '快照回放 · 4 秒轮询 · 非逐 token 观测';
    $('route-foot2').textContent = !rows.length
      ? '等待第一条路由'
      : idle
        ? '网关待机 · 中位 ' + secs(median(okMsList)) + ' · 最近 ' + rows.length + ' 条'
        : '在途 ' + running + ' · 中位 ' + secs(median(okMsList)) + (badCount ? ' · 失败 ' + badCount : '');
    $('route-note').textContent = '智能体 → 网关 → 模型 · 4 秒快照回放';

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
    const { today, week, month, quotas } = bundle;
    renderToday(today, week, month);
    renderQuotas(quotas);
    renderAgents(today);
    renderRouteStage(bundle);
    // 顶栏：网关状态灯 + 时钟；快照时间收进页脚。
    $('gw-label').textContent = online ? '网关在线' : '网关离线';
    $('source-note').textContent = '数据仅取自 127.0.0.1:3425 · 邮箱已遮蔽 · ' +
      (online ? '网关在线' : '网关离线 · 保留上次数据') +
      (bundle.at ? ' · 快照 ' + clockOf(new Date(bundle.at).toISOString()) : '');
    document.body.classList.toggle('offline', !online);
  }

  async function refresh() {
    try {
      const [today, week, month, quotas, trace] = await Promise.all([
        get('/v1/magpie/usage?period=today'),
        get('/v1/magpie/usage?period=7d'),
        get('/v1/magpie/usage?period=30d'),
        get('/v1/magpie/quotas'),
        get('/v1/magpie/trace')
      ]);
      online = true;
      lastGood = { today, week, month, quotas, trace, at: Date.now() };
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

  /* 轮询与 Watch 一致：先取数据再等待，周期 4 秒。 */
  (async function loop() {
    for (;;) {
      await refresh();
      await new Promise((resolve) => setTimeout(resolve, POLL_MS));
    }
  })();
})();
