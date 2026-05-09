// MainApp v15.14 · HUDFieldsBook 数据契约 + Codable 测试
// v15.16 hotfix #16：HUDFieldsBook 从 MainApp 移到 Shared module · 修原 commit 错误模板化"无单测"决策

import Testing
import Foundation
@testable import Shared

@Suite("HUDFieldsBook · 数据契约 + Codable")
struct HUDFieldsBookTests {

    @Test("default 仅 .debug 开（保 v15.13 之前行为）")
    func defaults() {
        let d = HUDFieldsBook.default
        #expect(d.fields == [.debug])
        #expect(d.fields.count == 1)
    }

    @Test("HUDFieldKind allCases 10 类完整（v15.56 加 sectorInfo）")
    func allCases() {
        let cases = HUDFieldKind.allCases
        #expect(cases.count == 10)
        #expect(cases.contains(.ohlc))
        #expect(cases.contains(.change))
        #expect(cases.contains(.amplitude))
        #expect(cases.contains(.volume))
        #expect(cases.contains(.volumeRatio))
        #expect(cases.contains(.openInterest))
        #expect(cases.contains(.atr))
        #expect(cases.contains(.timestamp))
        #expect(cases.contains(.sectorInfo))
        #expect(cases.contains(.debug))
    }

    @Test("displayOrder 与 ChartScene HUD 渲染顺序对齐（v15.56 sectorInfo 跟 atr 后 / debug 前）")
    func displayOrder() {
        let order = HUDFieldKind.displayOrder
        #expect(order == [
            .timestamp, .ohlc, .change, .amplitude,
            .volume, .volumeRatio, .openInterest, .atr, .sectorInfo, .debug
        ])
        #expect(Set(order) == Set(HUDFieldKind.allCases))  // 不漏 / 不重
    }

    @Test("displayName 全 10 类中文化（v15.56 加 sectorInfo）")
    func displayNames() {
        #expect(HUDFieldKind.ohlc.displayName.contains("OHLC"))
        #expect(HUDFieldKind.change.displayName == "涨跌幅")
        #expect(HUDFieldKind.amplitude.displayName.contains("振幅"))
        #expect(HUDFieldKind.volume.displayName == "成交量")
        #expect(HUDFieldKind.volumeRatio.displayName.contains("量比"))
        #expect(HUDFieldKind.openInterest.displayName == "持仓量")
        #expect(HUDFieldKind.atr.displayName.contains("ATR"))
        #expect(HUDFieldKind.timestamp.displayName == "时间戳")
        #expect(HUDFieldKind.sectorInfo.displayName.contains("板块"))
        #expect(HUDFieldKind.debug.displayName.contains("调试"))
    }

    @Test("v15.20 batch54 新字段 Codable round-trip 兼容旧 JSON（缺新字段 fallback 不影响）")
    func batch54NewFieldsRoundTrip() throws {
        let book = HUDFieldsBook(fields: [.atr, .amplitude, .volumeRatio, .debug])
        let data = try JSONEncoder().encode(book)
        let decoded = try JSONDecoder().decode(HUDFieldsBook.self, from: data)
        #expect(decoded.fields == [.atr, .amplitude, .volumeRatio, .debug])
        // rawValue 字符串稳定（用 atr/amplitude/volumeRatio · 兼容未来反序列化）
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("atr") && json.contains("amplitude") && json.contains("volumeRatio"))
    }

    @Test("default 不含 v15.20 新字段（保 v15.13+ 行为：仅 .debug）")
    func defaultExcludesNewFields() {
        let d = HUDFieldsBook.default
        #expect(!d.fields.contains(.atr))
        #expect(!d.fields.contains(.amplitude))
        #expect(!d.fields.contains(.volumeRatio))
    }

    @Test("Codable 往返 · 6 字段全开")
    func codableRoundTripFull() throws {
        let book = HUDFieldsBook(fields: Set(HUDFieldKind.allCases))
        let data = try JSONEncoder().encode(book)
        let decoded = try JSONDecoder().decode(HUDFieldsBook.self, from: data)
        #expect(decoded.fields == book.fields)
    }

    @Test("Codable 往返 · 空集（全不选）")
    func codableRoundTripEmpty() throws {
        let book = HUDFieldsBook(fields: [])
        let data = try JSONEncoder().encode(book)
        let decoded = try JSONDecoder().decode(HUDFieldsBook.self, from: data)
        #expect(decoded.fields == [])
    }

    @Test("Codable 往返 · 默认 [.debug]")
    func codableRoundTripDefault() throws {
        let book = HUDFieldsBook.default
        let data = try JSONEncoder().encode(book)
        let decoded = try JSONDecoder().decode(HUDFieldsBook.self, from: data)
        #expect(decoded.fields == [.debug])
    }

    @Test("HUDFieldsStore load/save · 隔离 UserDefaults")
    func storeRoundTrip() throws {
        let suiteName = "HUDFieldsBookTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        // 不存在 → load 返回 nil
        #expect(HUDFieldsStore.load(defaults: defaults) == nil)
        // 写入 → 读回
        let book = HUDFieldsBook(fields: [.ohlc, .change, .timestamp])
        HUDFieldsStore.save(book, defaults: defaults)
        let loaded = HUDFieldsStore.load(defaults: defaults)
        #expect(loaded != nil)
        #expect(loaded?.fields == [.ohlc, .change, .timestamp])
    }

    @Test("HUDFieldsStore load 损坏数据 · 返回 nil 不崩")
    func storeCorruptedData() {
        let suiteName = "HUDFieldsBookTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(Data([0x01, 0x02, 0x03, 0xFF]), forKey: HUDFieldsStore.key)
        let loaded = HUDFieldsStore.load(defaults: defaults)
        #expect(loaded == nil)  // try? 静默 fallback nil · caller 决定 default
    }

    @Test("HUDFieldsBook Equatable 正常工作（hotfix #14 多窗口同步用）")
    func equatable() {
        let a = HUDFieldsBook(fields: [.debug])
        let b = HUDFieldsBook(fields: [.debug])
        let c = HUDFieldsBook(fields: [.ohlc])
        #expect(a == b)
        #expect(a != c)
    }
}
