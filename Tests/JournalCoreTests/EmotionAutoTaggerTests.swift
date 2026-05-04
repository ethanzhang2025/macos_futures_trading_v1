// WP-53 v15.19 batch21 · 自动情绪 / 标签建议测试
// 覆盖：单笔阈值（复仇 / 得意 / 豪赌 / 失控 / 短炒 / 长持）+ 批量 tagAll streak/avg 推进

import Testing
import Foundation
@testable import JournalCore
import Shared

@Suite("EmotionAutoTagger · 自动情绪 / 标签建议 v15.19 batch21")
struct EmotionAutoTaggerTests {

    private func position(_ pnl: Decimal, holdingSec: TimeInterval = 600,
                          at offsetSec: TimeInterval = 0) -> ClosedPosition {
        let closeTime = Date(timeIntervalSince1970: 1_700_000_000 + offsetSec)
        return ClosedPosition(
            instrumentID: "rb2501", side: .long,
            openTradeID: UUID(), closeTradeID: UUID(),
            openTime: closeTime.addingTimeInterval(-holdingSec),
            closeTime: closeTime,
            openPrice: 3500, closePrice: 3500 + pnl,
            volume: 1, realizedPnL: pnl, totalCommission: 0
        )
    }

    @Test("空 context · 单笔无标签")
    func neutral() {
        let p = position(100)
        #expect(EmotionAutoTagger.tags(for: p, context: .init()).isEmpty)
    }

    @Test("priorStreak ≤ -3 · 单笔标 revengeAfterLosses")
    func revenge() {
        let ctx = EmotionAutoTagger.Context(priorStreak: -3)
        let tags = EmotionAutoTagger.tags(for: position(100), context: ctx)
        #expect(tags.contains(.revengeAfterLosses))
    }

    @Test("priorStreak ≥ 5 · 单笔标 overconfident")
    func overconfident() {
        let ctx = EmotionAutoTagger.Context(priorStreak: 5)
        let tags = EmotionAutoTagger.tags(for: position(100), context: ctx)
        #expect(tags.contains(.overconfident))
    }

    @Test("单笔盈利 > avgWin × 3 · 标 oversize")
    func oversizeWin() {
        let ctx = EmotionAutoTagger.Context(avgWin: 100, avgLoss: 0)
        let tags = EmotionAutoTagger.tags(for: position(400), context: ctx)
        #expect(tags.contains(.oversize))
    }

    @Test("单笔亏损 > avgLoss × 3 · 标 lossOfControl")
    func lossOfControl() {
        let ctx = EmotionAutoTagger.Context(avgWin: 0, avgLoss: 100)
        let tags = EmotionAutoTagger.tags(for: position(-400), context: ctx)
        #expect(tags.contains(.lossOfControl))
    }

    @Test("avgWin/avgLoss = 0 时不抛 oversize/lossOfControl（避免冷启动误警）")
    func zeroAvgNoFalsePositive() {
        let ctx = EmotionAutoTagger.Context()
        let tagsWin = EmotionAutoTagger.tags(for: position(10000), context: ctx)
        let tagsLoss = EmotionAutoTagger.tags(for: position(-10000), context: ctx)
        #expect(!tagsWin.contains(.oversize))
        #expect(!tagsLoss.contains(.lossOfControl))
    }

    @Test("持仓 < 60s · 标 scalp")
    func scalp() {
        let p = position(50, holdingSec: 30)
        let tags = EmotionAutoTagger.tags(for: p, context: .init())
        #expect(tags.contains(.scalp))
    }

    @Test("持仓 > 7 天 · 标 heldTooLong")
    func heldTooLong() {
        let p = position(500, holdingSec: 8 * 86_400)
        let tags = EmotionAutoTagger.tags(for: p, context: .init())
        #expect(tags.contains(.heldTooLong))
    }

    @Test("Tag.suggestedEmotion 不抛错 · 全 6 类有映射")
    func emotionMapping() {
        for tag in EmotionAutoTagger.Tag.allCases {
            // 仅校验不崩 · 具体映射见实现
            _ = tag.suggestedEmotion
            #expect(!tag.displayName.isEmpty)
        }
    }

    @Test("tagAll · 3 连败后第 4 笔标 revengeAfterLosses")
    func tagAllRevenge() {
        let positions = [
            position(-100, at: 0),
            position(-100, at: 60),
            position(-100, at: 120),
            position(50, at: 180)   // 第 4 笔 · 前置 streak = -3 · 应标 revenge
        ]
        let result = EmotionAutoTagger.tagAll(positions)
        #expect(result.count == 4)
        #expect(!result[0].tags.contains(.revengeAfterLosses))   // 首笔 streak=0
        #expect(result[3].tags.contains(.revengeAfterLosses))
    }

    @Test("tagAll · 5 连胜后第 6 笔标 overconfident")
    func tagAllOverconfident() {
        var positions: [ClosedPosition] = []
        for i in 0..<5 { positions.append(position(100, at: TimeInterval(i * 60))) }
        positions.append(position(100, at: 5 * 60))
        let result = EmotionAutoTagger.tagAll(positions)
        #expect(result.count == 6)
        #expect(result[5].tags.contains(.overconfident))
    }

    @Test("tagAll · avgWin 累积更新 · 第 N 笔豪赌阈值生效")
    func tagAllOversize() {
        // 前 3 笔 win=100 · 第 4 笔 win=400 → avgWin=100 · 400 > 300 ✓ oversize
        let positions = [
            position(100, at: 0),
            position(100, at: 60),
            position(100, at: 120),
            position(400, at: 180)
        ]
        let result = EmotionAutoTagger.tagAll(positions)
        #expect(result[3].tags.contains(.oversize))
        #expect(!result[2].tags.contains(.oversize))   // 第 3 笔 avgWin=100 · 100 不 > 300
    }

    @Test("tagAll · 平交易（PnL=0）跳过 streak 推进 · 不破坏连败计数")
    func tagAllBreakevenSkipped() {
        // 连败 2 笔 → 平 1 笔 → 连败 1 笔 → 第 5 笔（前置 streak=-3）
        let positions = [
            position(-100, at: 0),
            position(-100, at: 60),
            position(0, at: 120),       // 平 · 不影响 streak
            position(-100, at: 180),
            position(50, at: 240)
        ]
        let result = EmotionAutoTagger.tagAll(positions)
        #expect(result[4].tags.contains(.revengeAfterLosses))
    }

    @Test("tagAll · 输入乱序 · 内部按 closeTime 升序统计")
    func tagAllUnordered() {
        let positions = [
            position(-100, at: 60),
            position(-100, at: 180),
            position(-100, at: 0),
            position(50, at: 240)
        ]
        let result = EmotionAutoTagger.tagAll(positions)
        // 输出按内部排序顺序 · result[3] = closeTime=240 · 前置 streak=-3
        let last = result.last
        #expect(last?.tags.contains(.revengeAfterLosses) == true)
    }
}
