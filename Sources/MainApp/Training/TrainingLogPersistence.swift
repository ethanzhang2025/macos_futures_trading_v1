// MainApp · WP-54 v16.15 · 训练历史 UserDefaults JSON 持久化
//
// 用途：
// - TrainingViewModel.log 跨会话保留（之前内存只 · 关掉 App 全丢）
// - ReviewWindow 月报生成时跨窗口读取（不创建第二份 ViewModel）
//
// 设计：
// - JSON 编解码失败静默回退空 log（trader 升级时不抛错）
// - 大 log 时本地写盘 ~10ms · TrainingViewModel didSet 触发 · 不占主线程

#if canImport(SwiftUI) && os(macOS)

import Foundation
import TradingCore

enum TrainingLogPersistence {

    static let userDefaultsKey = "training.session.log.v1"

    static func load() -> TrainingSessionLog {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let log = try? JSONDecoder().decode(TrainingSessionLog.self, from: data)
        else { return TrainingSessionLog() }
        return log
    }

    static func save(_ log: TrainingSessionLog) {
        guard let data = try? JSONEncoder().encode(log) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}

#endif
