import SwiftUI

/// 所有指标参数统一配置
struct IndicatorParams: Codable, Equatable {
    // MA
    var maPeriods: [Int] = [5, 10, 20, 60]
    var maEnabled: [Bool] = [true, true, true, false]

    // BOLL
    var bollPeriod: Int = 20
    var bollMultiplier: Double = 2.0

    // MACD
    var macdFast: Int = 12
    var macdSlow: Int = 26
    var macdSignal: Int = 9

    // KDJ
    var kdjN: Int = 9
    var kdjM1: Int = 3
    var kdjM2: Int = 3

    // RSI
    var rsiPeriods: [Int] = [6, 14, 24]

    static let `default` = IndicatorParams()

    /// 持久化
    static func load() -> IndicatorParams {
        if let data = UserDefaults.standard.data(forKey: "indicatorParams"),
           let params = try? JSONDecoder().decode(IndicatorParams.self, from: data) {
            return params
        }
        return .default
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "indicatorParams")
        }
    }
}
