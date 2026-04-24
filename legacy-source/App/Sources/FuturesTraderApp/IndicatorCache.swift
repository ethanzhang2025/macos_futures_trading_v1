import Foundation
import MarketData

/// 指标计算结果记忆化。
///
/// 目标：body 重绘（滚动、缩放、鼠标悬浮）时，只要 bars 内容不变就命中缓存，
///   避免对全局 K 线反复算 MA/BOLL。
///
/// 失效 key：合约/周期（contextID）+ bars.count + 最后一根 close 的指纹。
///   合约切换 → contextID 变；有新 bar 追加 → count 变；最后一根 in-place 更新 → lastClose 变。
@MainActor
final class IndicatorCache: ObservableObject {
    struct BOLL {
        let mid: [Double?]
        let upper: [Double?]
        let lower: [Double?]
    }

    private struct Fingerprint: Hashable {
        let contextID: String
        let count: Int
        let lastClose: Decimal
    }

    private struct MAKey: Hashable { let fp: Fingerprint; let period: Int }
    private struct BOLLKey: Hashable { let fp: Fingerprint; let period: Int; let mult: Double }

    private var closesCache: [Fingerprint: [Double]] = [:]
    private var maCache: [MAKey: [Double?]] = [:]
    private var bollCache: [BOLLKey: BOLL] = [:]

    private func fingerprint(contextID: String, bars: [SinaKLineBar]) -> Fingerprint {
        Fingerprint(contextID: contextID, count: bars.count, lastClose: bars.last?.close ?? 0)
    }

    func closes(contextID: String, bars: [SinaKLineBar]) -> [Double] {
        let fp = fingerprint(contextID: contextID, bars: bars)
        if let v = closesCache[fp] { return v }
        let v = bars.map(\.closeD)
        closesCache[fp] = v
        return v
    }

    func ma(contextID: String, bars: [SinaKLineBar], period: Int) -> [Double?] {
        let fp = fingerprint(contextID: contextID, bars: bars)
        let key = MAKey(fp: fp, period: period)
        if let v = maCache[key] { return v }
        let cs = closes(contextID: contextID, bars: bars)
        let v = Self.computeMA(cs, period: period)
        maCache[key] = v
        return v
    }

    func boll(contextID: String, bars: [SinaKLineBar], period: Int, mult: Double) -> BOLL {
        let fp = fingerprint(contextID: contextID, bars: bars)
        let key = BOLLKey(fp: fp, period: period, mult: mult)
        if let v = bollCache[key] { return v }
        let cs = closes(contextID: contextID, bars: bars)
        let v = Self.computeBOLL(cs, period: period, mult: mult)
        bollCache[key] = v
        return v
    }

    private static func computeMA(_ values: [Double], period: Int) -> [Double?] {
        var r = [Double?](repeating: nil, count: values.count)
        guard period > 0, values.count >= period else { return r }
        for i in (period - 1)..<values.count {
            r[i] = values[(i - period + 1)...i].reduce(0, +) / Double(period)
        }
        return r
    }

    private static func computeBOLL(_ closes: [Double], period: Int, mult: Double) -> BOLL {
        let count = closes.count
        var mid = [Double?](repeating: nil, count: count)
        var upper = [Double?](repeating: nil, count: count)
        var lower = [Double?](repeating: nil, count: count)
        guard period > 0, count >= period else { return BOLL(mid: mid, upper: upper, lower: lower) }
        for i in (period - 1)..<count {
            let slice = Array(closes[(i - period + 1)...i])
            let avg = slice.reduce(0, +) / Double(period)
            let variance = slice.map { ($0 - avg) * ($0 - avg) }.reduce(0, +) / Double(period)
            let std = sqrt(variance)
            mid[i] = avg
            upper[i] = avg + mult * std
            lower[i] = avg - mult * std
        }
        return BOLL(mid: mid, upper: upper, lower: lower)
    }
}
