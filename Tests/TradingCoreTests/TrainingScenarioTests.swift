// WP-54 v15.23 batch15 · 训练场景预设库测试

import Testing
import Foundation
@testable import TradingCore

@Suite("TrainingScenario · WP-54 训练场景预设库")
struct TrainingScenarioTests {

    @Test("默认预设非空且 ≥ 6 条")
    func defaultPresetsCount() {
        let presets = TrainingScenarios.defaultPresets
        #expect(presets.count >= 6)
        #expect(!presets.isEmpty)
    }

    @Test("覆盖 3 个难度梯度")
    func coversAllDifficulties() {
        let easy = TrainingScenarios.presets(of: .easy)
        let medium = TrainingScenarios.presets(of: .medium)
        let hard = TrainingScenarios.presets(of: .hard)
        #expect(!easy.isEmpty)
        #expect(!medium.isEmpty)
        #expect(!hard.isEmpty)
    }

    @Test("所有场景结束时间晚于开始时间")
    func endAfterStart() {
        for scenario in TrainingScenarios.defaultPresets {
            #expect(scenario.endDate > scenario.startDate, "场景 \(scenario.name) 时间反了")
        }
    }

    @Test("所有场景初始资金 > 0")
    func positiveInitialBalance() {
        for scenario in TrainingScenarios.defaultPresets {
            #expect(scenario.initialBalance > 0, "场景 \(scenario.name) 资金 ≤ 0")
        }
    }

    @Test("durationDescription 格式正确")
    func durationFormat() {
        let s = TrainingScenario(
            name: "test", instrumentID: "RB0",
            startDate: TrainingScenarios.dateFor(year: 2024, month: 1, day: 1, hour: 9, minute: 0),
            endDate:   TrainingScenarios.dateFor(year: 2024, month: 1, day: 1, hour: 11, minute: 30),
            description: "", initialBalance: 100_000, recommendedDurationMinutes: 60
        )
        // 2.5 小时
        #expect(s.durationDescription == "2 小时 30 分")
    }

    @Test("durationDescription 短场景仅显示分钟")
    func durationFormatMinutesOnly() {
        let s = TrainingScenario(
            name: "test", instrumentID: "RB0",
            startDate: TrainingScenarios.dateFor(year: 2024, month: 1, day: 1, hour: 9, minute: 0),
            endDate:   TrainingScenarios.dateFor(year: 2024, month: 1, day: 1, hour: 9, minute: 45),
            description: "", initialBalance: 100_000, recommendedDurationMinutes: 30
        )
        #expect(s.durationDescription == "45 分")
    }

    @Test("按合约过滤")
    func filterByInstrument() {
        let rbScenarios = TrainingScenarios.presets(forInstrument: "RB0")
        #expect(!rbScenarios.isEmpty)
        for s in rbScenarios {
            #expect(s.instrumentID == "RB0")
        }
    }

    @Test("Difficulty emoji + displayName")
    func difficultyDisplay() {
        #expect(TrainingScenario.Difficulty.easy.displayName == "入门")
        #expect(TrainingScenario.Difficulty.medium.displayName == "中级")
        #expect(TrainingScenario.Difficulty.hard.displayName == "高级")
        #expect(TrainingScenario.Difficulty.easy.emoji == "🟢")
        #expect(TrainingScenario.Difficulty.medium.emoji == "🟡")
        #expect(TrainingScenario.Difficulty.hard.emoji == "🔴")
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = TrainingScenarios.defaultPresets.first!
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TrainingScenario.self, from: data)
        #expect(decoded == original)
    }

    @Test("场景名唯一（防重复）")
    func uniqueNames() {
        let names = TrainingScenarios.defaultPresets.map { $0.name }
        let unique = Set(names)
        #expect(unique.count == names.count, "场景名有重复")
    }
}
