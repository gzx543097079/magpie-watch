# MAGPIE 观测台 · 续接文档

> 壁纸与桌宠最后核对：2026-10-23（下方旧模块记录保留原核对日期）
> 项目目录：`/Users/gengzhixiang/Desktop/桌面小组件/MagpieWatch`（2026-10-22 起全部项目内容集中在此子文件夹）  
> 当前版本：`1.0.0 (1)`

本文档面向后续开发者，记录当前实现边界、关键决策、接口约定、验证方法和建议的下一步。产品目标与设计原则见 [PRODUCT.md](PRODUCT.md)，用户安装说明见 [README.md](README.md)。

## 2026-10-24：壁纸改为数据中心式数据面板（当前）

- 壁纸不再有 token 流向动画。`design/starport.*` 与 Three.js 已从打包流程移除；`WallpaperWebScene` 加载同源页面 `dashboard.html`，页面经 `LocalOrigin` 反代 `/v1/magpie/*`。
- 版面：12 列网格。左 4 列整列是账号额度（`grid-row: 1 / -1`），右 8 列分三段 —— 今日（支出 / 缓存命中率 / DeepSeek 等价 / 最近三小时）、实时数据流（KPI、单次耗时竖条、模型与项目分布、最近路由明细）、智能体排行。行高 `26fr / 55fr / 19fr`。
- 额度列：无额度窗口的账号合并成末尾一行 `无额度窗口 N 个`，其余按服务商分组；整列不再溢出（`scrollHeight == clientHeight`）。
- 留白：`--dock-left` 让开 Dock，`--dock-right` 让开一列文件夹（偏好设置 0 / 120 / 150 / 200 / 260，默认 120），`--dock-bottom` 让开底部。全屏时三者归零，画面顶满左右。
- 全屏过渡：窗口层 `NSAnimationContext` 淡入 0.55 s easeOut、淡出 0.4 s easeIn；页面层 padding 0.72 s `cubic-bezier(0.22, 0.61, 0.36, 1)`，配合 `body.settling` 的 `settle` 关键帧（模块错峰 0.04–0.19 s）与顶边扫光。
- 本轮验证：`swift build -c release`、`swift test`（14 项）、`./build-app.sh` 打包签名通过；壁纸窗口 1920 × 1080 实拍核对版面与额度列不溢出。`node` 不在本机 PATH，`Tests/Web/*.mjs` 本轮未执行。
- 遗留：`WallpaperFlowScene` / `WallpaperRouteScene` / `WallpaperView` / `ScreensaverView` / `RouteVisuals` / `WallpaperDashboard` 已无引用，仍留在 target 内；`design/starport.*`、`design/three.min.js`、`Tests/Web/scene-regression*` 依赖的仍是旧场景。

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
| `Sources/MagpieWatch/WallpaperView.swift` | 桌面动态壁纸布局与 `AmbientOrbField` 环境光晕组件。主舞台是 `WallpaperRouteScene`。 |
| `Sources/MagpieWatch/WallpaperRouteScene.swift` | 多 agent 路由舞台：左侧智能体、中央 Magpie、右侧模型。真实 trace 才沿曲线播包；没有路由时节点等待、链路为虚线。 |
| `Sources/MagpieWatch/RouteVisuals.swift` | 小组件单路由 Canvas、曲线、粒子、节点和 Reduce Motion 处理。 |
| `Sources/MagpieWatch/PreferencesView.swift` | 偏好设置 UI。 |
| `Sources/MagpieWatch/Theme.swift` | 四套 `WatchPalette`、字体、玻璃面板、品牌标记、通用按钮。当前主题经 `\.watchPalette` 传给界面。 |
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
| `magpie.theme` | String | `aurora`（另有 `noir`、`ion`、`ember`） |

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
