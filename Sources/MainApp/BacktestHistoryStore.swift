// v17.39 D5 · BacktestHistoryLog UserDefaults JSON 持久化（macOS）
//
// 用途：
// - BacktestWindow 💾 按钮 append 单条
// - ReviewWindow 月报生成时 load 拼 annex
// - JSON 解码失败静默回退空 log（升级时不抛错 · 与 TrainingLogPersistence 同模式）

#if canImport(SwiftUI) && os(macOS)

import Foundation
import IndicatorCore

enum BacktestHistoryStore {

    static let userDefaultsKey = "backtest.history.v1"

    static func load() -> BacktestHistoryLog {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let log = try? JSONDecoder().decode(BacktestHistoryLog.self, from: data)
        else { return BacktestHistoryLog() }
        return log
    }

    static func save(_ log: BacktestHistoryLog) {
        guard let data = try? JSONEncoder().encode(log) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    static func append(_ entry: BacktestHistoryEntry) {
        var log = load()
        log.entries.append(entry)
        save(log)
    }

    static func remove(id: UUID) {
        var log = load()
        log.entries.removeAll { $0.id == id }
        save(log)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}

#endif
