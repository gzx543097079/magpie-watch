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
  route-response: "#9fd1ff"
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

壁纸是一座正在运转的数据中心：每块面板是一台机柜的仪表屏，深空海军地面铺着极淡的蓝图网格，四角带青色角标的 HUD 机柜框里是等宽数字读数。光只表达真实状态——在途、失败、余量将尽、重置临近、离线——从不为装饰而亮。所有数字来自本机网关的原始 JSON，4 秒原位改写，无闪烁无布局位移。

**Key Characteristics:**
- 机柜 = 1px 发丝框 + 四角青色角标 + 呼吸 LED 标题行 + mono 模块代号
- 读数一律等宽字体，中文标签用 Avenir Next / PingFang SC
- 动效一次编排：一条 30s 扫描微光做环境，其余光全是数据事件（新路由扫光、往返包裹、数值闪辉、在途呼吸、耗尽闪烁）
- 离线时机柜角标转红、画面压暗、扫描暂停——降级也是状态

## Colors

冷色单相：蓝青为体，红与琥珀只作状态信号。

### Primary
- **实时青 Live Cyan** (#6ff2ff): 在途、最新、当前；LED、英雄数字辉光、新路由扫光、实时模块角标。
- **顺序蓝 Mark Blue** (#4aa3ff / #2f7fd6): 额度与分布条的顺序读数，账号圆点。

### Secondary
- **失败红 Void** (#ff7a7a): 失败路由、低余量（≤20%）、用尽（0）、离线；永远伴随闪烁或常亮辉光，不作它用。
- **临近琥珀 Amber** (#ffbc7d): 重置 <90 分钟的窗口与「最近重置」页脚；比红缓一级的预警。
- **回程冰蓝 Route Response** (#9fd1ff): 链路舞台的回程序彗星，与请求程青色区分方向；只在 LIVE.ROUTE 画布内使用。

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
- **Display** (mono 600, 45px): 今日支出英雄数字，三重青辉。
- **KPI** (mono 600, 21–24px): 实时条读数、缓存命中率、DeepSeek 等价。
- **Title** (mono 500, 17px): 今日四小格。
- **Body** (mono 500, 10–12px): 路由表、额度百分比、小时读数。
- **Label** (sans 600, 10px, 0.16em): 模块标题；副注 9–9.5px。

## Layout

12 列网格，行高 24fr / 60fr / 16fr。左 4 列账号额度机柜整列（`grid-row: 1 / -1`），右 8 列三段：今日 / 实时链路（主视觉）/ 智能体。桌面态左侧让开 Dock（`--dock-left`）、右侧让开文件夹列（`--dock-right`）、底部让开（`--dock-bottom`），全屏时三者归零顶满两边。

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

### 路由表 Route Table
- **形状:** mono 9.5px，7 列网格（62px 时间 + 智能体/模型弹性 + 右对齐读数），列距 10px
- **状态:** 在途行耗时格 1.6s 呼吸；新行 `.fresh` 一道 34% 宽青光 0.95s 扫过；失败行读数红辉

### 链路舞台 Route Stage（签名组件）
- **拓扑（星系）:** 中央恒星 = 网关（3D 核心/吸积盘/能量波即恒星外观，下方铭牌「MAGPIE 网关 / 今日 N · 在途 N」）；智能体与模型是两侧椭圆轨道上的**行星**——新月式光照（深空暗球 + 晨昏线 + 朝恒星的发光临边弧）、渐变大气辉光、约 1/3 带斜光环（名称哈希决定），名称与读数标于行星下方，半径随调用量增长，入场物质化缩放；每颗行星一条淡虚线轨道弧，沿轨道缓慢漂移
- **节点生命周期:** 智能体与模型**只在触发时出现**——最近 30 秒内有活动（活动时刻 = 路由完成时刻，长请求按完整生命周期算）或仍有在途行程才登场；30 秒无活动淡出退场；正在飞行的行程优先保住自己的端点行星，彗星跟随行星漂移
- **链路:** 引力束——活跃行星与恒星之间一道流动光束（宽辉光垫底 + 流动虚线），空闲只见轨道；包裹彗星带宽辉光尾流、十字耀斑、环绕电火花与尾焰粒子，**每一站都有事件特效**（坠入/离开恒星涟漪+火花+恒星弹跳，命中行星冲击波+火花迸射，落地行星火花绽开），在途包裹两颗电子环绕
- **状态:** 请求程青、回程冰蓝、失败红；在途包裹停在模型处脉冲，快照确认完成才放行；每条路由只回放一次；包裹粗细按 log(token 体量) 1.4–3.6px
- **网关 3D 核心（常驻）:** 科幻能量核永远罩着网关芯片，发光层全部加性混光（lighter）——经纬线框球（深度后暗前亮）+ 双陀螺环 + **吸积盘**（130 颗粒子开普勒速度内快外慢）+ 26 颗带拖尾环绕粒子 + 纬度能量波 + 中心发光核 + 过境光刺。待机呼吸态慢速环绕 + 声呐；运转态随吞吐粒子增密提速、辉光增强。链路虚线按方向流动，活跃链路辉光垫底；芯片全息入场（光柱 + 底座光垫）；背景星尘漂移；彗星带十字耀斑。页脚常驻「快照回放 · 4 秒轮询 · 非逐 token 观测」并吸收在途/中位/失败读数

### KPI 条
- **形状:** 上下发丝线夹一行，竖线分格，mono 21px 白字青辉
- **状态:** 失败格整体转红；数值变化时 0.9s 辉光短闪（`.tick`）

### 燃尽曲线 Burn Spark
- **位置:** 额度机柜每账号标题下，14px 高画布
- **形态:** 当前窗口剩余额度折线（青 0.75 透明度）+ 蓝色 16% 填充 + 末端亮点；<2 点不画
- **估算:** 按窗口内真实下降速率推算「估算 X 后用尽」（速率 <0.5%/h 或重置先到不估），注在窗口行与模块页脚（琥珀），一律带「估算」字样

### 24 小时节奏 Rhythm
- **形态:** 今日模块右栏底部，一排小时柱（≤14px 宽，高度 ∝ 调用数），当前小时青色渐变+辉光，零时柱 10% 暗蓝
- **标注:** 标题行「24 小时节奏 | 峰值 N 次 · HH 时」；悬停看 时·次·费用

### 调用占比条 Share
- **形态:** 智能体名下 2px 细轨，宽度 = 该智能体调用数 / 最活跃智能体，蓝渐变微辉；配「X 分钟前活跃」副注（trace 最后触发时刻）

## Do's and Don'ts

### Do:
- **Do** 让每一处光对应一个真实数据状态（在途/失败/低余量/临近重置/离线）。
- **Do** 用 mono 排一切数字，sans 排一切中文标签。
- **Do** 轮询原位改写 DOM（keyed 复用），未知值保持「—」。
- **Do** 尊重 Reduce Motion：`prefers-reduced-motion` 下停掉全部动画与过渡，静态结构保留。

### Don't:
- **Don't** 用 Three.js/WebGL 场景或粒子海洋——这是仪表墙，不是风景。
- **Don't** 发明流量或演示数据；包裹只来自真实 trace 路由，每条只回放一次，空闲就待机。
- **Don't** 在被动视图展示未遮蔽的邮箱——所有渲染字符串（含画布芯片文字）经 `mask()`。
- **Don't** 给与数据无关的元素加常驻动画；环境动画只有扫描微光、额度条流光与网关待机呼吸环。
