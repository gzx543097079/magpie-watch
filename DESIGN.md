---
name: MagpieWatch 数据观测台
description: 本地 Magpie 网关的桌面壁纸数据中心（NOC）视觉系统
colors:
  ground: "#020912"
  ink: "#f2f9ff"
  muted: "#b9cde3"
  dim: "#7e95ad"
  dim2: "#63829f"
  live: "#6ff2ff"
  mark: "#4aa3ff"
  mark-soft: "#2f7fd6"
  output-ice: "#9fd1ff"
  void: "#ff7a7a"
  amber: "#ffbc7d"
  hairline: "rgba(96, 158, 220, 0.22)"
  hair-faint: "rgba(70, 120, 170, 0.16)"
typography:
  display:
    fontFamily: "ui-monospace, 'SF Mono', Menlo, Monaco, monospace"
    fontSize: "45px"
    fontWeight: 600
    lineHeight: 0.9
    letterSpacing: "-0.03em"
  kpi:
    fontFamily: "ui-monospace, 'SF Mono', Menlo, Monaco, monospace"
    fontSize: "21px"
    fontWeight: 600
    lineHeight: 1.05
    letterSpacing: "-0.02em"
  body:
    fontFamily: "'Avenir Next', 'PingFang SC', -apple-system, sans-serif"
    fontSize: "10.5px"
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: "0.04em"
  label:
    fontFamily: "'Avenir Next', 'PingFang SC', -apple-system, sans-serif"
    fontSize: "10px"
    fontWeight: 600
    lineHeight: 1.4
    letterSpacing: "0.16em"
  mono-code:
    fontFamily: "ui-monospace, 'SF Mono', Menlo, Monaco, monospace"
    fontSize: "8.5px"
    fontWeight: 400
    letterSpacing: "0.14em"
rounded:
  cabinet: "2px"
  led: "50%"
spacing:
  mod-pad: "9px 16px 11px"
  column-gap: "26px"
  row-gap: "18px"
  inner-gap: "11px 30px"
components:
  cabinet:
    backgroundColor: "rgba(9, 24, 44, 0.42)"
    textColor: "{colors.ink}"
    rounded: "{rounded.cabinet}"
  track-bar:
    backgroundColor: "rgba(30, 60, 95, 0.55)"
    textColor: "{colors.mark}"
    height: "3px"
---

# Design System: MagpieWatch 数据观测台

## Overview

**Creative North Star: 「自家机房的大屏」——本地网关的数据中心指挥舱（NOC）**

壁纸是一座正在运转的数据中心：每块面板是一台机柜的仪表屏，深空海军地面铺着极淡的蓝图网格，四角带青色角标的 HUD 机柜框里是等宽数字读数。光只表达真实状态——在途、失败、余量将尽、重置临近、离线——从不为装饰而亮。所有数字来自本机网关的原始 JSON：请求账本约 1 秒原位改写，额度与聚合用量约 4 秒刷新，无闪烁无布局位移。

**Key Characteristics:**
- 机柜 = 1px 发丝框 + 四角青色角标 + 呼吸 LED 标题行 + mono 模块代号
- 读数一律等宽字体，中文标签用 Avenir Next / PingFang SC
- 动效一次编排：一条 30s 扫描微光做环境，其余光全是数据事件（新请求扫光、数值闪辉、耗尽闪烁）
- 离线时机柜角标转红、画面压暗、扫描暂停——降级也是状态

## Colors

冷色单相：蓝青为体，红与琥珀只作状态信号。

### Primary
- **实时青 Live Cyan** (#6ff2ff): 在途、最新、当前；LED、英雄数字辉光、新路由扫光、实时模块角标。
- **顺序蓝 Mark Blue** (#4aa3ff / #2f7fd6): 额度与分布条的顺序读数，账号圆点。

### Secondary
- **失败红 Void** (#ff7a7a): 失败路由、低余量（≤20%）、用尽（0）、离线；永远伴随闪烁或常亮辉光，不作它用。
- **临近琥珀 Amber** (#ffbc7d): 重置 <90 分钟的窗口与「最近重置」页脚；比红缓一级的预警。
- **输出冰蓝 Output Ice** (#9fd1ff): 输出类读数的冰蓝，与缓存读蓝、新输入青区分。

### Neutral
- **深空地 Ground** (#020912): 壁纸地面，网格与光晕都铺在其上。
- **面板墨 Ink** (#f2f9ff): 主读数白，带青辉。
- **次级 Muted / Dim / Dim2** (#b9cde3 / #7e95ad / #63829f): 标签、副读数、页脚，三级递暗。
- **发丝线 Hairline** (rgba(96,158,220,0.22) / rgba(70,120,170,0.16)): 机柜框与内部隔线。

### Named Rules
**状态光规则。** 每一处光都必须能回答「它代表什么数据状态」；回答不了的辉光删掉。
**红色最急规则。** 红 > 琥珀 > 青：余量用尽的窗口即使临近重置也保持红色，CSS 里红色规则永远写在琥珀之后。

## Typography

**Display/KPI:** ui-monospace（SF Mono）——所有数字读数
**Body/Label:** Avenir Next / PingFang SC——中文标签与说明
**模块代号:** mono 8.5px 全大写加宽字距（ACC.QUOTA / TODAY / LIVE.STREAM / AGENTS）

**Character:** 仪表而非文章——数字是主语，mono 保证逐位对齐与仪器感；中文只做标签，不与数字争字号。

### Hierarchy
- **Display** (mono 600, 45px): 今日支出英雄数字，三重青辉；额度机架大数字 34px。
- **KPI** (mono 600, 21–24px): 实时条读数、缓存命中率、DeepSeek 等价。
- **Title** (mono 500, 17px): 今日四小格。
- **Body** (mono 500, 10–12px): 路由表、额度百分比、小时读数。
- **Label** (sans 600, 10px, 0.16em): 模块标题；副注 9–9.5px。

## Layout

12 列网格。左 4 列账号额度机柜整列（`grid-row: 1 / -1`），右 8 列三段：今日 / 实时路由（主视觉）/ 上下文窗口。桌面态左侧只让开 Dock 本身（`--dock-left` = Dock 宽 + 12pt − 页面 36px 边距；Dock 自动隐藏或不在左侧时为 0），右侧让开文件夹列（`--dock-right`），底部让开（`--dock-bottom`），全屏时三者归零顶满两边。

## Elevation & Depth

无投影。深度来自三层叠加：蓝图网格地面 → 半透明机柜底（rgba(9,24,44,0.42)）→ 辉光读数。一条 30s 循环的横向扫描微光（rgba(111,242,255,0.03–0.065)，22vh 高）以 transform 扫过整屏，是唯一的常驻环境动画；示波器刻度线与虚线中位线提供仪表纵深感。

## Shapes

直角为体：机柜只有 2px 微圆角，唯一圆形是状态 LED（7px / 4px 圆点）。角标是 9×1px 的 L 形高光，叠在机柜四角上，颜色由 `--tick-c` 驱动（常态青、blip 提亮、alert/离线转红）。进度条 2–4px 高、无圆角、顶端一段 34px 流光（只挂额度条）。

## Components

### 机柜 Cabinet
- **形状:** 1px 发丝框（2px 圆角）+ 四角 L 形角标 + 顶缘 4.5% 青光
- **底色:** rgba(9,24,44,0.42)，上浅下深渐变
- **标题行:** 3×9px LED 条（呼吸停用，状态驱动）+ 中文标题 + mono 代号 + 右侧实时副注
- **页脚:** 发丝线上方一行 9.5px 读数（失败红 / 临近琥珀）

### 读数条 Track
- **轨道:** 2–4px，rgba(30,60,95,0.55)
- **填充:** 蓝渐变（#2f7fd6→#4aa3ff）+ 7px 外辉；低余量转红渐变；用尽转暗红并停流光
- **状态:** `.soon` 琥珀读数、`.low` 红读数+2.2s 闪烁、`.out` 1.1s 快闪

### 实时路由 Routing Stage（签名组件）
- **来源:** magpie 路由页 `.rt-stage` 的移植（`design/routing-stage.js` / `.css`）：左 agent、中 magpie、右账号行；连线是 magpie 的 `curve()`，喜鹊叼着请求点沿线飞，账号作答时点停在线头闪烁，回信由另一只喜鹊带回，失败的点回到 magpie 再转给下一个。座次、行上的话、点亮规则与原页一致。
- **数据:** 只读主程序网关 `/v1/magpie/trace?after=seq` 增量，不另起 `magpie web`（多一个 magpie 进程就多一方轮换 OAuth 令牌）。
- **皮肤:** 变量收在 `.rt-live` 里换成壁纸配色，选中行用实时青；按机柜宽度整体缩放，窄时退成 magpie 的 max560 布局。

### 上下文窗口 Context Waffle
- **来源:** magpie context.js 的 ctxCard 格子算法：窗口均分 400 格，按 token 占比着色（系统 / 工具 / 记忆 / 文件 / 返回 / 对话），空格是剩余窗口。取在途请求，没有在途就取最近一次带 prompt 的，不编造。

### KPI 条
- **形状:** 上下发丝线夹一行，竖线分格，mono 21px 白字青辉
- **状态:** 失败格整体转红；数值变化时 0.9s 辉光短闪（`.tick`）

### 电源墙 Power Wall
- **形态:** 每账号一个机架单元，左右两栏。左栏一个 34px 大数字 = 账号最紧窗口的剩余%，下注「5 小时 剩余」；颜色即状态（冰白正常 / 琥珀临近重置 / 红紧张与用尽）。右栏首行 产品名 + 遮蔽后的账号前缀 · 套餐（同名账号靠它区分），状态词只在异常时出现，正常不写字。其下每个窗口一行：窗口名 · 9px 带 25/50/75 刻度的燃料条 · 剩余% · 重置倒计时，列宽固定，整列上下对齐。
- **匀速刻线:** 燃料条上一根白色竖线 = 按窗口剩余时间占比此刻应剩多少（窗口时长从窗口名读，读不出不画）。条尾落在刻线左侧 8 个点以上 = 超速，读数转琥珀。模块副注写明「刻线 = 匀速应剩」。
- **排序:** 账号先按状态档（用尽 > 紧张 > 临近重置 > 正常）把出事的顶上来，同档按名字固定；窗口按时长固定（5 小时在 7 天上）。不按余量排，避免每次刷新换位。
- **估算:** 按窗口内真实下降速率推算「估算 X 后 Y 用尽」（速率 <0.5%/h 或重置先到不估），琥珀小字；令牌占用同一行暗色。用尽时大数字快闪、燃料条转暗红。

## Do's and Don'ts

### Do:
- **Do** 让每一处光对应一个真实数据状态（在途/失败/低余量/临近重置/离线）。
- **Do** 用 mono 排一切数字，sans 排一切中文标签。
- **Do** 轮询原位改写 DOM（keyed 复用），未知值保持「—」。
- **Do** 尊重 Reduce Motion：`prefers-reduced-motion` 下停掉全部动画与过渡，静态结构保留。

### Don't:
- **Don't** 用 Three.js/WebGL 场景或粒子海洋——这是仪表墙，不是风景。
- **Don't** 发明流量或演示数据；请求、令牌与耗时只来自真实请求账本。
- **Don't** 在被动视图展示未遮蔽的邮箱——所有渲染字符串经 `mask()`。
- **Don't** 给与数据无关的元素加常驻动画；环境动画只有扫描微光与额度条流光。
