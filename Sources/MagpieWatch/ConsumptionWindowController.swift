import AppKit
import SwiftUI

/// 菜单栏「Token 消耗明细…」的独立窗口：左列最近请求，右侧展开上下文构成。
private let detailInk = Color(red: 0.89, green: 0.96, blue: 1)
private let detailMuted = Color(red: 0.60, green: 0.73, blue: 0.81)
private let detailCyan = Color(red: 0.40, green: 0.90, blue: 0.98)

@MainActor
final class ConsumptionWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) { self.model = model }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 680),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "MAGPIE · Token 消耗明细"
            window.minSize = NSSize(width: 780, height: 580)
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentViewController = NSHostingController(rootView: ConsumptionView(model: model))
            window.setContentSize(NSSize(width: 860, height: 680))
            window.delegate = self
            window.center()
            self.window = window
        }
        model.isConsumptionVisible = true
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        Task { await model.refreshConsumption() }
    }

    func windowWillClose(_ notification: Notification) { model.isConsumptionVisible = false }
}

private struct ConsumptionView: View {
    @ObservedObject var model: AppModel
    @State private var selectedID: String?
    var body: some View {
        let records = model.consumptionRecords
        let selected = records.first { $0.id == selectedID } ?? records.first
        return VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Token 消耗明细").font(.system(size: 23, weight: .semibold))
                    Text("桌面上的最近调用 · 展开查看上下文构成").font(.system(size: 12)).foregroundStyle(detailMuted)
                }
                Spacer()
                Button { Task { await model.refresh() } } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .disabled(model.isRefreshing || model.isLoadingRequests)
            }.padding(24)
            Divider()

            if !model.traceIsFresh || model.requestsError != nil {
                Text(!model.traceIsFresh ? "路由暂未更新，以下为上次收到的数据。" : model.requestsError ?? "")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("最近请求 · \(records.count)")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(detailMuted).padding(16)
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(records) { record in
                                Button { selectedID = record.id } label: {
                                    ConsumptionRow(record: record, selected: selected?.id == record.id)
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 8)
                    }
                }.frame(width: 260)
                Divider()
                if let selected {
                    ScrollView { ConsumptionDetail(record: selected).padding(22) }
                        .id(selected.id).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.path").font(.system(size: 34)).foregroundStyle(detailCyan)
                        Text(model.isLoadingRequests ? "正在读取本机请求…" : "还没有请求记录")
                        Text("通过 Magpie 发起调用后，这里会显示消耗来源。")
                            .font(.system(size: 12)).foregroundStyle(detailMuted)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            HStack {
                Text("今日最近 100 条账本 + 当前路由 · 每 4 秒更新")
                Spacer()
                if let date = model.requestsUpdatedAt { Text(date, style: .time) }
            }.font(.system(size: 10)).foregroundStyle(detailMuted).padding(12)
        }
        .foregroundStyle(detailInk)
        .background(Color(red: 0.025, green: 0.065, blue: 0.105))
        .tint(detailCyan)
        .preferredColorScheme(.dark)
    }

}

private struct ConsumptionRow: View {
    let record: ConsumptionRecord
    let selected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(record.purpose).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 4)
                if !record.done { Circle().fill(detailCyan).frame(width: 6, height: 6) }
            }
            Text("\(Fmt.agentName(record.agent)) · \(record.model ?? "模型未提供")")
                .font(.system(size: 10)).lineLimit(1).truncationMode(.middle).foregroundStyle(detailMuted)
            HStack {
                Text(record.statusText).foregroundStyle(record.failed ? .orange : detailMuted)
                Spacer()
                if let date = DateParser.parse(record.time) { Text(date, style: .time).foregroundStyle(detailMuted) }
            }.font(.system(size: 10))
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? detailCyan.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
    }
}

private struct ConsumptionDetail: View {
    let record: ConsumptionRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(record.purpose).font(.system(size: 24, weight: .semibold))
                Text("\(Fmt.agentName(record.agent)) → \(record.model ?? "模型未提供")")
                    .font(.system(size: 12)).foregroundStyle(detailMuted).textSelection(.enabled)
                if let folder = record.folder {
                    Text(URL(fileURLWithPath: folder).lastPathComponent).font(.system(size: 11)).foregroundStyle(detailMuted)
                }
            }
            HStack(spacing: 18) {
                metric("新输入", record.input, detailCyan)
                metric("缓存读取", record.cacheRead, Color(red: 0.69, green: 0.65, blue: 1))
                metric("输出", record.output, Color(red: 1, green: 0.75, blue: 0.49))
            }.padding(.vertical, 4)
            if let reasoning = record.reasoning, reasoning > 0 {
                Text("输出内推理：\(reasoning.formatted()) Token").font(.system(size: 11)).foregroundStyle(detailMuted)
            }
            if let writes = record.cacheWrite, writes > 0 {
                Text("缓存写入：\(writes.formatted()) Token").font(.system(size: 11)).foregroundStyle(detailMuted)
            }
            Divider()
            if let prompt = record.prompt, let parts = prompt.parts, !parts.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("本次上下文构成").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(prompt.counted == true ? "Magpie 计数" : "Magpie 估算").font(.system(size: 10)).foregroundStyle(detailMuted)
                    }
                    Text("工具返回和文件内容进入上下文后会消耗输入 Token。工具定义是说明书，不代表执行次数。此处包含历史内容，不与上方用量相加。")
                        .font(.system(size: 11)).foregroundStyle(detailMuted).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(parts.sorted { ($0.tokens ?? 0) > ($1.tokens ?? 0) }.enumerated()), id: \.offset) { _, part in
                    PromptPartView(part: part, total: prompt.tokens)
                }
            } else {
                Text("Magpie 未提供这次请求的上下文拆分。请求用途与 Token 用量仍按实际返回显示。")
                    .font(.system(size: 12)).foregroundStyle(detailMuted).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ title: String, _ value: Int?, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundStyle(detailMuted)
            Text(value.map { $0.formatted() } ?? "待计量").font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(tint)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PromptPartView: View {
    let part: PromptPart
    let total: Int?
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(spacing: 10) {
                    ForEach(Array((part.items ?? []).enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top) {
                            Text(item.name ?? "未命名").lineLimit(3).textSelection(.enabled)
                            if let count = item.n, count > 1 { Text("×\(count)").foregroundStyle(detailMuted) }
                            Spacer(minLength: 8)
                            Text(item.tokens.map { $0.formatted() } ?? "—").monospacedDigit()
                        }.font(.system(size: 11)).foregroundStyle(detailMuted)
                    }
                }.padding(.top, 9).padding(.leading, 5)
            } label: {
                HStack {
                    Text(part.title).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(part.tokens.map { $0.formatted() } ?? "—").font(.system(size: 12, design: .monospaced)).foregroundStyle(detailCyan)
                }
            }
            GeometryReader { proxy in
                Capsule().fill(detailCyan.opacity(0.10))
                Capsule().fill(detailCyan.opacity(0.65))
                    .frame(width: proxy.size.width * min(1, max(0, Double(part.tokens ?? 0) / Double(max(1, total ?? 1)))))
            }.frame(height: 3)
        }.padding(.vertical, 3)
    }
}
