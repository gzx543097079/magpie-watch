import SwiftUI

struct WidgetView: View {
    @ObservedObject var model: AppModel
    var onOpenScreensaver: () -> Void
    var onOpenMagpie: () -> Void
    var onClose: () -> Void

    private var expandedSize: CGSize { CGSize(width: 430, height: 640) }
    private var compactSize: CGSize { CGSize(width: 294, height: 196) }

    var body: some View {
        ZStack {
            GlassPanel(cornerRadius: 26)

            if model.widgetExpanded {
                expanded
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            } else {
                compact
                    .transition(.opacity.combined(with: .scale(scale: 1.02, anchor: .top)))
            }
        }
        .frame(
            width: model.widgetExpanded ? expandedSize.width : compactSize.width,
            height: model.widgetExpanded ? expandedSize.height : compactSize.height
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: model.widgetExpanded)
    }

    private var expanded: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 17)
                .padding(.bottom, 13)

            Rectangle()
                .fill(Color.white.opacity(0.075))
                .frame(height: 0.5)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 13) {
                    usageHero
                        .entrance(index: 0)
                    routeSection
                        .entrance(index: 1)
                    quotaSection
                        .entrance(index: 2)
                    recentActivity
                        .entrance(index: 3)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }

            footer
        }
    }

    private var compact: some View {
        VStack(spacing: 11) {
            HStack(spacing: 9) {
                BrandMark(size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MAGPIE 观测台")
                        .font(.custom(WatchTheme.displayCNFont, size: 14).weight(.semibold))
                        .tracking(0.4)
                        .foregroundStyle(WatchTheme.ice)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(model.isOnline ? WatchTheme.seaBright : WatchTheme.coral)
                            .frame(width: 4, height: 4)
                        Text(model.isOnline ? "今日 \(Fmt.compact(model.todayCalls)) 次请求" : "网关离线")
                            .font(.custom(WatchTheme.monoFont, size: 7))
                            .foregroundStyle(WatchTheme.mist)
                    }
                }
                Spacer()
                IconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "展开小组件") {
                    model.widgetExpanded = true
                }
            }

            RouteNetworkView(route: model.routePresentation, compact: true)
                .frame(height: 74)

            TokenFlowView(route: model.routePresentation, compact: true)

            HStack {
                compactMetric("预估费用", Fmt.currency(model.usage?.cost), tint: WatchTheme.amber)
                compactMetric("缓存命中", Fmt.percent(model.cacheHitRate), tint: WatchTheme.seaBright)
                compactMetric("错误", "\(model.usage?.errors ?? 0)", tint: (model.usage?.errors ?? 0) > 0 ? WatchTheme.coral : WatchTheme.mist)
            }
        }
        .padding(15)
    }

    private func compactMetric(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.custom(WatchTheme.bodyFont, size: 6.5).weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(WatchTheme.mist)
            Text(value)
                .font(.custom(WatchTheme.monoFont, size: 10).weight(.medium))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            BrandMark(size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("MAGPIE 观测台")
                    .font(.custom(WatchTheme.displayCNFont, size: 18).weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(WatchTheme.ice)
                HStack(spacing: 6) {
                    LiveDot(
                        isLive: model.isOnline,
                        color: model.isOnline ? WatchTheme.seaBright : WatchTheme.coral
                    )
                    Text(model.isOnline ? "实时 · 127.0.0.1:3425" : "网关离线")
                        .font(.custom(WatchTheme.monoFont, size: 7.5))
                        .foregroundStyle(model.isOnline ? WatchTheme.mist : WatchTheme.coral)
                }
            }

            Spacer()

            IconButton(symbol: "arrow.down.right.and.arrow.up.left", help: "收起小组件") {
                model.widgetExpanded = false
            }
            IconButton(symbol: "arrow.clockwise", help: "立即刷新") {
                Task { await model.refresh() }
            }
            IconButton(symbol: "xmark", help: "隐藏小组件") {
                onClose()
            }
        }
    }

    private var usageHero: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("今日 / 本地网关")
                        .panelLabel()
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(model.todayCalls)")
                            .font(.custom(WatchTheme.displayFont, size: 52).weight(.medium))
                            .tracking(1)
                            .foregroundStyle(WatchTheme.ice)
                            .contentTransition(.numericText())
                            .animation(WatchMotion.data, value: model.todayCalls)
                        Text("次请求")
                            .font(.custom(WatchTheme.displayCNFont, size: 9).weight(.medium))
                            .tracking(0.4)
                            .foregroundStyle(WatchTheme.mist)
                    }
                    Text(model.isOnline ? "\(model.usage?.errors ?? 0) 次错误 · \(model.usage?.retried ?? 0) 次重试" : "Magpie 未连接")
                        .font(.custom(WatchTheme.displayCNFont, size: 10))
                        .foregroundStyle(WatchTheme.mist)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("预估费用")
                        .panelLabel()
                    Text(Fmt.currency(model.usage?.cost))
                        .font(.custom(WatchTheme.monoFont, size: 19).weight(.medium))
                        .foregroundStyle(WatchTheme.amber)
                        .contentTransition(.numericText())
                        .animation(WatchMotion.data, value: model.usage?.cost)
                    Text("\(Fmt.compact(model.usage?.credits ?? 0)) 额度点")
                        .font(.custom(WatchTheme.displayCNFont, size: 8.5))
                        .foregroundStyle(WatchTheme.mist)
                }
            }

            VStack(spacing: 7) {
                UsageSparkline(points: model.usage?.series ?? [])
                    .frame(height: 54)
                HStack {
                    Text("00")
                    Spacer()
                    Text("06")
                    Spacer()
                    Text("12")
                    Spacer()
                    Text("18")
                    Spacer()
                    Text("现在")
                }
                .font(.custom(WatchTheme.monoFont, size: 6.5))
                .foregroundStyle(WatchTheme.mist.opacity(0.75))
            }

            HStack(spacing: 0) {
                metric("输入", Fmt.compact(model.usage?.input), suffix: "令牌")
                metric("输出", Fmt.compact(model.usage?.output), suffix: "令牌")
                metric("缓存", Fmt.percent(model.cacheHitRate), suffix: "命中")
                metric("速度", Fmt.rate(model.usage?.decodeOut, decodeMilliseconds: model.usage?.decodeMs), suffix: "生成")
            }
        }
        .padding(16)
        .watchCard(fillOpacity: 0.48)
    }

    private func metric(_ label: String, _ value: String, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.custom(WatchTheme.bodyFont, size: 7).weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(WatchTheme.mist)
            Text(value)
                .font(.custom(WatchTheme.monoFont, size: 11).weight(.medium))
                .foregroundStyle(WatchTheme.ice)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(suffix)
                .font(.custom(WatchTheme.bodyFont, size: 7))
                .foregroundStyle(WatchTheme.mist.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var routeSection: some View {
        VStack(spacing: 0) {
            sectionHeading(
                title: "实时路由",
                detail: model.routePresentation.isLive ? "传输中" : "待机",
                tint: model.routePresentation.isLive ? WatchTheme.seaBright : WatchTheme.mist
            )
            .padding(.horizontal, 15)
            .padding(.top, 14)

            RouteNetworkView(route: model.routePresentation)
                .frame(height: 164)
                .padding(.horizontal, 8)

            TokenFlowView(route: model.routePresentation)
                .padding(.horizontal, 15)
                .padding(.bottom, 4)

            HStack(spacing: 0) {
                routeStat("请求", "\(model.routePresentation.requests)")
                routeStat("重路由", "\(model.routePresentation.rerouted)")
                routeStat("错误", "\(model.routePresentation.errors)", tint: model.routePresentation.errors > 0 ? WatchTheme.coral : WatchTheme.ice)
                routeStat("延迟", model.routePresentation.latency)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(WatchTheme.abyss.opacity(0.28))
        }
        .watchCard(fillOpacity: 0.38)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private var quotaSection: some View {
        VStack(spacing: 10) {
            sectionHeading(
                title: "额度压力",
                detail: model.selectedAccountLine,
                tint: WatchTheme.mist
            )

            if model.quotaHighlights.isEmpty {
                HStack {
                    Image(systemName: "gauge.with.dots.needle.0percent")
                    Text("正在读取账号额度")
                }
                .font(.custom(WatchTheme.bodyFont, size: 11))
                .foregroundStyle(WatchTheme.mist)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
            } else {
                ForEach(model.quotaHighlights) { quota in
                    quotaRow(quota)
                }
            }
        }
        .padding(15)
        .watchCard(fillOpacity: 0.38)
    }

    private func quotaRow(_ quota: QuotaHighlight) -> some View {
        let tint = WatchTheme.tone(quota.tone)
        return VStack(spacing: 7) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(tint)
                    .frame(width: 3, height: 25)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(quota.provider.uppercased())
                            .font(.custom(WatchTheme.bodyFont, size: 9).weight(.bold))
                            .tracking(0.7)
                            .foregroundStyle(WatchTheme.ice)
                        if quota.isSelected {
                            Text("当前")
                                .font(.custom(WatchTheme.displayCNFont, size: 7).weight(.medium))
                                .foregroundStyle(WatchTheme.abyss)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(tint, in: Capsule())
                        }
                    }
                    Text("\(quota.windowName) · \(quota.account)")
                        .font(.custom(WatchTheme.monoFont, size: 7.5))
                        .foregroundStyle(WatchTheme.mist)
                        .lineLimit(1)
                }
                Spacer()
                Text(Fmt.percent(quota.usedPercent))
                    .font(.custom(WatchTheme.monoFont, size: 12).weight(.medium))
                    .foregroundStyle(quota.usedPercent >= 90 ? WatchTheme.coral : tint)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.72), quota.usedPercent >= 90 ? WatchTheme.coral : tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(2, proxy.size.width * quota.usedPercent / 100))
                        .animation(WatchMotion.data, value: quota.usedPercent)
                        .overlay {
                            if quota.usedPercent > 2 {
                                QuotaBarShimmer(tint: .white)
                                    .clipShape(Capsule())
                            }
                        }
                        .shadow(color: tint.opacity(0.35), radius: 3, x: 0, y: 0)
                }
            }
            .frame(height: 3)

            HStack {
                Text(quota.detail)
                Spacer()
                Text(quota.resetText)
            }
            .font(.custom(WatchTheme.bodyFont, size: 7.5))
            .foregroundStyle(WatchTheme.mist.opacity(0.8))
        }
    }

    private var recentActivity: some View {
        VStack(spacing: 8) {
            sectionHeading(
                title: "最近活动",
                detail: "\(model.usage?.agents?.count ?? 0) 个智能体",
                tint: WatchTheme.mist
            )

            ForEach(Array((model.usage?.models ?? []).prefix(3).enumerated()), id: \.element.id) { _, item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(WatchTheme.sea.opacity(0.72))
                        .frame(width: 4, height: 4)
                    Text(item.name ?? item.model ?? "模型")
                        .font(.custom(WatchTheme.bodyFont, size: 9.5).weight(.medium))
                        .foregroundStyle(WatchTheme.ice)
                        .lineLimit(1)
                    Text("· \(Fmt.providerName(item.provider))")
                        .font(.custom(WatchTheme.bodyFont, size: 8))
                        .foregroundStyle(WatchTheme.mist)
                        .lineLimit(1)
                    Spacer()
                    Text("\(item.calls ?? 0)")
                        .font(.custom(WatchTheme.monoFont, size: 8.5))
                        .foregroundStyle(WatchTheme.mist)
                    Text(Fmt.currency(item.cost))
                        .font(.custom(WatchTheme.monoFont, size: 8.5))
                        .foregroundStyle(WatchTheme.amber.opacity(0.88))
                }
            }

            if model.usage?.models?.isEmpty != false {
                Text(model.isOnline ? "暂无请求记录" : "连接 Magpie 后显示最近活动")
                    .font(.custom(WatchTheme.bodyFont, size: 10))
                    .foregroundStyle(WatchTheme.mist)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(15)
        .watchCard(tint: WatchTheme.deep, fillOpacity: 0.32, borderOpacity: 0.065)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(model.isOnline ? WatchTheme.seaBright : WatchTheme.coral)
                    .frame(width: 4, height: 4)
                Text(model.isOnline ? Fmt.relative(model.lastUpdated) : "Magpie 离线")
                    .font(.custom(WatchTheme.bodyFont, size: 8))
                    .foregroundStyle(WatchTheme.mist)
            }
            Spacer()
            Button {
                onOpenScreensaver()
            } label: {
                Label("动态屏保", systemImage: "sparkles.tv")
                    .font(.custom(WatchTheme.displayCNFont, size: 9).weight(.medium))
            }
            .buttonStyle(WatchButtonStyle())
            Button {
                onOpenMagpie()
            } label: {
                Label("打开 Magpie", systemImage: "arrow.up.forward.app")
                    .font(.custom(WatchTheme.displayCNFont, size: 9).weight(.medium))
            }
            .buttonStyle(WatchButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.13))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    private func sectionHeading(title: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .panelLabel()
                .foregroundStyle(WatchTheme.ice.opacity(0.80))
            Spacer()
            Text(detail)
                .font(.custom(WatchTheme.monoFont, size: 7))
                .foregroundStyle(tint)
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(WatchMotion.data, value: detail)
        }
    }

    private func routeStat(_ label: String, _ value: String, tint: Color = WatchTheme.ice) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.custom(WatchTheme.bodyFont, size: 6.5).weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(WatchTheme.mist)
            Text(value)
                .font(.custom(WatchTheme.monoFont, size: 9.5).weight(.medium))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(WatchMotion.data, value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 沿额度条缓慢滑过的一道高光，让静态进度有流动感。
private struct QuotaBarShimmer: View {
    let tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 2.6) / 2.6
            GeometryReader { proxy in
                let bandWidth = proxy.size.width * 0.4
                LinearGradient(
                    colors: [.clear, tint.opacity(0.45), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: bandWidth)
                .offset(x: phase * (proxy.size.width + bandWidth) - bandWidth)
            }
        }
        .accessibilityHidden(true)
    }
}
