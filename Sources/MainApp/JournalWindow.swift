// MainApp · 交易日志面板（WP-53 UI · commit 1/4 · ⌘J 起步 + 双 Tab + Mock 13 trades + 5 journals）
//
// commit 1 起步：
// - ⌘J 独立窗口 · TabView segmented 切换：成交记录 / 交易日志
// - 成交记录 Tab：13 笔 Mock trades（4 合约 RB/IF/AU/CU · 3 来源 wenhua/generic/manual · 跨 3 天）
// - 交易日志 Tab：5 篇 Mock journals（关联 trade.id · 5 类情绪 + 5 类偏差 + 标签）
// - 顶部 stats（总成交 / 总日志 / 触发 commit 进度标签）+ 底部提示
//
// 留给后续 commit：
// - commit 2/4：CSV 导入面板（NSOpenPanel + DealCSVParser + 格式选择 + 错误展示）
// - commit 3/4：日志编辑器 Sheet（情绪/偏差 Picker + tags + JournalGenerator 自动生成 batch）
// - commit 4/4：标签搜索 + 月度/季度统计聚合
//
// 留待 M5：StoreManager 注入 SQLiteJournalStore（已就绪 · trades + journals CRUD）替换 Mock

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import JournalCore
import Shared

// MARK: - Tab 切换

private enum JournalTab: String, CaseIterable, Identifiable {
    case trades   = "成交记录"
    case journals = "交易日志"
    var id: String { rawValue }
}

// MARK: - 主窗口

struct JournalWindow: View {

    @State private var trades: [Trade] = []
    @State private var journals: [TradeJournal] = []
    @State private var selectedTab: JournalTab = .trades

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 880, idealWidth: 1100, minHeight: 520, idealHeight: 720)
        .task {
            if trades.isEmpty {
                let mock = MockJournalData.generate()
                trades = mock.trades
                journals = mock.journals
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 24) {
            Text("📔 交易日志").font(.title2).bold()
            Divider().frame(height: 24)
            stat("总成交", "\(trades.count) 笔")
            stat("总日志", "\(journals.count) 篇")
            Spacer()
            Text("commit 1/4 · ⌘J 起步")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.gray.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(size: 14, design: .monospaced))
        }
    }

    // MARK: - Tab 栏

    private var tabBar: some View {
        Picker("", selection: $selectedTab) {
            ForEach(JournalTab.allCases) { t in
                Text(t.rawValue).tag(t)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .labelsHidden()
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .trades:   tradesTable
        case .journals: journalsTable
        }
    }

    // MARK: - 成交记录 Tab

    private var tradesTable: some View {
        Table(trades) {
            TableColumn("合约") { t in
                Text(t.instrumentID).fontWeight(.medium)
            }
            .width(min: 70, ideal: 80)

            TableColumn("方向") { t in
                Text(t.direction.displayName)
                    .foregroundColor(t.direction == .buy ? .red : .green)
            }
            .width(min: 50, ideal: 60)

            TableColumn("开/平") { t in
                Text(t.offsetFlag.displayName)
            }
            .width(min: 60, ideal: 70)

            TableColumn("成交价") { t in
                Text(formatDecimal(t.price, fractionDigits: 1))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 90)

            TableColumn("数量") { t in
                Text("\(t.volume)")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 50, ideal: 60)

            TableColumn("手续费") { t in
                Text(formatDecimal(t.commission, fractionDigits: 2))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 80)

            TableColumn("时间") { t in
                Text(Self.timestampFormatter.string(from: t.timestamp))
                    .foregroundColor(.secondary)
            }
            .width(min: 130, ideal: 150)

            TableColumn("来源") { t in
                Text(sourceLabel(t.source))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.12))
                    .clipShape(Capsule())
            }
            .width(min: 60, ideal: 70)
        }
        .font(.system(.body, design: .monospaced))
    }

    // MARK: - 交易日志 Tab

    private var journalsTable: some View {
        Table(journals) {
            TableColumn("标题") { j in
                Text(j.title).fontWeight(.medium)
            }
            .width(min: 220, ideal: 280)

            TableColumn("成交") { j in
                Text("\(j.tradeIDs.count) 笔")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(min: 60, ideal: 70)

            TableColumn("情绪") { j in
                Text(emotionLabel(j.emotion))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(emotionColor(j.emotion).opacity(0.18))
                    .foregroundColor(emotionColor(j.emotion))
                    .clipShape(Capsule())
            }
            .width(min: 70, ideal: 80)

            TableColumn("偏差") { j in
                Text(deviationLabel(j.deviation))
                    .font(.caption)
                    .foregroundColor(j.deviation == .asPlanned ? .green : .orange)
            }
            .width(min: 80, ideal: 100)

            TableColumn("标签") { j in
                Text(j.tags.sorted().joined(separator: " · "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 200)

            TableColumn("更新时间") { j in
                Text(Self.timestampFormatter.string(from: j.updatedAt))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(min: 130, ideal: 150)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("Mock 数据 · 待 commit 2 CSV 导入 · commit 3 日志编辑器 · commit 4 月度统计 · M5 接 SQLiteJournalStore")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - 标签格式化

    private func sourceLabel(_ s: TradeSource) -> String {
        switch s {
        case .wenhua:  return "文华"
        case .generic: return "通用"
        case .manual:  return "手填"
        }
    }

    private func emotionLabel(_ e: JournalEmotion) -> String {
        switch e {
        case .confident: return "自信"
        case .hesitant:  return "犹豫"
        case .fearful:   return "恐惧"
        case .greedy:    return "贪婪"
        case .calm:      return "平静"
        }
    }

    private func emotionColor(_ e: JournalEmotion) -> Color {
        switch e {
        case .confident: return .green
        case .hesitant:  return .orange
        case .fearful:   return .red
        case .greedy:    return .purple
        case .calm:      return .blue
        }
    }

    private func deviationLabel(_ d: JournalDeviation) -> String {
        switch d {
        case .asPlanned:     return "按计划"
        case .breakStopLoss: return "破止损"
        case .chaseRebound:  return "抢反弹"
        case .chaseHigh:     return "追高"
        case .catchFalling:  return "抄底"
        case .earlyExit:     return "过早离场"
        case .overTrade:     return "超额交易"
        case .other:         return "其他"
        }
    }

    private func formatDecimal(_ d: Decimal, fractionDigits: Int) -> String {
        let nf = fractionDigits == 1 ? Self.priceFormatter : Self.feeFormatter
        return nf.string(from: d as NSDecimalNumber) ?? "\(d)"
    }

    private static let priceFormatter: NumberFormatter = makeDecimalFormatter(fractionDigits: 1)
    private static let feeFormatter: NumberFormatter = makeDecimalFormatter(fractionDigits: 2)

    private static func makeDecimalFormatter(fractionDigits: Int) -> NumberFormatter {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = fractionDigits
        nf.maximumFractionDigits = fractionDigits
        return nf
    }

    static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - Mock 数据（commit 1 静态 · commit 2 CSV 导入接管 · M5 替换为 SQLiteJournalStore）

private enum MockJournalData {

    static func generate() -> (trades: [Trade], journals: [TradeJournal]) {
        let now = Date()
        let trades = generateTrades(anchor: now)
        let journals = generateJournals(now: now, trades: trades)
        return (trades, journals)
    }

    private struct Spec {
        let symbol: String
        let dir: Direction
        let off: OffsetFlag
        let price: String
        let vol: Int
        let fee: String
        let minutes: Int
        let source: TradeSource
        let ref: String
    }

    private static func generateTrades(anchor: Date) -> [Trade] {
        let specs: [Spec] = [
            // RB2510 日内 7 笔（最新 → 最旧）
            Spec(symbol: "RB2510", dir: .buy,  off: .open,           price: "3251",   vol: 2, fee: "1.50",  minutes: -30,    source: .wenhua,  ref: "WH26042807"),
            Spec(symbol: "RB2510", dir: .sell, off: .close,          price: "3255",   vol: 4, fee: "1.50",  minutes: -55,    source: .wenhua,  ref: "WH26042806"),
            Spec(symbol: "RB2510", dir: .buy,  off: .open,           price: "3248",   vol: 4, fee: "1.50",  minutes: -80,    source: .wenhua,  ref: "WH26042805"),
            Spec(symbol: "RB2510", dir: .buy,  off: .closeYesterday, price: "3243",   vol: 3, fee: "1.50",  minutes: -105,   source: .wenhua,  ref: "WH26042804"),
            Spec(symbol: "RB2510", dir: .sell, off: .open,           price: "3250",   vol: 3, fee: "1.50",  minutes: -130,   source: .wenhua,  ref: "WH26042803"),
            Spec(symbol: "RB2510", dir: .sell, off: .close,          price: "3252",   vol: 5, fee: "1.50",  minutes: -155,   source: .wenhua,  ref: "WH26042802"),
            Spec(symbol: "RB2510", dir: .buy,  off: .open,           price: "3245",   vol: 5, fee: "1.50",  minutes: -180,   source: .wenhua,  ref: "WH26042801"),
            // IF2509 跨日 3 笔
            Spec(symbol: "IF2509", dir: .sell, off: .open,           price: "3870.0", vol: 1, fee: "23.00", minutes: -1440,        source: .wenhua,  ref: "WH26042705"),
            Spec(symbol: "IF2509", dir: .sell, off: .close,          price: "3865.4", vol: 2, fee: "23.00", minutes: -1500,        source: .wenhua,  ref: "WH26042704"),
            Spec(symbol: "IF2509", dir: .buy,  off: .open,           price: "3852.0", vol: 2, fee: "23.00", minutes: -1560,        source: .wenhua,  ref: "WH26042703"),
            // AU2512 长线 2 笔
            Spec(symbol: "AU2512", dir: .sell, off: .close,          price: "619.0",  vol: 3, fee: "10.00", minutes: -1440 * 2,    source: .generic, ref: "GEN042602"),
            Spec(symbol: "AU2512", dir: .buy,  off: .open,           price: "612.5",  vol: 5, fee: "10.00", minutes: -1440 * 3,    source: .generic, ref: "GEN042601"),
            // CU2511 手动 1 笔
            Spec(symbol: "CU2511", dir: .buy,  off: .open,           price: "78650",  vol: 1, fee: "5.00",  minutes: -1440 - 30,   source: .manual,  ref: "MAN001")
        ]
        return specs.map { spec in
            Trade(
                tradeReference: spec.ref,
                instrumentID: spec.symbol,
                direction: spec.dir,
                offsetFlag: spec.off,
                price: Decimal(string: spec.price)!,
                volume: spec.vol,
                commission: Decimal(string: spec.fee)!,
                timestamp: anchor.addingTimeInterval(TimeInterval(spec.minutes * 60)),
                source: spec.source
            )
        }
    }

    private static func generateJournals(now: Date, trades: [Trade]) -> [TradeJournal] {
        let rbIDs = trades.filter { $0.instrumentID == "RB2510" }.map(\.id)
        let ifIDs = trades.filter { $0.instrumentID == "IF2509" }.map(\.id)
        let auIDs = trades.filter { $0.instrumentID == "AU2512" }.map(\.id)
        let cuIDs = trades.filter { $0.instrumentID == "CU2511" }.map(\.id)
        let allIDs = rbIDs + ifIDs + auIDs + cuIDs

        return [
            TradeJournal(
                tradeIDs: rbIDs,
                title: "RB0 日内三段操作 · 跟随 5min MA20 顺势",
                reason: "5min MA20 上行 · 价格回调到 MA20 上方建多单 · 上涨突破前高加仓",
                emotion: .confident,
                deviation: .asPlanned,
                lesson: "止损位放在 5min MA60 下方 · 跟住趋势没追高",
                tags: ["日内", "趋势跟随", "RB"],
                createdAt: now.addingTimeInterval(-60 * 60 * 2),
                updatedAt: now.addingTimeInterval(-60 * 60 * 1)
            ),
            TradeJournal(
                tradeIDs: ifIDs,
                title: "IF2509 日间持仓 · 周线 KDJ 顶背离试空",
                reason: "周线 KDJ 顶背离 · 试空头 · 准备放到下周",
                emotion: .hesitant,
                deviation: .earlyExit,
                lesson: "提前止盈错过后续 50 点跌幅 · 信号确认不应过早离场",
                tags: ["日间", "KDJ", "IF"],
                createdAt: now.addingTimeInterval(-86400),
                updatedAt: now.addingTimeInterval(-86400)
            ),
            TradeJournal(
                tradeIDs: auIDs,
                title: "AU 长线 · 二次加仓追高",
                reason: "金价突破 615 + 美元指数走弱 · 加仓",
                emotion: .greedy,
                deviation: .chaseHigh,
                lesson: "追高位置太高 · 总盈亏好但加仓段亏 · 控制加仓节奏",
                tags: ["长线", "追高", "AU"],
                createdAt: now.addingTimeInterval(-86400 * 3),
                updatedAt: now.addingTimeInterval(-86400 * 2)
            ),
            TradeJournal(
                tradeIDs: cuIDs,
                title: "CU 手动录入 · 仓位试错",
                reason: "突破 78600 整数关 · 试多 1 手验证",
                emotion: .calm,
                deviation: .asPlanned,
                lesson: "仓位 1 手风险可控 · 验证后续可加",
                tags: ["试仓", "整数关", "CU"],
                createdAt: now.addingTimeInterval(-60 * 30),
                updatedAt: now.addingTimeInterval(-60 * 30)
            ),
            TradeJournal(
                tradeIDs: allIDs,
                title: "周复盘 · 4 月第 4 周",
                reason: "4 合约 13 笔成交 · 主要在 IF 提前离场损失明显",
                emotion: .calm,
                deviation: .other,
                lesson: "下周计划：减少 IF 操作 · 专注 RB 日内 · 控制频次",
                tags: ["周复盘", "总结"],
                createdAt: now.addingTimeInterval(-86400 / 2),
                updatedAt: now.addingTimeInterval(-86400 / 2)
            )
        ]
    }
}

#endif
