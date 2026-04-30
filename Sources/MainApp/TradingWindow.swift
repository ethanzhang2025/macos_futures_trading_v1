// MainApp · 模拟交易窗口（v15.4 · WP-54 SimNow 模拟训练第 2 批）
//
// 职责：
// - 顶部账户摘要（balance / available / margin / positionPnL / closePnL / commission / riskRatio）
// - 下单区（合约 Picker + 买/卖 + 开/平 + 价格 + 数量 + 提交 / 拒绝消息）
// - Tab：委托 / 成交 / 持仓 · 实时订阅 engine.observe()
//
// 设计要点（与 AlertWindow / WatchlistWindow 同款模式）：
// - .task 启动加载初始状态 + 订阅 observe stream
// - 收到任何事件 → 重新拉 engine 全量 snapshot（actor 单线程化无并发问题）
// - 下单失败 → lastSubmitMessage 显示原因 · 5s 后自动清掉

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Foundation
import Shared
import TradingCore

// MARK: - Tab

private enum TradingTab: String, CaseIterable, Identifiable {
    case orders    = "委托"
    case trades    = "成交"
    case positions = "持仓"
    case equity    = "资金曲线"
    var id: String { rawValue }
}

// MARK: - 主窗口

struct TradingWindow: View {

    @State private var account: Account = Self.emptyAccount
    @State private var orders: [OrderRecord] = []
    @State private var trades: [TradeRecord] = []
    @State private var positions: [Position] = []
    @State private var contracts: [Contract] = []
    @State private var equityCurve: [EquityCurvePoint] = []
    @State private var selectedTab: TradingTab = .orders
    @State private var observeTask: Task<Void, Never>?

    /// 下单表单草稿
    @State private var draftInstrumentID: String = "RB0"
    @State private var draftDirection: Direction = .buy
    @State private var draftOffset: OffsetFlag = .open
    @State private var draftPrice: Double = 3500
    @State private var draftVolume: Int = 1

    /// 最近一次操作的反馈（成功/拒绝原因 · 5s 自动清）
    @State private var feedback: SubmitFeedback?
    /// feedback 的单调递增 token · scheduleClearFeedback 5s 后只清自己那条
    /// 用 token 而非 == 比较 message · 避免短时间内同样内容反馈被误清
    @State private var feedbackToken: UInt = 0
    /// v15.6 持久化节流 · 1s 间隔最多写盘 1 次（与 ChartScene viewport 同款）
    @State private var lastSnapshotSaveTime: Date = .distantPast

    @Environment(\.simulatedTradingEngine) private var engine

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            orderForm
            Divider()
            tabBar
            Divider()
            tabContent
        }
        .frame(minWidth: 900, idealWidth: 1100, minHeight: 600, idealHeight: 720)
        .task {
            await loadInitial()
            startObserving()
        }
        .onDisappear { observeTask?.cancel() }
    }

    // MARK: - 顶部账户摘要

    private var header: some View {
        HStack(spacing: 16) {
            Text("🧪 模拟交易").font(.title2).bold()
            Divider().frame(height: 24)
            stat("动态权益", fmtMoney(account.balance), color: .primary)
            stat("可用资金", fmtMoney(account.available), color: account.available >= 0 ? .green : .red)
            stat("保证金", fmtMoney(account.margin))
            stat("浮动盈亏", fmtMoney(account.positionPnL),
                 color: account.positionPnL >= 0 ? .green : .red)
            stat("平仓盈亏", fmtMoney(account.closePnL),
                 color: account.closePnL >= 0 ? .green : .red)
            stat("手续费", fmtMoney(account.commission), color: .secondary)
            stat("风险度", "\(fmtPercent(account.riskRatio))%",
                 color: account.riskRatio < 50 ? .green : (account.riskRatio < 80 ? .orange : .red))
            Spacer()
            // v15.5 当日交割单 CSV 导出（委托 / 成交 / 持仓 三表合一）
            Button {
                exportCSV()
            } label: {
                Label("导出 CSV", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .help("当日交割单 · 委托 / 成交 / 持仓 三表合一 UTF-8 BOM")

            // v15.6 重置账户（清持久化快照 · 重建 100w 初始）
            Button {
                resetAccountWithConfirmation()
            } label: {
                Label("重置账户", systemImage: "arrow.counterclockwise.circle")
            }
            .buttonStyle(.borderless)
            .help("清空所有委托/成交/持仓/资金曲线 · 资金恢复 1,000,000")
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private func stat(_ label: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(size: 13, design: .monospaced)).foregroundColor(color)
        }
    }

    // MARK: - 下单表单

    private var orderForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker("合约", selection: $draftInstrumentID) {
                    ForEach(contracts, id: \.instrumentID) { c in
                        Text("\(c.instrumentID) · \(c.instrumentName)").tag(c.instrumentID)
                    }
                }
                .frame(width: 220)

                Picker("方向", selection: $draftDirection) {
                    Text("买").tag(Direction.buy)
                    Text("卖").tag(Direction.sell)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .labelsHidden()

                Picker("开平", selection: $draftOffset) {
                    Text("开仓").tag(OffsetFlag.open)
                    Text("平仓").tag(OffsetFlag.close)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .labelsHidden()

                HStack(spacing: 4) {
                    Text("价格")
                    TextField("", value: $draftPrice, format: .number).frame(width: 90)
                }

                HStack(spacing: 4) {
                    Text("数量")
                    TextField("", value: $draftVolume, format: .number).frame(width: 60)
                    Stepper("", value: $draftVolume, in: 1...1000).labelsHidden()
                }

                Button {
                    Task { await submitOrder() }
                } label: {
                    Label(draftDirection == .buy ? "买入" : "卖出", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }

            if let fb = feedback {
                Text(fb.message)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(fb.isError ? .red : .green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Tab 切换

    private var tabBar: some View {
        Picker("", selection: $selectedTab) {
            ForEach(TradingTab.allCases) { t in
                Text("\(t.rawValue) (\(tabBadgeCount(t)))").tag(t)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .labelsHidden()
    }

    private func tabBadgeCount(_ tab: TradingTab) -> Int {
        switch tab {
        case .orders:    return orders.count
        case .trades:    return trades.count
        case .positions: return positions.count
        case .equity:    return equityCurve.count
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .orders:    ordersList
        case .trades:    tradesList
        case .positions: positionsList
        case .equity:    equityCurveView
        }
    }

    // MARK: - 资金曲线（v15.5）

    private var equityCurveView: some View {
        let firstBalance = equityCurve.first?.balance ?? 0
        let lastBalance = equityCurve.last?.balance ?? 0
        let balances = equityCurve.map(\.balance)
        return VStack(spacing: 0) {
            // HUD：起始 / 当前 / 最高 / 最低
            HStack(spacing: 24) {
                stat("起始", fmtMoney(firstBalance), color: .secondary)
                stat("当前", fmtMoney(lastBalance),
                     color: lastBalance >= firstBalance ? .green : .red)
                stat("最高", fmtMoney(balances.max() ?? 0), color: .green)
                stat("最低", fmtMoney(balances.min() ?? 0), color: .red)
                Divider().frame(height: 24)
                stat("点数", "\(equityCurve.count)", color: .secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.06))

            Canvas { ctx, size in drawEquityCurve(ctx, size: size) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.07, green: 0.08, blue: 0.10))
        }
    }

    /// 资金曲线绘制 · 起始基线虚线 + 折线 + 上涨绿/下跌红区分色
    private func drawEquityCurve(_ ctx: GraphicsContext, size: CGSize) {
        guard equityCurve.count >= 2 else {
            // 单点 / 空 → 中央提示
            let text = Text("等待交易事件 · 当前 \(equityCurve.count) 个数据点")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            ctx.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
            return
        }

        let balances = equityCurve.map { NSDecimalNumber(decimal: $0.balance).doubleValue }
        guard let minB = balances.min(), let maxB = balances.max() else { return }
        let range = max(0.01, maxB - minB)
        // 上下各留 10% padding · 防贴边
        let viewMin = minB - range * 0.1
        let viewMax = maxB + range * 0.1
        let viewRange = viewMax - viewMin

        let n = balances.count
        let step = (n > 1) ? size.width / CGFloat(n - 1) : size.width
        let baseline = balances.first ?? 0
        // value → 屏幕 Y（顶部 = max · 底部 = min）
        func yFor(_ value: Double) -> CGFloat {
            (1 - (value - viewMin) / viewRange) * size.height
        }

        // 起始基线虚线
        let baselineY = yFor(baseline)
        var dash = Path()
        dash.move(to: CGPoint(x: 0, y: baselineY))
        dash.addLine(to: CGPoint(x: size.width, y: baselineY))
        ctx.stroke(dash, with: .color(.white.opacity(0.25)),
                   style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

        // 折线（终态盈利绿 / 亏损红 · v1 不分段）
        var path = Path()
        for (i, b) in balances.enumerated() {
            let pt = CGPoint(x: CGFloat(i) * step, y: yFor(b))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        let isProfitable = (balances.last ?? 0) >= baseline
        let lineColor: Color = isProfitable ? .green : .red
        ctx.stroke(path,
                   with: .color(lineColor),
                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

        // 终点圆点
        let lastX = CGFloat(n - 1) * step
        let lastY = yFor(balances.last ?? 0)
        let dot = Path(ellipseIn: CGRect(x: lastX - 3, y: lastY - 3, width: 6, height: 6))
        ctx.fill(dot, with: .color(lineColor))
    }

    // MARK: - 委托表

    private var ordersList: some View {
        Self.tableContainer(headers: [
            ("时间", 80), ("合约", 80), ("方向", 50), ("开平", 60),
            ("价格", 80), ("数量", 50), ("成交", 50), ("状态", 80), ("操作", 80)
        ]) {
            ForEach(orders, id: \.orderRef) { o in
                HStack(spacing: 8) {
                    cell(o.insertTime, width: 80, color: .secondary)
                    cell(o.instrumentID, width: 80)
                    cell(o.direction.displayName, width: 50,
                         color: o.direction == .buy ? .red : .green)
                    cell(o.offsetFlag.displayName, width: 60)
                    cell(fmtPrice(o.price), width: 80, alignment: .trailing)
                    cell("\(o.totalVolume)", width: 50, alignment: .trailing)
                    cell("\(o.filledVolume)", width: 50, alignment: .trailing,
                         color: o.filledVolume > 0 ? .accentColor : .secondary)
                    cell(o.status.displayName, width: 80,
                         color: orderStatusColor(o.status))
                    HStack {
                        if o.status.isActive {
                            Button("撤单") {
                                Task { await cancelOrder(orderRef: o.orderRef) }
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                        } else {
                            Text("—").foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 80, alignment: .leading)
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                Divider()
            }
        }
    }

    private func orderStatusColor(_ s: OrderStatus) -> Color {
        switch s {
        case .filled:                       return .green
        case .cancelled, .rejected:         return .secondary
        case .pending, .submitted, .partFilled: return .accentColor
        case .unknown:                      return .secondary
        }
    }

    // MARK: - 成交表

    private var tradesList: some View {
        Self.tableContainer(headers: [
            ("时间", 80), ("合约", 80), ("方向", 50), ("开平", 60),
            ("成交价", 90), ("成交量", 60), ("手续费", 80), ("成交号", 100)
        ]) {
            ForEach(trades, id: \.tradeID) { t in
                HStack(spacing: 8) {
                    cell(t.tradeTime, width: 80, color: .secondary)
                    cell(t.instrumentID, width: 80)
                    cell(t.direction.displayName, width: 50,
                         color: t.direction == .buy ? .red : .green)
                    cell(t.offsetFlag.displayName, width: 60)
                    cell(fmtPrice(t.price), width: 90, alignment: .trailing)
                    cell("\(t.volume)", width: 60, alignment: .trailing)
                    cell(fmtMoney(t.commission), width: 80, alignment: .trailing, color: .secondary)
                    cell(t.tradeID, width: 100, color: .secondary)
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                Divider()
            }
        }
    }

    // MARK: - 持仓表

    private var positionsList: some View {
        Self.tableContainer(headers: [
            ("合约", 80), ("方向", 50), ("总数", 50), ("今仓", 50),
            ("均价", 90), ("保证金", 100), ("乘数", 60), ("操作", 100)
        ]) {
            ForEach(positions, id: \.positionKey) { p in
                HStack(spacing: 8) {
                    cell(p.instrumentID, width: 80)
                    cell(p.direction.displayName, width: 50,
                         color: p.direction == .long ? .red : .green)
                    cell("\(p.volume)", width: 50, alignment: .trailing)
                    cell("\(p.todayVolume)", width: 50, alignment: .trailing, color: .secondary)
                    cell(fmtPrice(p.openAvgPrice), width: 90, alignment: .trailing)
                    cell(fmtMoney(p.margin), width: 100, alignment: .trailing)
                    cell("\(p.volumeMultiple)", width: 60, alignment: .trailing, color: .secondary)
                    Button("一键平仓") {
                        Task { await quickClose(p) }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .frame(width: 100, alignment: .leading)
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                Divider()
            }
        }
    }

    // MARK: - 通用 helper（cell / tableContainer）

    private func cell(_ text: String, width: CGFloat,
                      alignment: Alignment = .leading,
                      color: Color = .primary) -> some View {
        Text(text)
            .frame(width: width, alignment: alignment)
            .foregroundColor(color)
    }

    @ViewBuilder
    private static func tableContainer<Content: View>(
        headers: [(String, CGFloat)],
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                    Text(h.0).frame(width: h.1, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.06))
            ScrollView {
                LazyVStack(spacing: 0) { content() }
            }
        }
    }

    // MARK: - 业务动作

    private func submitOrder() async {
        guard let engine else {
            showFeedback(.error("引擎未注入"))
            return
        }
        let request = OrderRequest(
            instrumentID: draftInstrumentID,
            direction: draftDirection,
            offsetFlag: draftOffset,
            priceType: .limitPrice,
            price: Decimal(draftPrice),
            volume: draftVolume
        )
        let (ref, rejection) = await engine.submitOrder(request)
        if let r = rejection {
            showFeedback(.error("委托被拒 · \(r.displayMessage)"))
        } else {
            showFeedback(.success("委托已提交 · \(ref) · 等待撮合"))
        }
    }

    private func cancelOrder(orderRef: String) async {
        guard let engine else { return }
        let ok = await engine.cancelOrder(orderRef: orderRef)
        showFeedback(ok
            ? .success("撤单成功 · \(orderRef)")
            : .error("撤单失败 · \(orderRef)（已成交或不存在）"))
    }

    /// 一键平仓：按持仓全量提交极端价限价平仓单模拟市价（v1 SimulatedTradingEngine 不支持市价单）
    /// 撮合规则（v1 限价语义）：买单需 lastPrice ≤ price · 卖单需 lastPrice ≥ price
    /// 多头平=卖：price 取近 0（0.01）→ 任何 lastPrice ≥ 0.01 都可成 · 不受暴跌影响
    /// 空头平=买：price 取极大（1e9）→ 任何 lastPrice ≤ 1e9 都可成 · 不受暴涨影响
    /// （旧 0.5x / 2x 开仓均价：极端行情下可能不被撮合 · 已修）
    private func quickClose(_ p: Position) async {
        guard let engine else { return }
        let isLong = p.direction == .long
        let direction: Direction = isLong ? .sell : .buy
        let extremePrice: Decimal = isLong ? Self.minClosePrice : Self.maxClosePrice
        let request = OrderRequest(
            instrumentID: p.instrumentID,
            direction: direction,
            offsetFlag: .close,
            priceType: .limitPrice,
            price: extremePrice,
            volume: p.volume
        )
        let (_, rejection) = await engine.submitOrder(request)
        if let r = rejection {
            showFeedback(.error("一键平仓被拒 · \(r.displayMessage)"))
        } else {
            showFeedback(.success("一键平仓单已提交 · 等待下一个 Tick 撮合"))
        }
    }

    /// 一键平仓极端价（限价单模拟市价）
    private static let minClosePrice = Decimal(string: "0.01")!
    private static let maxClosePrice = Decimal(string: "1000000000")!

    // MARK: - 数据加载 / 订阅

    private func loadInitial() async {
        guard let engine else { return }
        contracts = await engine.allContracts().sorted { $0.instrumentID < $1.instrumentID }
        if let first = contracts.first { draftInstrumentID = first.instrumentID }
        await refresh()
    }

    private func startObserving() {
        guard let engine, observeTask == nil else { return }
        observeTask = Task {
            for await _ in await engine.observe() {
                await refresh()
                await saveSnapshotIfNeeded()
            }
        }
    }

    /// 1s 节流持久化 · 事件 burst 时仅最末一次写盘
    /// @MainActor 保证 lastSnapshotSaveTime 读写均在 MainActor · 不跨 actor 边界访问 @State
    @MainActor
    private func saveSnapshotIfNeeded() async {
        guard let engine else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSnapshotSaveTime) >= 1 else { return }
        lastSnapshotSaveTime = now
        let snap = await engine.snapshot()
        // 后台序列化 + UserDefaults set · 5000 trades JSON ~5ms
        // fire-and-forget · v1 接受 App 退出时最末一次可能丢失（下次启动从倒数第二次恢复）
        Task.detached(priority: .background) {
            SimulatedTradingStore.save(snap)
        }
    }

    private func refresh() async {
        guard let engine else { return }
        // SimulatedTradingEngine 是单 actor · async let 实际仍串行执行 · 直接顺序 await 更清晰
        let a = await engine.currentAccount()
        let o = await engine.allOrders()
        let t = await engine.allTrades()
        let p = await engine.allPositions()
        let eq = await engine.equityCurveSnapshot()
        await MainActor.run {
            account = a
            orders = o.sorted { $0.orderRef > $1.orderRef }   // 新的在前
            trades = t.reversed()
            positions = p
            equityCurve = eq
        }
    }

    /// 写入新反馈 + 5s 后只清自己那条（用 token 比 message 更稳）
    private func showFeedback(_ fb: SubmitFeedback) {
        feedbackToken &+= 1
        let myToken = feedbackToken
        feedback = fb
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                if feedbackToken == myToken { feedback = nil }
            }
        }
    }

    // MARK: - 重置账户（v15.6）

    /// 弹 NSAlert 确认 · 用户点"重置"才执行：清快照 + engine.reset + 立即 refresh
    private func resetAccountWithConfirmation() {
        let alert = NSAlert()
        alert.messageText = "重置模拟账户？"
        alert.informativeText = "将清空所有委托 / 成交 / 持仓 / 资金曲线 · 资金恢复 1,000,000 · 此操作不可撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "重置")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            guard let engine else { return }
            await engine.reset(initialBalance: 1_000_000)
            SimulatedTradingStore.clear()
            await MainActor.run { lastSnapshotSaveTime = .distantPast }
            await refresh()
            showFeedback(.success("已重置 · 资金恢复 1,000,000"))
        }
    }

    // MARK: - CSV 导出（v15.5 · 当日交割单 · 委托/成交/持仓 三表合一）

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.title = "导出当日交割单"
        panel.allowedContentTypes = [.commaSeparatedText]
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd-HHmmss"
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        panel.nameFieldStringValue = "trading_\(dateFmt.string(from: Date())).csv"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let csv = Self.buildCSV(orders: orders, trades: trades, positions: positions, account: account)
        // UTF-8 BOM 让 Excel 正确识别中文
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(csv.data(using: .utf8) ?? Data())
        do {
            try data.write(to: url)
            showFeedback(.success("交割单已导出：\(url.lastPathComponent)"))
        } catch {
            showFeedback(.error("导出失败：\(error.localizedDescription)"))
        }
    }

    /// 三表合一 CSV · 章节标题（Excel 友好：单字段标题行 + 空行分隔，无 # 注释）
    private static func buildCSV(
        orders: [OrderRecord], trades: [TradeRecord],
        positions: [Position], account: Account
    ) -> String {
        var lines: [String] = []
        appendSection(into: &lines, title: "账户摘要", header: "项,值", rows: [
            "动态权益,\(account.balance)",
            "可用资金,\(account.available)",
            "保证金,\(account.margin)",
            "浮动盈亏,\(account.positionPnL)",
            "平仓盈亏,\(account.closePnL)",
            "手续费,\(account.commission)",
        ])
        appendSection(into: &lines, title: "委托记录",
                      header: "时间,委托号,合约,方向,开平,价格,总量,已成,状态,消息",
                      rows: orders.map { o in
            "\(csvEscape(o.insertTime)),\(csvEscape(o.orderRef)),\(csvEscape(o.instrumentID)),\(o.direction.displayName),\(o.offsetFlag.displayName),\(o.price),\(o.totalVolume),\(o.filledVolume),\(o.status.displayName),\(csvEscape(o.statusMessage))"
        })
        appendSection(into: &lines, title: "成交记录",
                      header: "时间,成交号,委托号,合约,方向,开平,成交价,数量,手续费",
                      rows: trades.map { t in
            "\(csvEscape(t.tradeTime)),\(csvEscape(t.tradeID)),\(csvEscape(t.orderRef)),\(csvEscape(t.instrumentID)),\(t.direction.displayName),\(t.offsetFlag.displayName),\(t.price),\(t.volume),\(t.commission)"
        })
        appendSection(into: &lines, title: "持仓快照",
                      header: "合约,方向,数量,今仓,均价,保证金,乘数",
                      rows: positions.map { p in
            "\(csvEscape(p.instrumentID)),\(p.direction.displayName),\(p.volume),\(p.todayVolume),\(p.openAvgPrice),\(p.margin),\(p.volumeMultiple)"
        }, trailingBlank: false)
        return lines.joined(separator: "\n") + "\n"
    }

    /// 追加 CSV 章节：标题行（单字段 · Excel 直接识别）+ 表头 + 数据 + 可选尾空行
    private static func appendSection(
        into lines: inout [String],
        title: String, header: String, rows: [String],
        trailingBlank: Bool = true
    ) {
        lines.append(csvEscape(title))
        lines.append(header)
        lines.append(contentsOf: rows)
        if trailingBlank { lines.append("") }
    }

    /// CSV 字段转义（RFC 4180）：含逗号 / 引号 / CR / LF 时用双引号包住 + 内部双引号转双双引号
    private static func csvEscape(_ s: String) -> String {
        if s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
    }

    // MARK: - 静态/格式化辅助

    private static let emptyAccount = Account(
        preBalance: 0, deposit: 0, withdraw: 0,
        closePnL: 0, positionPnL: 0,
        commission: 0, margin: 0
    )

    private func fmtMoney(_ v: Decimal) -> String {
        let n = NSDecimalNumber(decimal: v).doubleValue
        return String(format: "%.2f", n)
    }

    private func fmtPrice(_ v: Decimal) -> String {
        let n = NSDecimalNumber(decimal: v).doubleValue
        if abs(n - n.rounded()) < 0.001 { return String(format: "%.0f", n) }
        return String(format: "%.2f", n)
    }

    private func fmtPercent(_ v: Decimal) -> String {
        let n = NSDecimalNumber(decimal: v).doubleValue
        return String(format: "%.1f", n)
    }
}

// MARK: - 反馈消息（token 比对替代 Equatable · 静态 success/error 简化调用方）

private struct SubmitFeedback {
    let message: String
    let isError: Bool
    static func success(_ m: String) -> SubmitFeedback { .init(message: m, isError: false) }
    static func error(_ m: String) -> SubmitFeedback { .init(message: m, isError: true) }
}

// MARK: - Position ForEach id key

private extension Position {
    /// SwiftUI ForEach 用的 key（Position 不是 Identifiable · 持仓最多一个 (instrument, direction) 对）
    var positionKey: String {
        "\(instrumentID).\(direction == .long ? "L" : "S")"
    }
}

#endif
