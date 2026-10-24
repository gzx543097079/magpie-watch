# MAGPIE 观测台 · 续接文档

> 壁纸最后核对：2026-10-24（下方旧模块记录保留原核对日期）
> 项目目录：`/Users/gengzhixiang/Desktop/桌面小组件/MagpieWatch`（2026-10-22 起全部项目内容集中在此子文件夹）  
> 当前版本：`1.0.0 (1)`

本文档面向后续开发者，记录当前实现边界、关键决策、接口约定、验证方法和建议的下一步。产品目标与设计原则见 [PRODUCT.md](PRODUCT.md)，用户安装说明见 [README.md](README.md)。

## 2026-10-24：其余三模块数据升级（当前）

- 用户需求：优化链路舞台之外的模块，挖掘 Magpie 可取的数据。新接入 `/v1/magpie/quotas/history`（单独容错，拿不到只是少画曲线不算离线）。
- **账号额度**：每账号标题下一幅**燃尽曲线**（当前窗口内剩余额度的折线+填充，quotas/history 真实点位）；按当前窗口的真实下降速度推算**「估算 X 后用尽」**（小时速率 <0.5%/h 或重置先到则不估，注在对应窗口行）；模块页脚新增「最快燃尽 · 窗口 · 估算 X」（琥珀色）。原始已有的 <90min 琥珀重置预警保留。
- **今日**：「最近三小时」三行换成 **24 小时节奏柱状图**（尾部未到的小时裁掉，当前小时青色高亮，悬停看 次数/费用，标题行注峰值）；flow2 换入根级**首字**（ttft_ms/timed）与**生成速度**（decode_out/decode_ms，t/s），去掉 credits/计时两个弱读数。
- **智能体**：每行名下加**调用占比条**（宽度 = 调数 / 最活跃智能体）；副注追加「X 分钟前活跃」（以 trace 里该智能体最后一次触发时刻为准）。
- **最近调用明细带**（用户确认追加）：智能体模块底部新增两行请求账本明细（`/v1/magpie/usage/requests?period=today&limit=6`，单独容错），一行 = 时间·智能体·模型·输出 tok·耗时·费用，失败行标红、未计价标「未计价」、新行青光入场；智能体名过 `mask()`。行高从 24/60/16 调到 24/57/19 给明细带腾位。点击行星弹层的方案不可行——壁纸窗口鼠标完全穿透，无法接收点击。
- **屏保概览模式**（用户反馈「数据太混乱，屏保上一眼看到」）：`body.fullscreen`（屏保/全屏）时自动降噪——今日模块隐藏右栏（等价/流程/节奏图），只留大号今日支出（45→64px）、缓存率（24→32px）与四格（17→22px）；额度列隐藏燃尽曲线/副注/无窗口行，只留账号名 + 大号百分比（12→15px）+ 余量条；智能体只留名字 + 成本，隐藏副注/占比条/调用明细；星系段 57→61fr 且画布标注（行星标签 9.5→12.5px、恒星铭牌 10.5→13px）跟随放大。桌面态（非全屏）不受影响，仍是全量面板。
- **额度列状态分诊**（用户反馈「换一种一眼看出问题的方式」）：账号标题行挂**状态词**（用尽 > 紧张 ≤20% > 临近重置 <90min > 正常），账号前的 LED 圆点与状态词同步变色（红/红闪、琥珀、青）；每组最紧窗口的百分比加大为 15px 主读数，临近重置的窗口数字与余量条走琥珀。原「在岗/N 窗口」标记移除（活动状态由星系舞台表达）。
- **额度/今日模块重构**（用户反馈「重构额度模块，除 token 流动外都可重构，要酷炫清晰一目了然」）：
  - 额度改为**电源墙**：每账号一个大燃料计单元——状态灯 + 账号名 + 状态词（用尽/紧张/临近重置/正常）→ 6px 带刻度燃料条（25/50/75 刻度线 + 流光，颜色随状态蓝→琥珀→红）→ 主读数行（最紧窗口名 + 21px 大号剩余% + 重置倒计时）→ 一行小字收拢其余窗口（`7d 54%`）/估算用尽/占用。多窗口表格与燃尽曲线折线移除（估算逻辑保留）；用尽时大数字快闪、燃料条转暗红。
  - 今日改为**单列仪表组合**：一行「支出巨字(48px) + 缓存率(26px) + 生成速度/首字迷你表」，流程合为一行（输入/输出/缓存读/推理/失败/会话），五格读数（本周/30日/总tok/**等价**/每调用，DeepSeek 等价从右栏独占块并入），24h 节奏图收尾。双栏 today-side 与独立等价块移除。
  - 屏保概览模式同步适配：燃料条 8px、大号% 26px、迷你表隐藏。
- 本轮验证：真实数据截图核对（燃尽曲线下降形态、估算 3.7 小时、节奏图峰值 158 次 @13 时、占比条与活跃标注）；全屏概览与桌面全量两态截图确认；`impeccable detect` 无 error；`swift build` / `swift test` / `./build-app.sh` 通过。

## 2026-10-24：链路舞台按触发出场 + 常驻 3D 网关核心

- 用户需求：智能体/模型只在触发时出现，30 秒没有继续触发就消失；网关自己做呼吸动画，被调用时也要保持酷炫的 3D 效果。
- 节点存在性改为 TTL 语义：活动时刻 = 路由开始 +（已完成的）耗时，最近 30 秒内有活动（或仍有在途行程）才在舞台登记；30 秒无活动走 600ms 淡出。回放与补播同样只认 30 秒内有活动的路由（长请求按完整生命周期算）。
- 3D 网关核心常驻（`drawGatewayCore`）：科幻能量核——经纬线框球（6+3，倾斜投影 -0.38rad，z 深度决定透明度与线宽）+ 双陀螺环（两条不同倾角大圆轨道）+ 26 颗环绕粒子（各自倾斜轨道、带拖尾，少量冰蓝）+ 纬度能量波（亮环周期性从赤道向两极扫）+ 中心发光核 + 过境光刺（包裹穿过时 8 根短芒放射）。网关芯片叠在球心。
- 两个状态：**待机呼吸态**慢速环绕 + 半径 ±7% 呼吸 + 声呐环；**运转态**能量 = 0.3 + 0.25×(在途+停泊, ≤3) + 弹跳——粒子数量 8→26、角速度 ×5、线宽亮度与辉光提升、能量波更频繁（2.4s→1.1s）。旋转与粒子都走 `routeCorePhase` 相位累积器（dt 推进），能量变化是平滑加速而非跳变；包裹穿网关时 `routeCoreKick` 弹跳（0.90/帧衰减）。Reduce Motion 下静态慢速。
- 特效终极版（用户追加：还要更酷炫）：舞台发光层统一 `globalCompositeOperation = 'lighter'` 加性混光（光是叠出来的，芯片面板回到 source-over 保证可读）；核心加**吸积盘**（130 颗粒子同倾斜平面、开普勒速度内快外慢、黄金角分布，运转时 55→130 颗）；链路虚线按方向流动（agent 侧流向网关、model 侧流出，`lineDashOffset` 时间驱动），活跃链路垫 4.5px 辉光底；芯片入场走**全息光柱**（竖直渐变光向上射出、随淡入散去）+ 常驻底座椭圆光垫；背景 42 颗星尘缓慢漂移闪烁；彗星头部加十字耀斑（沿运动方向 + 垂直向）。
- 全流程特效（用户追加：整个流程都要酷炫，不只待机）：彗星本体升级为**宽辉光尾流**（沿路径铺 3.4× 宽淡光，尾迹比彗尾更长）+ 头部两颗**环绕电火花** + 飞行中随机**喷出尾焰粒子**；**每一站都有事件特效**——进网关：涟漪 + 4 颗火花 + 球体弹跳；**命中模型**：冲击波涟漪 + 10 颗火花迸射（请求程的最大爆点）；出网关：涟漪 + 火花 + 球体弹跳；**落地智能体**：8 颗火花绽开 + 收敛环。在途等待的包裹加两颗**电子环绕**（椭圆轨道）。火花是状态无关瞬态粒子（位置 = 原点 + 速度×时长，上限 150 颗），在加性混光层渲染。
- 星系化（用户追加：星空效果——中间恒星，两侧星球）：拓扑从「左列芯片 - 中央网关芯片 - 右列芯片」改为**星系**——中央恒星（网关溶入恒星本体，3D 核/吸积盘/能量波就是恒星外观，下方只留「MAGPIE 网关 / 今日 N · 在途 N」铭牌），智能体与模型是两侧**椭圆轨道上的行星**：每颗行星一条淡虚线轨道弧，行星本体是亮面朝恒星、暗面沉夜的球体（径向渐变）+ 大气辉光 + 活跃临边光弧，名称与读数标在行星下方，半径随调用量增长、入场从 30% 缩放物质化；行星沿轨道缓慢漂移（±0.055rad，4.2s 周期），彗星/涟漪/火花全部跟随行星实时坐标。链路改为**引力束**：活跃行星与恒星之间一道流动光束（宽辉光垫底 + 流动虚线），空闲时只有轨道不见束。
- 行星渲染精修（用户反馈「旁边的星星太丑了」）：球体改为**新月式光照**——深空底色暗球 + 晨昏线（恒星一侧的光扫进球内，裁剪在球内）+ 朝恒星一侧发亮的临边弧（带辉光）；大气辉光从色饼改为向外扩散的渐变光晕（加性）；约 1/3 的行星带**斜光环**（后半环 → 球体 → 前半环穿插，名称哈希决定，稳定）；半径 8–14px 随调用量增长；标注收紧（名称 9.5px、读数 8px 淡一档）。
- 已知平台行为不变：隐藏标签页 rAF 节流会让预览静止，真实壁纸窗口不受影响。
- 本轮验证：真实流量连拍——彗星沿引力束从行星飞向恒星、命中模型行星时冲击波+火花在行星边缘迸开、行星临边光弧点亮。

## 2026-10-24：实时链路升格为主视觉，移除实时数据流

- 用户需求：去掉实时数据流模块；token 流动模块做得更酷炫；没有触发的智能体和模型时网关自己做呼吸动画。
- 右栏回到三段（24/60/16fr）：今日 / 实时链路（约 60% 高度的主视觉）/ 智能体。实时数据流的 KPI、耗时示波器、分布、路由明细整块移除（HTML/CSS/JS 一并清掉，含 lt-row 扫光与 breath keyframes）；关键读数吸收进链路页脚——「在途 N · 中位 Xs · 失败 Y」。新路由到达时的机柜角标 blip 从 STREAM 迁到 LIVE.ROUTE。
- 舞台升级：① 网关待机声呐——空闲（无行程且无在途）时两层青色声呐环从网关向外扩散（2.6s 周期），叠加网关底光呼吸（径向渐变 0.10–0.16 透明度脉动），忙碌时底光恒定微光；循环以待机呼吸档 24fps 保持运转，Reduce Motion 下静态。② 包裹进出网关时在网关边缘激起涟漪（520ms 扩散环，请求程/回程颜色跟随）。③ 彗星加一圈 2.8 倍宽的柔光描边，体积感更强；网关芯片在包裹过境/停泊/在途时点亮。
- 已知平台行为：隐藏的 WKWebView/标签页里 rAF 会被节流暂停（预览浏览器里验证过），画面表现为静止；真实壁纸窗口在桌面属于可见窗口，显示链正常。画布单帧异常用 try/catch 兜底（console.warn），不让显示链停摆。
- 本轮验证：真实流量连拍覆盖请求程/回程/落地闪；待机两帧确认声呐环半径推进与页脚「网关待机 · 中位 X · 最近 60 条」；`impeccable detect` 无 error；`swift build` / `swift test` / `./build-app.sh` 通过。

## 2026-10-24：新增「实时链路 LIVE.ROUTE」往返舞台

- 用户追加需求：展示 token 流向——Agent → 网关 → 大模型，回复原路返回。实现为右栏第二段的新机柜（`LIVE.ROUTE`），右栏从三段变四段（24/25/35/16fr），今日与实时数据流相应压缩。
- 舞台是单画布：左列智能体芯片（≤3）、中央 MAGPIE 网关芯片、右列模型芯片（≤3），节点全部来自最近 60 条真实 trace 路由；虚线 S 形贝塞尔链路。
- 节点生命周期（用户追加：Agent 与模型会触发、会增减）：登记表驱动——活跃行程的端点优先占位，其余按最近活跃补足；新节点 500ms 淡入、离开的节点 600ms 原地淡出、在册节点位置按稳定序缓动重排（避免每次轮询跳位）；行程彗星的端点坐标取节点当前位置，重排时彗星跟着走。登记表只在过渡期让主循环保持运转，静止即停帧。
- 每条真实路由回放一次「包裹」：请求程（青 `#6ff2ff`）agent→gw→model；快照 `done === false` 时停在模型处脉冲；后续快照确认完成后放行回程（冰蓝 `#9fd1ff`，失败红 `#ff7a7a`），粗细按 log(token 体量) 1.4–3.6px。`routeSpent` 墓碑集保证同一路由只播一次（上限 300，被 7 条上限挤出的也进墓碑，不重播）；首帧只回放最新 3 条，历史不补播。
- 空闲（无行程且无在途）不伪造流量：链路虚线、网关待机呼吸环（CSS 叠层 `.gw-ring`，仅 idle 类时显示）。页脚常驻诚实标注「快照回放 · 4 秒轮询 · 非逐 token 观测」。画布芯片文字同样过 `mask()`。
- 帧率门控：有移动包裹 30fps、只剩停泊 8fps、落地闪（600ms 收敛环）放完即停帧；`prefers-reduced-motion` 下完全不播包，只画静态拓扑。
- 已知取舍（finish review 提出的可选项，未实施）：链路时长是常数（700/800/1100ms），未按真实 `r.ms` 缩放；活跃芯片用描边辉光而非四角角标。留给后续迭代。
- 本轮验证：真实 curl 请求穿过网关的连拍截图核对请求程/停泊/回程/落地闪四阶段；`swift build` / `swift test` / `./build-app.sh` 通过。

## 2026-10-24：壁纸改为数据中心 NOC 风

- 视觉世界替换：巡检站的「平静报表」语言换成数据中心指挥舱（NOC）。深空海军地 `#020912` + 蓝图双层网格（36px/180px）+ 30s 循环横向扫描微光；每模块一个 HUD 机柜（1px 发丝框 + 四角青色角标 `--tick-c` + LED 标题行 + mono 模块代号 ACC.QUOTA / TODAY / LIVE.STREAM / AGENTS）。所有数字读数改等宽字体（ui-monospace）。
- 光只表达真实状态：新路由落表时该行 0.95s 窄青光扫过、STREAM 机柜角标 blip 提亮；有失败时 STREAM 的 LED、角标、失败 KPI、模型分布条全部转红；余量 ≤20% 红色慢闪、用尽快闪、重置 <90 分钟琥珀（红优先）；数值变化时读数辉光短闪（`.tick`）；在途路由耗时格 1.6s 呼吸；离线时全板角标转红、画面压暗、扫描暂停。
- 常驻动画收紧到两类：扫描微光（body::after，transform 合成）与额度条流光（`.q .track i::after`）。头部/模块 LED 一律常亮不呼吸（响应审查发现的 pulsing-dot error）。`prefers-reduced-motion` 仍然一刀切停所有动画。
- 实时数据流模块重排：KPI 通栏 → 耗时示波器跨两行（新增三条淡刻度线 + canvas 辉光）→ 模型/项目分布贴右列 → 路由明细表通栏（能多显示几行）。
- 布局节奏微调：列间距 40→26px、新增行距 18px、机柜内边距 9/16/11px、`--dim2` 提亮到 `#63829f`（对比度 ≥4.5:1）。
- 顺带修复一个存量隐患：`mask()` 之前从未被调用，「邮箱已遮蔽」是空承诺；现在额度账号名 / plan / 无窗口账号名单 / 路由智能体名 / 智能体排行名渲染时都过 `mask()`。
- 设计文档：DESIGN.md 按 built world 重写（数据中心 NOC），新增 `.impeccable/design.json` sidecar；PRODUCT.md 品牌承诺改为「NOC 大屏、光=状态」；surface brief（`.impeccable/surfaces/design-dashboard-html.md`）写入新方向契约。验证截图：`.impeccable/review/desktop.png` 与 `desktop-fullscreen.png`（1920×1080 实数据）。
- 本轮验证：独立 finish review（fix → 三项修复 → 回验）；`detect` 无 error；swift build / test / build-app.sh 通过。

## 2026-10-24：移除桌宠、视觉主题与「预览 Token 流向」

- 桌宠整块删除：`PetWindowController`、`PetDetailWindowController`、`PetSkin`、`PetActivityTracker`、`design/pet.*`、`Resources/Pets/`（含 WhaleMusume 与许可）、菜单栏「桌宠」子菜单、偏好设置里的开关与装扮选择、`--pet-details` 与 `--wallpaper-demo` 启动参数。`Tests/MagpieWatchTests/PetActivityTests.swift` 与 `Tests/Web/pet-regression.mjs` 一并删除。
- 视觉主题删除：`WatchThemeID` 与四套配色收敛成单一 `WatchPalette.watch`（沿用原「极光暮色」值）。菜单栏「视觉主题」子菜单、偏好设置色板、`magpie.theme` 键、各视图里 `model.theme` 的 `.environment`/`.animation` 全部去掉。
- 「预览 Token 流向」删除：`AppModel.wallpaperPreview`、菜单栏与偏好设置开关、`setMagpieConfig` 的 `preview` 字段、`--wallpaper-demo`。`dashboard.js` 里对应的「演示数据」页脚分支也一并去掉。
- 顺带清掉长期无引用的旧舞台：`WallpaperRouteScene`、`WallpaperFlowScene`、`WallpaperView`、`ScreensaverView`、`RouteVisuals`、`WallpaperDashboard`、`WallpaperBoardTests`、`design/starport.*`、`design/three.min.js`、`Tests/Web/scene-regression*`。屏保仍是同一块数据面板。
- `ConsumptionWindowController`（原在 `PetDetailWindowController.swift` 里）拆成独立文件，菜单栏「Token 消耗明细…」与 ⌘T 不变。
- 本轮验证：`swift build -c release` 通过，`swift test` 5 项通过，`./build-app.sh` 打包签名通过。

## 2026-10-24：壁纸改为数据中心式数据面板

- 壁纸不再有 token 流向动画。`design/starport.*` 与 Three.js 已从打包流程移除；`WallpaperWebScene` 加载同源页面 `dashboard.html`，页面经 `LocalOrigin` 反代 `/v1/magpie/*`。
- 版面：12 列网格。左 4 列整列是账号额度（`grid-row: 1 / -1`），右 8 列分三段 —— 今日（支出 / 缓存命中率 / DeepSeek 等价 / 最近三小时）、实时数据流（KPI、单次耗时竖条、模型与项目分布、最近路由明细）、智能体排行。行高 `26fr / 55fr / 19fr`。
- 额度列：无额度窗口的账号合并成末尾一行 `无额度窗口 N 个`，其余按服务商分组；整列不再溢出（`scrollHeight == clientHeight`）。
- 留白：`--dock-left` 让开 Dock，`--dock-right` 让开一列文件夹（偏好设置 0 / 120 / 150 / 200 / 260，默认 120），`--dock-bottom` 让开底部。全屏时三者归零，画面顶满左右。
- 全屏过渡：窗口层 `NSAnimationContext` 淡入 0.55 s easeOut、淡出 0.4 s easeIn；页面层 padding 0.72 s `cubic-bezier(0.22, 0.61, 0.36, 1)`，配合 `body.settling` 的 `settle` 关键帧（模块错峰 0.04–0.19 s）与顶边扫光。
- 本轮验证：`swift build -c release`、`swift test`（14 项）、`./build-app.sh` 打包签名通过；壁纸窗口 1920 × 1080 实拍核对版面与额度列不溢出。
- 遗留：旧舞台文件当时仍留在 target 内，已在本轮（2026-10-24 移除桌宠与主题）一并删除。

## 2026-10-23：数据直接展示在桌面

- 账号余额 / 剩余额度、缓存命中率、今日输入 / 缓存 / 输出固定在壁纸顶部；最近三次调用的用途、来源、结算状态和用量显示在桌面底部。
- 桌宠工作台只有装扮和动作。Token 明细由菜单栏独立入口打开（⌘T、`--token-details`），不再归属于桌宠。
- 隐藏桌宠不影响桌面统计和请求账本刷新。上下文主项只作为归属线索，不当作单项操作账单。
- 本轮验证：12 项 Swift 测试、场景 JavaScript 回归、release 打包与签名校验通过。1920 × 1080 原生壁纸实拍见 `screenshots/desktop-telemetry-live.png`（本机真实数据，非演示）。
- 原生验证：底部按钮打开装扮页、动作页切换、睡衣选择及重启后保留、恢复原装扮；⌘T 在应用获得焦点时打开独立 Token 明细，成功选择已完成请求并展开 `js / exec_command / write_stdin / apply_patch` 返回占用。关闭两个详情窗口后，壁纸与桌宠继续运行。
- 尚未验证：多显示器插拔、长期耗电。当前请求刷新约 4 秒；货币余额仅在数据源实际提供时展示。

## 2026-10-23：鲸鱼娘原版、独立工作台与桌面统计

- 原版资源、MIT 核心与许可固定在 `Resources/Pets/WhaleMusume`，版本和 SHA-256 见 manifest。历史生成 PNG 保留但不打包。
- `PetWindowController` 现在为 246 × 316，单击互动、拖动移动、双击或底部按钮打开 `PetDetailWindowController`。装扮与动作不再依赖二级悬停菜单。菜单栏菜单在 tracking 期间不重建。
- `ConsumptionModels` 解码 trace 的 `kind/folder/prompt.parts[].items[]` 和 `/v1/magpie/usage/requests?period=today&limit=100`。账本通过 `route_id` 与路由合并，账本用量优先；缺失值不变成 0。壁纸启用或独立消耗分析窗口可见时轮询账本，完全不依赖桌宠。
- 只使用结构名称和计数，不读取对话正文。文件/工具项是本次上下文构成，可能含历史返回；不能称为单次工具的独立账单。输出内推理不再额外相加。
- `DesktopAccountSummary` 将额度、遮蔽账号传给壁纸顶部统计。当前 Magpie 0.1.1300 返回三个订阅账号的周期剩余百分比，没有货币余额。新输入、缓存读取、输出、缓存命中率独立展示。旧快照显式标记。
- 测试新增消费归属、账本去重、未知值、原版桌宠动作优先级、预览隔离、静态/减少动态效果与统计 DOM 文本安全。

以下为此前阶段记录，旧宠物素材和尺寸以本节为准。

## 2026-10-23：星潮壁纸与独立桌宠

最新需求优先实现「动态壁纸 + 可移动宠物」，技术不限。已使用 AppKit 桌面窗口 + 本地 WKWebView/Three.js，不再把壁纸中的 SVG 当作可交互宠物。

- `design/starport.{html,css,js}`：吸积盘 shader、星尘、青色输入 / 金色回流、请求光带与错误返回。`WallpaperWebScene.swift` 将本次输入/输出 token、今日统计和明确的 preview 标志传入。
- `PetWindowController.swift`：独立透明 `NSPanel`，原生拖动与右键菜单，持久化屏内位置和形象；不依赖壁纸开关。`design/pet.html` + `Resources/Pets/*.png` 实现三种插画悬浮动效，素材完整提示见 `SOURCES.md`。
- `WallpaperBoardBuilder` 保留同一智能体的多条并发请求。
- 新安装默认打开壁纸和桌宠、关闭小组件和自动屏保；已有偏好继续保存。`--wallpaper-demo` 仅用于明确标注的示例流量。
- 网关约 4 秒轮询，光流表示 trace 事件，不能声称逐 token 流式观测。未知计量显示「待计量」；离线清空流光。粒子数量有上限，30 fps、DPR 最高 1.5，支持 Reduce Motion。

本轮验证：release 构建与 ad-hoc 签名通过；4 项 Swift 数据测试；JavaScript 场景逻辑回归覆盖并发、双向移动、完成去重、离线、演示隔离与 Reduce Motion。原生应用实测三种换肤、拖动、重启后形象/位置恢复、壁纸开关与演示入口。新的壁纸展示截图为 `screenshots/star-tide-preview.png`（演示数据）。未声称完成多显示器插拔或长期耗电测试。

## 1. 当前完成状态

应用已经可以构建、打包并在本机运行。当前实现的核心能力：

- 原生 macOS 菜单栏应用，`LSUIElement=true`，不占用 Dock。
- 桌面浮动小组件，展开尺寸 `430 × 640`，紧凑尺寸 `294 × 166`。
- 从 `127.0.0.1:3425` 读取 Magpie 服务信息、今日用量、额度与路由追踪。
- 今日请求、费用、缓存命中、输入/输出令牌、生成速度、错误、重试、延迟等指标。
- `智能体 → Magpie 网关 → 候选服务商 / 账号` 的 Canvas 动画。
- 偏好设置：显示/隐藏小组件、始终置顶、鼠标穿透、自动屏保、等待时间、邮箱遮蔽。
- 应用内全屏动态屏保：所有显示器覆盖、任意输入退出、阻止空闲睡眠和显示睡眠。
- 桌面动态壁纸：常驻在系统壁纸之上、桌面图标之下，逐屏一个透明窗口，鼠标事件完全穿透，可在菜单栏、偏好设置或 `--wallpaper` 启动参数开启。
- 面板位置恢复与越界重置。
- 安全的开发启动参数：`--expanded`、`--compact`、`--preferences`、`--screensaver`、`--wallpaper`。
- release 构建、`.app` 组装、Info.plist 校验和 ad-hoc 签名。

已验证：

```bash
swift build
./build-app.sh
plutil -lint Info.plist
codesign --verify --deep --strict 'dist/Magpie Watch.app'
```

打包产物：

```text
dist/Magpie Watch.app
```

Magpie 本机版本与接口在 2026-10-22 核对过：Magpie `0.1.1319`，安装于 `/Applications/magpie.app`，bundle id 为 `com.yetone.magpie`。

## 2. 必须保留的产品边界

### 2.1 不是系统 `.saver`

当前屏保由应用进程创建 `NSWindow`，层级为 `.screenSaver`，覆盖每块屏幕。这不是 macOS 系统设置中可选择、并由系统 `legacyScreenSaver` 进程加载的 `.saver` bundle。

因此：

- 可以通过菜单栏、小组件按钮或应用内空闲检测触发。
- 系统锁屏、登录窗口或系统真正休眠后，不能保证继续展示。
- 退出应用后，自动屏保不再工作。
- 不应在文档、发布说明或界面文案中宣称它是系统原生屏保。

若后续要做系统级屏保，应单独增加 ScreenSaver `.saver` target，并处理沙盒、进程间数据共享、密码输入界面、系统版本兼容和签名分发。

### 2.2 数据只来自本机

应用只访问 `http://127.0.0.1:3425`。没有云端账号、遥测、截图、OCR 或远程同步。不要把接口改成公网地址，也不要把账号信息写入日志。

### 2.3 图标与品牌

`build-app.sh` 当前从 `/Applications/magpie.app/Contents/Resources/magpie.icns` 复制图标。这只适合本机个人使用。公开发布前应替换为自有图标，并明确非官方关系与素材授权。

## 3. 架构总览

```text
NSApplication
  └─ AppDelegate
      ├─ AppModel
      │   ├─ MagpieAPI ── HTTP ── 127.0.0.1:3425
      │   ├─ UserDefaults
      │   └─ RoutePresentation / QuotaHighlight
      ├─ WidgetWindowController
      │   └─ WidgetView
      │       └─ RouteNetworkView
      ├─ ScreensaverWindowController
      │   └─ ScreensaverView
      │       └─ RouteNetworkView
      ├─ NSStatusItem / NSMenu
      └─ PreferencesView
```

线程模型：`AppModel`、`AppDelegate`、窗口控制器均为 `@MainActor`。网络请求通过 `async/await` 发出，结果回到主 actor 后更新 `@Published` 状态。

## 4. 文件职责

| 文件 | 职责 |
| --- | --- |
| `Sources/MagpieWatch/main.swift` | 创建 `NSApplication`，安装 `AppDelegate`，设置为 accessory 应用并进入事件循环。 |
| `Sources/MagpieWatch/AppDelegate.swift` | 菜单栏、菜单动作、启动参数、空闲监控、屏保触发和偏好窗口生命周期。 |
| `Sources/MagpieWatch/AppModel.swift` | 4 秒轮询、在线状态、错误状态、路由选择、额度摘要、设置持久化。小组件继续用单路由 `routePresentation`；壁纸和屏保用 `wallpaperBoard`。 |
| `Sources/MagpieWatch/MagpieAPI.swift` | HTTP 客户端、超时、状态码检查、JSON 解码。 |
| `Sources/MagpieWatch/Models.swift` | Magpie API 解码模型和视图展示模型。 |
| `Sources/MagpieWatch/PanelControllers.swift` | `FloatingPanel`、小组件窗口、屏保全屏窗口与输入退出监听。 |
| `Sources/MagpieWatch/WidgetView.swift` | 展开和紧凑两种小组件布局。 |
| `Sources/MagpieWatch/ScreensaverView.swift` | 全屏屏保布局、头部、指标、底部状态和退出提示。 |
| `Sources/MagpieWatch/TokenFlowView.swift` | 小组件上的 Token 流向光带：缓存 / 输入分行交织，输出反向回流。壁纸和屏保不再用它当主舞台。 |
| `Sources/MagpieWatch/RouteVisuals.swift` | 小组件单路由 Canvas、曲线、粒子、节点和 Reduce Motion 处理。 |
| `Sources/MagpieWatch/PreferencesView.swift` | 偏好设置 UI。 |
| `Sources/MagpieWatch/Theme.swift` | 单一 `WatchPalette.watch`、字体、玻璃面板、品牌标记、通用按钮。 |
| `Sources/MagpieWatch/Formatting.swift` | 数字缩写、货币、百分比、延迟、日期和账号遮蔽。 |
| `Sources/MagpieWatch/UsageSparkline.swift` | 今日用量折线图和柱状信号图。 |
| `Package.swift` | SwiftPM 可执行 target，最低 macOS 14。 |
| `Info.plist` | LSUIElement、本地网络、版本和 bundle 元数据。 |
| `build-app.sh` | release 构建、组装 `.app`、复制图标、校验和 ad-hoc 签名。 |

## 5. 启动与生命周期

`main.swift` 创建共享的 `NSApplication`，设置 `.accessory` 激活策略，然后调用 `run()`。`applicationDidFinishLaunching` 中依次完成：

1. 创建小组件和屏保窗口控制器。
2. 配置菜单栏。
3. 绑定设置和刷新状态。
4. 启动 `AppModel` 轮询。
5. 根据持久化设置显示小组件并检查是否在屏幕内。
6. 启动 5 秒周期的空闲检测 Timer。
7. 应用启动参数。

`--screensaver` 和 `--preferences` 会异步触发，让窗口先完成应用初始化。`--compact` 与 `--expanded` 仅在启动时覆盖持久化的展开状态。

## 6. 数据流与刷新行为

`AppModel.start()` 只允许启动一次轮询任务。每一轮并行请求：

```text
GET /                         -> ServiceInfo
GET /v1/magpie/usage?period=today -> UsageResponse
GET /v1/magpie/quotas         -> QuotasResponse
GET /v1/magpie/trace?after=0  -> TraceResponse
```

每个请求独立使用 `try?`，因此一个接口失败不会清空其他接口已经拿到的有效数据。只要任意一个接口成功，当前轮次就视为在线，并刷新 `lastUpdated` 和 `refreshGeneration`；全部失败才设置离线错误。

失败时保留上一次成功数据，但 `isOnline` 会变为 `false`。这使离线时仍能看到旧快照，同时头部和状态标签会明确显示离线。接入新接口时需要保持这个“分接口成功、整体汇总”的模式。

`refresh()` 有 `isRefreshing` 防重入保护，菜单栏刷新和界面刷新可以并发调用而不会叠加请求。

## 7. 路由展示规则

`AppModel.routePresentation` 是视图的主要数据源：

- 选择 `trace.routes` 中 `id` 最大的路由作为最新路由。
- 当前选中节点优先取 `route.tries.last.id`，否则取 `route.order.first.id`。
- 路由时间在 120 秒内且网关在线时标记为 live。
- `order` 最多展示 4 个候选，每个候选显示 provider、账号、套餐、额度百分比和当前/候补状态。
- 没有 trace 时退化为 quota 候选，并显示“等待下一次请求”或“网关离线”。
- 账号展示统一经过 `Fmt.maskAccount`，默认遮蔽。

`RouteNetworkView` 只在紧凑模式展示当前节点，展开模式最多 3 个节点，沉浸式屏保最多 4 个节点。`accessibilityReduceMotion` 为真时，粒子动画会停用，静态结构仍保留。

## 8. API 与模型约定

解码器使用 `convertFromSnakeCase`。Magpie 字段新增时，在 `Models.swift` 中增加可选字段，避免解码整个响应因缺少字段而失败。

当前关键端点：

| 端点 | 关键字段 | 用法 |
| --- | --- | --- |
| `GET /` | `name`, `version`, `pid`, `models`, `serves`, `window` | 在线状态和网关版本。 |
| `GET /v1/magpie/usage?period=today` | `calls`, `cost`, `input`, `output`, `cache_read`, `errors`, `retried`, `series`, `agents`, `models` | 小组件、趋势和最近活动。 |
| `GET /v1/magpie/quotas` | `provider`, `name`, `user`, `windows`, `last` | 额度压力和账号选择。 |
| `GET /v1/magpie/trace?after=0` | `routes`, `order`, `tries`, `totals` | 路由动画和请求统计。 |

请求参数：

- `usage` 的 `period` 当前固定为 `today`；模型层已支持字符串，但 UI 尚未提供 7 天、30 天和全量切换。
- `trace` 的 `after` 当前固定为 `0`，每轮重新获取快照；如果 Magpie 返回数据变大，应改为基于 `seq` 的增量游标。
- 请求超时为 4 秒，使用忽略缓存策略，`Accept: application/json`。
- 非 2xx 会抛出 `MagpieAPIError.server`；JSON 解码失败会抛出带上下文的 `decode` 错误。

### 增加新 API 的步骤

1. 在 `MagpieAPI` 增加返回 `Decodable` 类型的方法。
2. 在 `Models.swift` 增加可选字段和视图需要的派生模型。
3. 在 `AppModel.refresh()` 的 `async let` 组中并行请求，并保留旧快照策略。
4. 将展示映射集中到 `routePresentation` 或 `quotaHighlights`，不要在 View 中直接解析原始 JSON。
5. 补充在线/离线/空数据三种状态的 UI 验证。

## 9. 窗口与屏保实现

### 小组件窗口

`FloatingPanel` 是无边框、非激活型 `NSPanel`，允许背景拖动，可加入所有 Space，并作为全屏辅助窗口显示。设置同步会更新：

- `isPinned` → `.floating` 或 `.normal`
- `clickThrough` → `ignoresMouseEvents`
- `isWidgetVisible` → `orderFrontRegardless()` 或 `orderOut(nil)`
- `widgetExpanded` → 尺寸和边界约束

尺寸变化时保持窗口顶部位置，并通过可见屏幕区域夹取，避免小组件被推到屏幕外。启动时调用 `ensureOnScreen()`，如果当前帧不与任何屏幕相交则重置到主屏右上角。

### 屏保窗口

`ScreensaverWindowController.show(model:)` 对 `NSScreen.screens` 逐一创建无边框窗口：

- `level = .screenSaver`
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`
- 每块屏幕一个 `ScreensaverView`
- `ProcessInfo.beginActivity` 禁止空闲系统睡眠和显示睡眠

输入退出同时使用本地和全局事件监听：

- 本地：键按下、鼠标按下、滚动、鼠标移动。
- 全局：鼠标移动、鼠标按下、键盘按下。
- `dismissOnce()` 防止一次退出事件被多个监听器重复处理。
- `hide()` 释放 activity 和所有事件监听器，并关闭全部窗口。

### 空闲检测

`AppDelegate` 每 5 秒通过 `CGEventSource.secondsSinceLastEventType` 读取鼠标、点击、滚动和键盘事件的最小空闲时间。触发条件：

- `autoScreensaver == true`
- 当前没有屏保窗口
- 已过启动后的 30 秒抑制期
- 距离上次屏保展示超过 5 秒，避免退出后立刻重入
- 空闲时间达到 `idleMinutes * 60`

## 10. 设置持久化

`AppModel` 使用 `UserDefaults.standard`，键名如下：

| 键 | 类型 | 默认值 |
| --- | --- | --- |
| `magpie.widget.expanded` | Bool | `true` |
| `magpie.widget.visible` | Bool | `false`（2026-10-22 起默认隐藏，桌面主展示位让给动态壁纸） |
| `magpie.widget.pinned` | Bool | `true` |
| `magpie.widget.clickThrough` | Bool | `false` |
| `magpie.screensaver.auto` | Bool | `true` |
| `magpie.screensaver.idleMinutes` | Int | `5` |
| `magpie.privacy.maskEmails` | Bool | `true` |
| `magpie.wallpaper.enabled` | Bool | `false` |
| `magpie.wallpaper.rightInset` | Int | `120` |

新增设置时要同时处理默认值、`didSet` 持久化和 Preferences UI 绑定。修改键名会清空用户现有偏好，应提供迁移逻辑而不是直接改名。

## 11. 构建、运行和验证

### 构建

```bash
swift build
```

### 打包

```bash
./build-app.sh
```

注意：如果 `dist/Magpie Watch.app` 正在运行，先退出应用再重建，避免运行中的旧二进制和新 bundle 混用。

### 校验

```bash
plutil -lint Info.plist
codesign --verify --deep --strict 'dist/Magpie Watch.app'
```

如需查看签名信息：

```bash
codesign -dv --verbose=2 'dist/Magpie Watch.app'
```

### 本地 API 验证

```bash
curl -sS http://127.0.0.1:3425/
curl -sS 'http://127.0.0.1:3425/v1/magpie/usage?period=today'
curl -sS http://127.0.0.1:3425/v1/magpie/quotas
curl -sS 'http://127.0.0.1:3425/v1/magpie/trace?after=0'
```

若接口不可用：

```bash
lsof -nP -iTCP:3425 -sTCP:LISTEN
pgrep -fl magpie
```

### 手工回归清单

每次修改 UI、窗口层级或网络层后至少检查：

- 菜单栏图标出现，菜单标题和计数会随数据刷新。
- 展开/紧凑切换后尺寸正确，缩放不越界，节点不重叠。
- 关闭再显示小组件，设置仍然保留。
- 置顶和鼠标穿透切换能立即生效。
- 偏好窗口能在当前 Space 显示并可关闭重开。
- 手动屏保能覆盖所有显示器，鼠标、点击、键盘均能退出。
- 自动屏保在设定时间出现，退出后不会立即重入。
- Magpie 停止时显示离线，恢复后自动回到在线。
- 邮箱遮蔽开关对路由和额度区域同时生效。
- 切换四套视觉主题后，小组件、壁纸和屏保同时变色，重启后仍是上次的选择。

## 12. 当前限制与风险

1. **系统屏保缺口**：要支持系统设置和锁屏自动加载，需要新建 `.saver` target 和跨进程数据通道。
2. **端口不可配置**：`127.0.0.1:3425` 写死在 `MagpieAPI.init`。不同安装或代理端口会导致持续离线。
3. **接口无版本协商**：完全依赖 Magpie 当前 JSON 字段；Magpie 升级可能改变字段或把 `trace` 改成增量语义。新增字段应保持可选，并添加解码回归样本。
4. **全量 trace 轮询**：`after=0` 每 4 秒取一次全量快照，数据长期增长后可能增加内存、解码和绘制成本。可改为使用 `seq` 游标。
5. **轮询任务生命周期**：`deinit` 取消任务，但应用正常退出由 `NSApp.terminate` 结束；如果未来增加多窗口或重载逻辑，需要显式处理 task 取消和 actor 隔离。
6. **多显示器行为**：每块屏幕显示相同路由，没有按屏幕独立配置。屏幕热插拔时，下一次进入屏保会重新枚举，但屏保显示期间不会动态增删窗口。
7. **图标与分发**：当前使用 ad-hoc 签名和 Magpie 自带图标，只适合本机。公开分发需要自有图标、Developer ID、公证和许可证文件。
8. **没有自动化测试**：目前只有构建和人工 UI 回归，网络解码与路由选择没有 XCTest 覆盖。
9. **屏幕保护退出监听**：全局事件监听依赖辅助功能/输入监控权限的实际授权状态；不同 macOS 版本可能需要用户手动授权。若全局监听不可用，仍应保证窗口内本地事件可退出。

## 13. 建议的后续迭代

### 优先级 P1：稳定性与可维护性

- 将 Magpie 地址和端口加入偏好设置，默认 `127.0.0.1:3425`，并在连接失败时提示。
- 为 `Models.swift` 增加解码样本和 XCTest，覆盖字段缺失、空数组、额度窗口为空、trace 缺失等情况。
- 为 `AppModel` 的路由选择、账号匹配、额度排序提取纯函数并添加单元测试。
- 使用 `trace.seq` 做增量轮询，减少长时间运行时的负载。
- 将轮询间隔、超时和启动抑制时间抽成常量或设置项。
- 为屏保显示期间处理显示器热插拔，避免新增屏幕没有覆盖层。

### 优先级 P2：产品体验

- 在小组件内提供今日、7 天、30 天、全量切换；模型已支持 `period` 参数。
- 将额度、路由和请求历史拆成可折叠区块，适配更大字体与辅助功能。
- 增加“仅显示当前路由”或“显示所有候选”的密度设置。
- 为离线、空数据、额度耗尽和无路由增加更明确的空状态文案。
- 允许自定义屏保闲置时间、屏保是否阻止睡眠和多显示器策略。
- 增加键盘焦点顺序、VoiceOver 标签和 Reduce Motion 的完整回归。

### 优先级 P3：系统级屏保与分发

- 新建 ScreenSaver `.saver` target，通过共享容器、Unix domain socket 或本地 HTTP 读取同一份 Magpie 数据。
- 设计系统设置中的配置面板，并处理系统屏保进程无法直接访问主应用状态的问题。
- 替换 Magpie 图标为自有品牌图标，补充 `LICENSE`、`NOTICE` 和第三方素材说明。
- 使用 Developer ID 签名与 notarization，提供 `.dmg` 或 `.pkg` 安装流程。
- 为公开发布准备隐私说明、版本迁移和崩溃日志采集（不采集账号与路由内容）。

## 14. 续接时的第一组命令

```bash
cd '/Users/gengzhixiang/Desktop/桌面小组件/MagpieWatch'
swift --version
swift build
plutil -lint Info.plist
codesign --verify --deep --strict 'dist/Magpie Watch.app'
curl -sS http://127.0.0.1:3425/
```

启动当前应用：

```bash
open 'dist/Magpie Watch.app'
```

查看是否已有实例：

```bash
pgrep -fl MagpieWatch
```

如果要在改代码后重新打包，先退出旧实例，再运行：

```bash
./build-app.sh
open 'dist/Magpie Watch.app'
```

## 15. 变更记录

### 2026-10-23（壁纸改多 agent 舞台）

- 动态壁纸和屏保的主画面改为多 agent 路由编排，不再用 Token 光带占舞台。一眼可读的方向是：多个智能体 → Magpie 本地网关 → 请求模型 → 响应回流到智能体。
- 新增 `WallpaperRouteScene` / `WallpaperBoardBuilder`。节点来自 `usage.agents`（最多 4 个）和 `usage.models`（补足最多 4 个等待中的模型）。每个智能体只保留 90 秒内最新的一条非等待 trace。阶段：进入网关 1.4 秒内为 incoming，之后未完成为 outbound，完成后约 22 秒内为 returning，其余为 waiting。
- 包只在真实 trace 上播放。incoming 用主色沿智能体→网关移动，outbound 用输入色沿网关→模型移动，returning 用回流色反向走完两段。粒子数量按该跳 token 体量在 1–3 之间。没有路由时链路是虚线，节点标为等待。
- 同一模型被多个智能体同时使用时，描边取更活跃的阶段，每条真实 trace 仍各自播包。被数量上限挤掉的一端会回到等待，避免画出没有端点的包。
- Token 光带留在小组件。壁纸和屏保底部只用本段真实上/下行 token 做读数，不再铺全屏光带。四套主题、壁纸窗口层级、`--wallpaper` 和偏好开关保持不变。Reduce Motion 时粒子停止，结构和配色保留。

### 2026-10-23

- Token 流向改成电影感光带：缓存与输入分行交织，输出反向回流。厚度、彗星数量和流速绑定真实 token 体量与 tok/s；体量为 0 的车道不播放粒子。
- 当时壁纸使用 `ambient` 舞台，屏保使用 `cinematic` 舞台。这一版已被上面的多 agent 舞台替换；小组件仍使用紧凑和面板光带。沉浸式单路由视图只留在小组件。
- 新增四套可切换主题：极光暮色（`aurora`，原配色）、黑金夜宴（`noir`）、离子极昼（`ion`）、熔核（`ember`）。菜单栏「视觉主题」和偏好设置色板都会改 `magpie.theme`，小组件、壁纸、屏保一起生效。Reduce Motion 时粒子停止，配色和厚度仍保留。

### 2026-10-22（第四次）

- 「极光暮色」主题重构：近黑蓝紫底 + 青色主能量 + 紫罗兰氛围 + 琥珀输出，全局色板与玻璃面板换新。
- 新增 `TokenFlowView`：上行（缓存+输入，青/蓝）/下行（输出，琥珀）双通道 token 流动画，车道厚度与粒子密度按 log 体量缩放。
- token 流向与路由绑定：解码 `trace.routes[].usage`（`RouteUsage`），优先显示本次路由的真实 in/out/cache_read，无路由数据时回退今日累计并标注「今日累计」；标题显示路由模型名。
- `RouteNetworkView`：选中路由增加沿线流光短划与反向输出的琥珀粒子（密度随输出量变化），网关呼吸光晕改极光色。
- 小组件紧凑尺寸 294×166 → 294×196，加入紧凑版流向图；展开模式把流向图并入「实时路由」卡片。
- 小组件出厂默认改为不可见（`magpie.widget.visible` 默认 `false`），桌面主展示位让给动态壁纸；屏保与壁纸均加入 TokenFlowView。

### 2026-10-22（第三次）

- 新增桌面动态壁纸：`WallpaperWindowController`（`PanelControllers.swift`）为每块屏幕创建一个无边框透明窗口，层级取 `INT32_MIN + 35`，位于系统壁纸层（`INT32_MIN + 25`）与桌面图标层（`INT32_MIN + 45`）之间，`ignoresMouseEvents = true`，并监听屏幕参数变化重建。
- `WallpaperView` 提供半透明底色（壁纸颜色隐约透出）、实时路由动画、今日请求主数字、关键指标与底部状态条；`AmbientOrbField` 环境光晕供壁纸与屏保复用。
- 开关入口：菜单栏「显示/隐藏动态壁纸」（⌘D）、偏好设置「动态壁纸」分区块、`--wallpaper` 启动参数；设置键 `magpie.wallpaper.enabled`。
- 注意：Swift 中 `NSWindow.Level` 没有 `.desktop`/`.desktopIcon` 成员，`CGWindowLevelKey` 的成员也不可直接引用，层级只能用原始数值（来源见 SDK 的 `CGWindowLevel.h`）。

### 2026-10-22（第二次）

- 项目内容整体移入 `MagpieWatch/` 子文件夹，桌面根目录保持整洁；构建脚本与文档均使用相对路径，无需改动。
- UI 重构与美化：新增 `watchCard` 统一卡片样式（渐变底、发丝描边、顶部高光）、`WatchMotion` 动效常量、`Entrance` 分段入场动画和按钮悬停反馈。
- 用量折线图重写为平滑曲线，带辉光、渐变填充、从左到右的绘制动画和端点脉冲。
- 路由动画增强：粒子彗星拖尾、网关双环脉冲与呼吸光晕、沉浸模式环境星点。
- 屏保新增缓慢漂移的环境光晕层；偏好设置分区块套用统一卡片样式。
- 额度进度条增加动态填充动画与流光效果；关键数值使用 `numericText` 滚动过渡。

### 2026-10-22

- 完成 SwiftUI + AppKit 桌面小组件、菜单栏控制器和应用内动态屏保。
- 接入 Magpie 本机 usage、quota 和 trace 接口。
- 增加路由 Canvas 动画、紧凑布局、多显示器屏保、偏好设置与邮箱遮蔽。
- 完成 release 打包、Info.plist 校验和 ad-hoc 签名验证。
- 补充中文 README 与本文档。

## 2026-10-23 · 壁纸看板与活跃节点

- 壁纸使用 `AppModel.activeWallpaperBoard`（`WallpaperBoardBuilder.make(activeOnly: true)`），只显示此刻有真实路由的智能体与模型；节点在请求到达时带光柱入场，最后一条回流落地后淡出。
- 左侧看板：今日 Token、今日/本周/本月（由 `/usage?period=30d` 逐日序列按本地自然周/月求和，接口不支持 week/month）、今日效率（错误、重试、会话、费用、推理、平均首字、生成速度）、24 小时请求节奏。右侧：账号额度、智能体排行、模型排行（副标题邮箱按遮蔽设置处理）。数据结构见 `WallpaperDashboard.swift`。
- 每条链路是双车道着色器光带：青色输入流向模型，金色输出流回智能体，有请求时加速变亮。
- 本机无 Node 时用 JavaScriptCore 跑场景回归：`/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc Tests/Web/scene-regression-jsc.js`。
- 实拍：`screenshots/wallpaper-dashboard-live.png`。
