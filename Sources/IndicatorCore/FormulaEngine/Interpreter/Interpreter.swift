import Foundation

/// 解释器错误
public struct InterpreterError: Error, Sendable, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

/// 指标计算结果（一条输出线）
public struct IndicatorLine: Sendable {
    public let name: String
    public let values: [Decimal?]
    public let attributes: [String]

    public init(name: String, values: [Decimal?], attributes: [String]) {
        self.name = name
        self.values = values
        self.attributes = attributes
    }
}

/// 公式解释器 — 对K线序列执行公式计算
public struct Interpreter: Sendable {
    /// 内置函数注册表
    private let builtinFunctions: [String: BuiltinFunction]

    public init(builtinFunctions: [String: BuiltinFunction] = BuiltinFunctions.all) {
        self.builtinFunctions = builtinFunctions
    }

    /// 执行公式，返回所有输出线
    public func execute(formula: Formula, bars: [BarData]) throws -> [IndicatorLine] {
        var context = ExecutionContext(bars: bars)
        var outputs: [IndicatorLine] = []

        for statement in formula.statements {
            guard case .assignment(let name, let isOutput, let expr, let attrs) = statement else {
                continue
            }

            let values = try evaluateSeries(expr: expr, context: &context)
            context.variables[name] = values

            if isOutput && !name.hasPrefix("_EXPR_") {
                outputs.append(IndicatorLine(name: name, values: values, attributes: attrs))
            }
        }

        return outputs
    }

    /// 对每根K线计算表达式，返回序列
    private func evaluateSeries(expr: ASTNode, context: inout ExecutionContext) throws -> [Decimal?] {
        let count = context.bars.count
        switch expr {
        case .number(let value):
            return Array(repeating: value, count: count)

        case .string:
            return Array(repeating: nil, count: count)

        case .variable(let name):
            // 用户定义的中间变量优先（lexical scoping · 用户 V: 应能 shadow VOLUME）
            // 修复 bug：原顺序 builtin 优先导致 V/C/O/H/L/S 等单字符变量被遮蔽
            // （如 V:VARIANCE(CLOSE,20); DIFF:V-X 中的 V 实际取 VOLUME 而非 VARIANCE 结果）
            if let series = context.variables[name] {
                return series
            }
            // 内置行情变量
            if let series = context.getBuiltinSeries(name) {
                return series
            }
            throw InterpreterError(message: "未定义的变量: \(name)")

        case .functionCall(let name, let args):
            guard let fn = builtinFunctions[name] else {
                throw InterpreterError(message: "未定义的函数: \(name)")
            }
            let argSeries = try args.map { try evaluateSeries(expr: $0, context: &context) }
            return try fn.execute(args: argSeries, bars: context.bars)

        case .binaryOp(let op, let left, let right):
            let leftVals = try evaluateSeries(expr: left, context: &context)
            let rightVals = try evaluateSeries(expr: right, context: &context)
            return try applyBinaryOp(op: op, left: leftVals, right: rightVals)

        case .unaryOp(let op, let operand):
            let vals = try evaluateSeries(expr: operand, context: &context)
            return applyUnaryOp(op: op, values: vals)

        case .assignment:
            throw InterpreterError(message: "赋值语句不能作为表达式")
        }
    }

    private func applyBinaryOp(op: BinaryOperator, left: [Decimal?], right: [Decimal?]) throws -> [Decimal?] {
        let count = max(left.count, right.count)
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let l = i < left.count ? left[i] : nil,
                  let r = i < right.count ? right[i] : nil else { continue }
            switch op {
            case .add:          result[i] = l + r
            case .subtract:     result[i] = l - r
            case .multiply:     result[i] = l * r
            case .divide:       result[i] = r != 0 ? divideDecimal(l, r) : nil
            case .modulo:       result[i] = r != 0 ? moduloDecimal(l, r) : nil
            case .equal:        result[i] = l == r ? 1 : 0
            case .notEqual:     result[i] = l != r ? 1 : 0
            case .greaterThan:  result[i] = l > r ? 1 : 0
            case .lessThan:     result[i] = l < r ? 1 : 0
            case .greaterEqual: result[i] = l >= r ? 1 : 0
            case .lessEqual:    result[i] = l <= r ? 1 : 0
            case .and:          result[i] = (l != 0 && r != 0) ? 1 : 0
            case .or:           result[i] = (l != 0 || r != 0) ? 1 : 0
            }
        }
        return result
    }

    private func applyUnaryOp(op: UnaryOperator, values: [Decimal?]) -> [Decimal?] {
        values.map { v in
            guard let v else { return nil }
            switch op {
            case .negate: return -v
            case .not:    return v == 0 ? Decimal(1) : Decimal(0)
            }
        }
    }

    private func divideDecimal(_ a: Decimal, _ b: Decimal) -> Decimal {
        var result = a / b
        var rounded = Decimal()
        NSDecimalRound(&rounded, &result, 8, .plain)
        return rounded
    }

    /// v15.16 hotfix #16：quotient 超 Int 范围时 NSDecimalNumber 截断行为是 platform-defined（64-bit Mac 是 Int64.min 巨大反符号）· 整公式静默错
    /// 修：超 Int.max 走 Decimal floor 路径 · `truncated = quotient.rounded(.down)` 全 Decimal 计算 · 不依赖 Int 转换
    private func moduloDecimal(_ a: Decimal, _ b: Decimal) -> Decimal {
        let quotient = divideDecimal(a, b)
        // 范围内走 Int 截断（快路径）· 超界走 Decimal 截断（慢但正确）
        if quotient >= Decimal(Int.min) && quotient <= Decimal(Int.max) {
            let truncated = Decimal(Int(truncating: quotient as NSDecimalNumber))
            return a - truncated * b
        }
        var truncated = Decimal()
        var raw = quotient
        NSDecimalRound(&truncated, &raw, 0, .down)  // 向 0 截断（floor for positive · ceil for negative）
        return a - truncated * b
    }
}

/// 执行上下文
struct ExecutionContext {
    let bars: [BarData]
    var variables: [String: [Decimal?]] = [:]

    func getBuiltinSeries(_ name: String) -> [Decimal?]? {
        switch name {
        case "CLOSE", "C": return bars.map { $0.close as Decimal? }
        case "OPEN", "O":  return bars.map { $0.open as Decimal? }
        case "HIGH", "H":  return bars.map { $0.high as Decimal? }
        case "LOW", "L":   return bars.map { $0.low as Decimal? }
        case "VOL", "V", "VOLUME": return bars.map { Decimal($0.volume) as Decimal? }
        case "AMOUNT":     return bars.map { $0.amount as Decimal? }
        case "OPI", "OPENINTEREST": return bars.map { $0.openInterest as Decimal? }
        default: return nil
        }
    }
}

/// K线数据（公式引擎使用的简化版本）
public struct BarData: Sendable {
    public let open: Decimal
    public let high: Decimal
    public let low: Decimal
    public let close: Decimal
    public let volume: Int
    public let amount: Decimal
    public let openInterest: Decimal

    public init(open: Decimal, high: Decimal, low: Decimal, close: Decimal,
                volume: Int, amount: Decimal = 0, openInterest: Decimal = 0) {
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
        self.amount = amount
        self.openInterest = openInterest
    }
}
