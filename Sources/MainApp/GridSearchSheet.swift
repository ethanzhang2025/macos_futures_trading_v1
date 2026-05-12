// v17.44 D4 · 参数扫描 sheet（BacktestWindow "🔬 参数扫描" 入口）
//
// 设计：
// - 输入：模板（含 {N} {M} 占位）+ paramSpace（plain text · 每行 name=v1,v2,v3）
//   + metric picker（endingPnL / sharpe / winRate）
// - 算法：GridSearchEngine.run（笛卡尔积 + 模板替换 + 排序）· bars 复用 BacktestWindow mock
// - 输出：top N（默认 20）结果表 · 排名 + 参数 + 6 指标 · 双击行回填到主公式
// - v2 留：CSV 导出 / 复合 metric / 等高线图

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import IndicatorCore

struct GridSearchSheet: View {

    let bars: [BarData]
    let signalLineName: String
    let initialEquity: Double
    @Binding var isPresented: Bool
    /// 双击行回填到主公式的 callback（参数：替换后的实际公式文本）
    var onApplyFormula: (String) -> Void

    @AppStorage("gridSearch.v1.template") private var template: String = defaultTemplate
    @AppStorage("gridSearch.v1.paramSpaceText") private var paramSpaceText: String = defaultParamSpace
    @AppStorage("gridSearch.v1.metricRaw") private var metricRaw: String = MetricKind.endingPnL.rawValue
    @AppStorage("gridSearch.v1.topN") private var topN: Int = 20

    @State private var outcomes: [GridSearchOutcome] = []
    @State private var errorMessage: String?
    @State private var isRunning: Bool = false
    @State private var elapsedSeconds: Double = 0

    enum MetricKind: String, CaseIterable, Identifiable {
        case endingPnL
        case sharpe
        case winRate
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .endingPnL: return "末日 PnL"
            case .sharpe:    return "Sharpe"
            case .winRate:   return "胜率"
            }
        }
        func extract(_ r: BacktestResult) -> Double {
            switch self {
            case .endingPnL: return (r.endingPnL as NSDecimalNumber).doubleValue
            case .sharpe:    return r.sharpe
            case .winRate:   return r.winRate
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                configPanel
                    .frame(width: 360)
                Divider()
                resultArea
            }
        }
        .frame(width: 1200, height: 760)
    }

    private var header: some View {
        HStack {
            Image(systemName: "slider.horizontal.3")
                .foregroundColor(.accentColor)
            Text("🔬 参数扫描（grid search）")
                .font(.title3.bold())
            Text("· 笛卡尔积 · \(bars.count) bars 共享主窗口数据")
                .font(.callout)
                .foregroundColor(.secondary)
            Spacer()
            if !outcomes.isEmpty {
                Text("\(outcomes.count) 组 · \(String(format: "%.2fs", elapsedSeconds))")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
            Button("关闭") { isPresented = false }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    private var configPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("公式模板（{占位}）").font(.headline)
                TextEditor(text: $template)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 140)
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.4), lineWidth: 0.5))

                Text("参数空间（每行 name=v1,v2,v3）").font(.headline)
                TextEditor(text: $paramSpaceText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 100)
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.4), lineWidth: 0.5))

                Text("排序指标").font(.headline)
                Picker("", selection: Binding(
                    get: { MetricKind(rawValue: metricRaw) ?? .endingPnL },
                    set: { metricRaw = $0.rawValue }
                )) {
                    ForEach(MetricKind.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack {
                    Text("结果 top N").font(.callout).foregroundColor(.secondary)
                    Stepper(value: $topN, in: 5...200, step: 5) {
                        Text("\(topN)").font(.callout.monospaced())
                    }
                }

                Divider()

                Button(action: runSearch) {
                    HStack {
                        if isRunning {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(isRunning ? "扫描中…" : "运行参数扫描").font(.callout.bold())
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isRunning)

                if let err = errorMessage {
                    Text(err).font(.caption).foregroundColor(.red)
                }

                if let combos = combinationCountText {
                    Text(combos).font(.caption).foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(12)
        }
    }

    private var combinationCountText: String? {
        let space = parseParamSpace(paramSpaceText)
        guard !space.isEmpty else { return nil }
        let total = space.reduce(1) { $0 * $1.values.count }
        return "组合数：\(total)（\(space.map { "\($0.name)=\($0.values.count)" }.joined(separator: " × "))）"
    }

    private var resultArea: some View {
        VStack(spacing: 0) {
            if outcomes.isEmpty {
                emptyResult
            } else {
                resultHeader
                resultList
            }
        }
    }

    private var emptyResult: some View {
        VStack(spacing: 12) {
            Image(systemName: "slider.horizontal.below.rectangle")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))
            Text("点击 ▶ 运行参数扫描查看结果")
                .font(.callout)
                .foregroundColor(.secondary)
            Text("默认 MA 双均线：N ∈ {5,10,15,20} × M ∈ {20,30,50} = 12 组合")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultHeader: some View {
        HStack(spacing: 0) {
            Text("#").frame(width: 36, alignment: .trailing)
            Text("参数").frame(width: 200, alignment: .leading)
            Text("末日 PnL").frame(width: 90, alignment: .trailing)
            Text("最大回撤").frame(width: 80, alignment: .trailing)
            Text("Sharpe").frame(width: 70, alignment: .trailing)
            Text("胜率").frame(width: 60, alignment: .trailing)
            Text("trades").frame(width: 60, alignment: .trailing)
            Spacer()
            Text("操作").frame(width: 80, alignment: .center)
        }
        .font(.caption2.monospaced().weight(.semibold))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08))
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(outcomes.prefix(topN).enumerated()), id: \.offset) { idx, o in
                    resultRow(rank: idx + 1, outcome: o)
                        .onTapGesture(count: 2) {
                            onApplyFormula(o.formula)
                            isPresented = false
                        }
                }
                if outcomes.count > topN {
                    Text("…还有 \(outcomes.count - topN) 组未显示（调整 top N 查看）")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    private func resultRow(rank: Int, outcome o: GridSearchOutcome) -> some View {
        let pnlD = (o.result.endingPnL as NSDecimalNumber).doubleValue
        let ddD = (o.result.maxDrawdown as NSDecimalNumber).doubleValue
        let paramsText = o.params
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(NSDecimalNumber(decimal: $0.value).stringValue)" }
            .joined(separator: " · ")
        return HStack(spacing: 0) {
            Text("\(rank)").frame(width: 36, alignment: .trailing)
                .foregroundColor(rank <= 3 ? .accentColor : .primary)
                .fontWeight(rank <= 3 ? .bold : .regular)
            Text(paramsText)
                .frame(width: 200, alignment: .leading)
                .lineLimit(1)
            Text(String(format: "%+.2f", pnlD))
                .frame(width: 90, alignment: .trailing)
                .foregroundColor(pnlD >= 0 ? .green : .red)
            Text(String(format: "%.2f", ddD))
                .frame(width: 80, alignment: .trailing)
                .foregroundColor(.red)
            Text(String(format: "%.2f", o.result.sharpe))
                .frame(width: 70, alignment: .trailing)
                .foregroundColor(o.result.sharpe >= 1 ? .green : .secondary)
            Text(String(format: "%.0f%%", o.result.winRate * 100))
                .frame(width: 60, alignment: .trailing)
                .foregroundColor(o.result.winRate >= 0.5 ? .green : .secondary)
            Text("\(o.result.trades.count)")
                .frame(width: 60, alignment: .trailing)
                .foregroundColor(.secondary)
            Spacer()
            Button("回填") {
                onApplyFormula(o.formula)
                isPresented = false
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .frame(width: 80, alignment: .center)
            .help("把这组参数对应的公式回填到主回测窗口")
        }
        .font(.caption.monospaced())
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(rank % 2 == 0 ? Color.clear : Color.secondary.opacity(0.05))
        .contentShape(Rectangle())
    }

    // MARK: - 跑扫描

    private func runSearch() {
        errorMessage = nil
        let space = parseParamSpace(paramSpaceText)
        guard !space.isEmpty else {
            errorMessage = "参数空间为空 · 请输入 name=v1,v2,v3 格式"
            return
        }
        let kind = MetricKind(rawValue: metricRaw) ?? .endingPnL
        isRunning = true
        outcomes = []
        let t0 = Date()
        Task { @MainActor in
            let results = GridSearchEngine.run(
                template: template,
                paramSpace: space,
                bars: bars,
                signalLineName: signalLineName,
                initialEquity: Decimal(initialEquity),
                metric: { kind.extract($0) }
            )
            elapsedSeconds = Date().timeIntervalSince(t0)
            outcomes = results
            isRunning = false
            if results.isEmpty {
                errorMessage = "无有效结果（所有组合编译/运行失败 · 检查模板占位与参数名是否匹配）"
            }
        }
    }

    /// 解析参数空间 · 每行 name=v1,v2,v3 · 容错处理（空行 / 缺 = / 非数值跳过）
    private func parseParamSpace(_ text: String) -> [(name: String, values: [Decimal])] {
        var result: [(name: String, values: [Decimal])] = []
        for line in text.split(whereSeparator: { $0.isNewline }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let name = String(trimmed[..<eqIdx]).trimmingCharacters(in: .whitespaces)
            let rhs = String(trimmed[trimmed.index(after: eqIdx)...])
            let values = rhs
                .split(separator: ",")
                .compactMap { Decimal(string: String($0).trimmingCharacters(in: .whitespaces)) }
            guard !name.isEmpty, !values.isEmpty else { continue }
            result.append((name: name, values: values))
        }
        return result
    }
}

// MARK: - 默认模板 / 参数空间

private let defaultTemplate: String = """
{ MA 双均线穿越（参数化）· {N} 短均线 · {M} 长均线 }
MA{N}:=MA(CLOSE,{N});
MA{M}:=MA(CLOSE,{M});
BUY:IF(MA{N}>MA{M},1,0);
"""

private let defaultParamSpace: String = """
N=5,10,15,20
M=20,30,50
"""

#endif
