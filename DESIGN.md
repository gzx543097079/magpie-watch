# 巡检站 / Station Course

## Intent

Magpie 的数据模块作为桌面壁纸：信息尽可能密，但排布必须稳。不是卡片墙。第二行整行留给「多节点往返」舞台——它不是装饰性的流向动画，每一次往返都对应一条此刻正在进行的真实调用（trace 里 `done === false` 的路由）。没有在途调用时舞台不拿历史数据凑画面，只让网关做待机呼吸。

## Composition

- Native desktop wallpaper behind icons, full mouse passthrough, one window per display.
- Left Dock inset via `--dock-left` from `NSScreen.visibleFrame`, a right column reserved for the user's folder stack via `--dock-right` (Preferences, 0–260 pt, default 120), and `--dock-bottom`. Fullscreen / screensaver clears all three, so the board fills both edges.
- Two columns on one screen: the left third is every account quota window, full height, one window per row, grouped by account with generous air between groups; accounts that report no window collapse into a single trailing line instead of one row each; the right two thirds stack three bands — today / the live data stream / agents.
- Avenir Next / PingFang SC. Navy ground `#020912`. Sequential mark `#3987e5` (validated dark slot 1). Quota identity stays on that one hue; `#d95926` and `#199e70` appear only where a second or third category is genuinely needed. Live `#68ebff` marks the current account only. Exhausted quota `#e66767`.
- No cards, no Three.js, no ambient animation. The live panel is read, not watched: values update in place every 4 s, and the only motion is a single fade on a row that just arrived.

## Motion and truth

Polling rewrites values in place against stable DOM keys, so nothing flickers and no layout shifts. Exhausted quotas keep their row and colour only the number. Reduce Motion disables transitions entirely. Demo data is labelled 演示数据. Unknown values stay 「—」. Emails stay masked in this ambient view, and are masked again after each fetch.

The page polls `127.0.0.1:3425` itself, once every 4 s (refresh then sleep), through Watch’s loopback-only same-origin server: it serves the static page and reverse-proxies `/v1/magpie/*`, so no CORS and no field projection in Swift. Magpie’s own cadence is not claimed. A failed round keeps the last good frame and only marks the status stale; it never blanks the desktop.

## Data panels

Wallpaper shows four modules on one 1920×1080 screen — every account quota window in the left third with reset countdown and hold records; today’s spend with cache hit rate, DeepSeek equivalent value, full flow and three most recent hours in a two-column body; the live data-stream panel (KPI strip, duration chart, two distributions, route table); agents with latency. Density is held by one 12-column grid, one type scale (9/10/11.5/12/12.5/16/46), and one spacing set; hierarchy comes from size and weight, never from colour or boxes. Row heights are proportional, so other displays do not overflow. Stations show today / week / month token totals, input / output / cache, calls / errors / retries / sessions, TTFT and decode rate, hourly request columns, and agent ranks — plus the live route stream. A subscription percentage is not a currency balance. Unknown values remain unknown; stale snapshots are marked. Context attribution is labelled separately and never added to billed usage.

The live data stream replaces the animated round trip. It is a data-centre panel, not a decoration: a KPI strip (in flight, median duration, median TTFT, output tokens, failures), a per-route duration column chart drawn from the last 60 real routes with a dashed median line and failures in red, a model distribution and a folder distribution ranked by calls and output, and a route table of time / agent / model / duration / TTFT / output. Every mark comes from the trace; nothing is interpolated or replayed, and the table is the same numbers as the chart so the two can be checked against each other. In-flight routes draw their elapsed time with an ellipsis; the median line is the only horizontal rule in the panel.

Failure is stated, not implied. A route with a non-200 status or a `fail` on any attempt renders red in the chart, the model bar and the table row, the failure KPI names the reason (额度用尽 / 超时 / 限流 …), and the module footer repeats the count. The upstream English error stays in the row's tooltip.

The workbench combines request ledger entries with trace by route ID. Prefer ledger accounting; never add trace counts again. Reasoning is included in output. Decode prompt.parts and item labels only, without retaining request body text. Tool definitions do not prove tool execution. Preserve selection and disclosure state across polling.

## Verification

Native packaged app renders the wallpaper. Swift tests cover consumption accounting and quota percent vs money. Chart marks use validated dark slot `#3987e5,#d95926,#199e70` on `#020912`. Dock inset and fullscreen zero-inset are layout variables, not decorations.
