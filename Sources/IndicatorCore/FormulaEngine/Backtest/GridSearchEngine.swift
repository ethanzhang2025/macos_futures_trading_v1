// v17.38 D4 · 多公式参数扫描（grid search · 找最优参数组合）
//
// 设计：
// - 输入：公式模板（含 {name} 占位）+ 参数空间 [(name, [Decimal])] + bars + metric closure
// - 算法：参数笛卡尔积 · 每组替换 → 编译 → 跑回测 → 收集 (params, result) + metric
// - 输出：按 metric 降序排列的全部结果 · 用户挑 top N
// - 失败处理：单组编译/运行失败 → 跳过（不阻塞其他组合）
//
// 注意：模板替换是简单 {name} → value 字符串拼接 · 不做表达式语义校验
//       trader 应自行确保参数值类型与位置合理（如 N 应整数 · 替换后 MA(N) 仍合法）

import Foundation

/// 单组参数 + 回测结果
public struct GridSearchOutcome: Sendable {
    public let params: [String: Decimal]
    public let formula: String                    // 替换占位后的实际公式（trader 可复制）
    public let result: BacktestResult
    public let metric: Double                     // 排序依据值

    public init(params: [String: Decimal], formula: String, result: BacktestResult, metric: Double) {
        self.params = params
        self.formula = formula
        self.result = result
        self.metric = metric
    }
}

public enum GridSearchEngine {

    /// 跑参数扫描
    /// - Parameters:
    ///   - template: 公式模板（用 `{N}` `{M}` 占位 · 大小写敏感）
    ///   - paramSpace: 参数空间（顺序按笛卡尔积外层 → 内层）· name 应与模板占位一致
    ///   - bars: 测试数据
    ///   - signalLineName: 信号输出线名（默认 "BUY"）
    ///   - initialEquity: 起始权益
    ///   - metric: 排序 closure · 返回 Double · 默认 endingPnL（trader 经验首选 net PnL）
    /// - Returns: 全部 outcomes · 按 metric 降序 · 失败组合静默跳过
    public static func run(
        template: String,
        paramSpace: [(name: String, values: [Decimal])],
        bars: [BarData],
        signalLineName: String = "BUY",
        initialEquity: Decimal = 100_000,
        metric: @Sendable (BacktestResult) -> Double = { NSDecimalNumber(decimal: $0.endingPnL).doubleValue }
    ) -> [GridSearchOutcome] {
        let combos = cartesian(paramSpace)
        var outcomes: [GridSearchOutcome] = []
        outcomes.reserveCapacity(combos.count)

        for combo in combos {
            let filled = substitute(template: template, params: combo)
            do {
                var lexer = Lexer(source: filled)
                let tokens = try lexer.tokenize()
                var parser = Parser(tokens: tokens)
                let formula = try parser.parse()
                let result = try SimpleBacktestEngine.run(
                    formula: formula, bars: bars,
                    signalLineName: signalLineName,
                    initialEquity: initialEquity
                )
                outcomes.append(GridSearchOutcome(
                    params: combo,
                    formula: filled,
                    result: result,
                    metric: metric(result)
                ))
            } catch {
                continue   // 单组失败不阻塞
            }
        }
        return outcomes.sorted { $0.metric > $1.metric }
    }

    /// 参数笛卡尔积（外层 paramSpace[0] · 内层 paramSpace[last]）
    /// 返回 [String: Decimal] · key=name · value=该组合在该 name 的取值
    /// paramSpace 空 → [[]]（含一个空 dict · 调用方按空模板跑 1 组）
    static func cartesian(_ paramSpace: [(name: String, values: [Decimal])]) -> [[String: Decimal]] {
        guard !paramSpace.isEmpty else { return [[:]] }
        var result: [[String: Decimal]] = [[:]]
        for (name, values) in paramSpace {
            var next: [[String: Decimal]] = []
            next.reserveCapacity(result.count * values.count)
            for partial in result {
                for v in values {
                    var copy = partial
                    copy[name] = v
                    next.append(copy)
                }
            }
            result = next
        }
        return result
    }

    /// 模板占位替换 · `{name}` → 该 name 对应 Decimal 值（按 NSDecimalNumber.stringValue 序列化）
    /// name 不在 params 中保留原样不替换（容错 · trader 写错占位名时仍可调试）
    static func substitute(template: String, params: [String: Decimal]) -> String {
        var out = template
        for (name, value) in params {
            let placeholder = "{\(name)}"
            let str = NSDecimalNumber(decimal: value).stringValue
            out = out.replacingOccurrences(of: placeholder, with: str)
        }
        return out
    }
}
