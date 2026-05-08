// 麦语言扩展 · 第 35 批（v15.25 batch42 · 数学辅助函数）
//
// 7 个数学辅助：
//   1. POSITIVE(X)   — max(X, 0) · 取正部
//   2. NEGATIVE(X)   — min(X, 0) · 取负部
//   3. CLIP(X, lo, hi) — 双向 clamp · max(min(X, hi), lo)
//   4. HEAVISIDE(X)  — 阶跃函数 · X >= 0 ? 1 : 0
//   5. SQUARED(X)    — X²
//   6. CUBED(X)      — X³
//   7. INVERT(X)     — 1/X（X=0 时返 nil）

import Foundation

// MARK: - 1. POSITIVE

struct POSITIVEFunction: BuiltinFunction {
    let name = "POSITIVE"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "POSITIVE需要1个参数") }
        return args[0].map { v in
            guard let v else { return nil }
            return v > 0 ? v : 0
        }
    }
}

// MARK: - 2. NEGATIVE

struct NEGATIVEFunction: BuiltinFunction {
    let name = "NEGATIVE"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "NEGATIVE需要1个参数") }
        return args[0].map { v in
            guard let v else { return nil }
            return v < 0 ? v : 0
        }
    }
}

// MARK: - 3. CLIP

struct CLIPFunction: BuiltinFunction {
    let name = "CLIP"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else { throw InterpreterError(message: "CLIP需要3个参数（X, lo, hi）") }
        let source = args[0]
        guard let loV = args[1].first, let lo = loV,
              let hiV = args[2].first, let hi = hiV else {
            throw InterpreterError(message: "CLIP的lo/hi参数无效")
        }
        return source.map { v in
            guard let v else { return nil }
            if v < lo { return lo }
            if v > hi { return hi }
            return v
        }
    }
}

// MARK: - 4. HEAVISIDE

struct HEAVISIDEFunction: BuiltinFunction {
    let name = "HEAVISIDE"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "HEAVISIDE需要1个参数") }
        return args[0].map { v in
            guard let v else { return nil }
            return v >= 0 ? Decimal(1) : Decimal(0)
        }
    }
}

// MARK: - 5. SQUARED

struct SQUAREDFunction: BuiltinFunction {
    let name = "SQUARED"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "SQUARED需要1个参数") }
        return args[0].map { v in
            guard let v else { return nil }
            return v * v
        }
    }
}

// MARK: - 6. CUBED

struct CUBEDFunction: BuiltinFunction {
    let name = "CUBED"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "CUBED需要1个参数") }
        return args[0].map { v in
            guard let v else { return nil }
            return v * v * v
        }
    }
}

// MARK: - 7. INVERT

struct INVERTFunction: BuiltinFunction {
    let name = "INVERT"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "INVERT需要1个参数") }
        return args[0].map { v in
            guard let v, v != 0 else { return nil }
            return 1 / v
        }
    }
}
