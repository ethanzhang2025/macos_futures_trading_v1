// WP-41 · BOLL · 布林带（波动率 / 通道类）
// 参数：period（20）/ k（2，标准差倍数）
// 公式：
//   MID   = MA(close, N)
//   UPPER = MID + k * StdDev(close, N)
//   LOWER = MID - k * StdDev(close, N)
//
// WP-41 v2 commit 3/4：BOLL 实现 IncrementalIndicator · ring buffer + 滑动 sum · stddev 用 ring 数据 reduce
//                       per step：O(1) sum 增量更新 + O(N) stddev 遍历 ring · 总 O(N) 远快于全量 calculate O(N²)

import Foundation
import Shared

public enum BOLL: Indicator {
    public static let identifier = "BOLL"
    public static let category: IndicatorCategory = .volatility
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 20, minValue: 2, maxValue: 500),
        IndicatorParameter(name: "k", defaultValue: 2, minValue: 1, maxValue: 10)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        guard params.count >= 2 else {
            throw IndicatorError.invalidParameter("BOLL 需要 2 个参数（period / k）")
        }
        let n = intValue(params[0])
        let k = params[1]
        guard n >= 2, k > 0 else {
            throw IndicatorError.invalidParameter("BOLL 参数非法: period=\(n) k=\(k)")
        }

        let mid = Kernels.ma(kline.closes, period: n)
        let sd = Kernels.stddev(kline.closes, period: n)
        let count = kline.count

        var upper = [Decimal?](repeating: nil, count: count)
        var lower = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if let m = mid[i], let s = sd[i] {
                upper[i] = Kernels.round8(m + k * s)
                lower[i] = Kernels.round8(m - k * s)
            }
        }
        return [
            IndicatorSeries(name: "BOLL-MID", values: mid),
            IndicatorSeries(name: "BOLL-UPPER", values: upper),
            IndicatorSeries(name: "BOLL-LOWER", values: lower)
        ]
    }
}

// MARK: - WP-41 v2 commit 3/4 · BOLL 增量 API

extension BOLL: IncrementalIndicator {

    /// state：ring buffer 存最近 period 个 close · sum 滑动累计 · stddev 时遍历 ring 计算
    public struct IncrementalState: Sendable {
        public let period: Int
        public let k: Decimal
        public var ring: [Decimal]
        public var head: Int
        public var count: Int
        public var sum: Decimal
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        let (n, k) = try Self.requireParams(params)
        let closes = kline.closes
        // 取 history 末尾 ≤ n 个 close 装入 ring · 重建 sum 与 calculate() 末值一致（与 MA 同模式）
        let startIdx = max(0, closes.count - n)
        var ring = [Decimal](repeating: Decimal(0), count: n)
        var head = 0
        var count = 0
        var sum = Decimal(0)
        for v in closes[startIdx...] {
            ring[head] = v
            head = (head + 1) % n
            count = min(count + 1, n)
            sum += v
        }
        return IncrementalState(period: n, k: k, ring: ring, head: head, count: count, sum: sum)
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        // ring 满 → 减旧值；未满 → count++
        if state.count == state.period {
            state.sum -= state.ring[state.head]
        } else {
            state.count += 1
        }
        state.ring[state.head] = newBar.close
        state.head = (state.head + 1) % state.period
        state.sum += newBar.close

        guard state.count == state.period else { return [nil, nil, nil] }

        // calculate() 中 mid[i] = round8(sum/n) · sd[i] = round8(sqrt(variance)) · upper/lower 用 round 后的 mid/sd
        // 增量必须 round8 snapshot 与之对齐 · variance 用 raw mean（与 Kernels.stddev 算法一致）
        let nDec = Decimal(state.period)
        let midRaw = state.sum / nDec
        let variance = state.ring.reduce(Decimal(0)) { acc, x in
            let d = x - midRaw
            return acc + d * d
        } / nDec
        let sdRaw = Decimal(NSDecimalNumber(decimal: variance).doubleValue.squareRoot())

        let mid = Kernels.round8(midRaw)
        let sd = Kernels.round8(sdRaw)
        let upper = Kernels.round8(mid + state.k * sd)
        let lower = Kernels.round8(mid - state.k * sd)
        return [mid, upper, lower]
    }

    /// 共享参数校验（calculate / makeIncrementalState 都用）
    fileprivate static func requireParams(_ params: [Decimal]) throws -> (n: Int, k: Decimal) {
        guard params.count >= 2 else {
            throw IndicatorError.invalidParameter("BOLL 需要 2 个参数（period / k）")
        }
        let n = intValue(params[0])
        let k = params[1]
        guard n >= 2, k > 0 else {
            throw IndicatorError.invalidParameter("BOLL 参数非法: period=\(n) k=\(k)")
        }
        return (n, k)
    }
}
