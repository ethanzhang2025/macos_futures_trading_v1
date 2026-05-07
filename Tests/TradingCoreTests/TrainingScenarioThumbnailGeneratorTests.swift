// WP-54 v15.23 batch115 · 训练场景 K 线 thumbnail 生成器测试

import Testing
import Foundation
@testable import TradingCore

@Suite("TrainingScenarioThumbnailGenerator · WP-54 K 线 thumbnail 数据")
struct TrainingScenarioThumbnailGeneratorTests {

    @Test("默认 60 根 bars · 数量正确")
    func defaultCount() {
        let bars = TrainingScenarioThumbnailGenerator.bars(for: .oscillation)
        #expect(bars.count == 60)
    }

    @Test("自定义 count · 数量正确 · count=0 返回空")
    func customCount() {
        #expect(TrainingScenarioThumbnailGenerator.bars(for: .uptrend, count: 30).count == 30)
        #expect(TrainingScenarioThumbnailGenerator.bars(for: .uptrend, count: 0).isEmpty)
    }

    @Test("OHLC 自洽：high ≥ max(o,c) · low ≤ min(o,c)")
    func ohlcConsistent() {
        for pattern in TrainingScenarioPattern.allCases {
            let bars = TrainingScenarioThumbnailGenerator.bars(for: pattern, seed: 12345)
            for bar in bars {
                #expect(bar.high >= max(bar.open, bar.close), "\(pattern) high 异常")
                #expect(bar.low  <= min(bar.open, bar.close), "\(pattern) low 异常")
            }
        }
    }

    @Test("确定性：相同 pattern + seed → 完全相同输出")
    func deterministic() {
        let a = TrainingScenarioThumbnailGenerator.bars(for: .vReversal, seed: 42)
        let b = TrainingScenarioThumbnailGenerator.bars(for: .vReversal, seed: 42)
        #expect(a == b)
    }

    @Test("不同 seed → 输出不同（noise 起作用）")
    func differentSeedDiffOutput() {
        let a = TrainingScenarioThumbnailGenerator.bars(for: .oscillation, seed: 1)
        let b = TrainingScenarioThumbnailGenerator.bars(for: .oscillation, seed: 2)
        #expect(a != b)
    }

    @Test("uptrend 末根 close > 首根 open（确实上行）")
    func uptrendDirection() {
        let bars = TrainingScenarioThumbnailGenerator.bars(for: .uptrend, seed: 1)
        #expect(bars.last!.close > bars.first!.open + 10, "uptrend 涨幅 < 10 不像上行")
    }

    @Test("downtrend 末根 close < 首根 open（确实下行）")
    func downtrendDirection() {
        let bars = TrainingScenarioThumbnailGenerator.bars(for: .downtrend, seed: 1)
        #expect(bars.last!.close < bars.first!.open - 10, "downtrend 跌幅 < 10 不像下行")
    }

    @Test("vReversal 中间最低（V 形）")
    func vReversalShape() {
        let bars = TrainingScenarioThumbnailGenerator.bars(for: .vReversal, seed: 1)
        let mid = bars.count / 2
        let midPrice = bars[mid].close
        let firstPrice = bars[0].close
        let lastPrice = bars.last!.close
        #expect(midPrice < firstPrice, "V 中部应低于首部")
        #expect(midPrice < lastPrice, "V 中部应低于尾部")
    }

    @Test("breakout 末段涨幅 > 前段涨幅（突破特征）")
    func breakoutShape() {
        let bars = TrainingScenarioThumbnailGenerator.bars(for: .breakout, seed: 1)
        let firstHalf = bars.prefix(bars.count / 2)
        let secondHalf = bars.suffix(bars.count / 2)
        let firstRange = firstHalf.map { $0.close }.max()! - firstHalf.map { $0.close }.min()!
        let secondRange = secondHalf.map { $0.close }.max()! - secondHalf.map { $0.close }.min()!
        #expect(secondRange > firstRange * 1.5, "突破后段振幅应明显大于前段横盘")
    }

    @Test("Codable 老 JSON 兼容（无 pattern 字段 → 默认 .oscillation）")
    func codableBackwardCompat() throws {
        let json = """
        {
          "id": "12345678-1234-1234-1234-123456789012",
          "name": "test",
          "instrumentID": "RB0",
          "startDate": 0,
          "endDate": 100,
          "description": "test",
          "initialBalance": 100000,
          "recommendedDurationMinutes": 60,
          "difficulty": "easy"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TrainingScenario.self, from: json)
        #expect(decoded.pattern == .oscillation)
        #expect(decoded.difficulty == .easy)
    }

    @Test("8 个内置 preset 全有 pattern 字段")
    func allPresetsHavePattern() {
        for s in TrainingScenarios.defaultPresets {
            // pattern 是非可选 · 已有值即可（编译期保证）· 这里仅断言枚举合法
            #expect(TrainingScenarioPattern.allCases.contains(s.pattern))
        }
    }
}
