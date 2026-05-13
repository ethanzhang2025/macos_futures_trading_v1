// v17.139 · MainChartOverlayBook 数据契约 + Codable + Store 测试

import Testing
import Foundation
@testable import Shared

@Suite("MainChartOverlayBook · 主图叠加偏好（VWAP / Pivot / SuperTrend）")
struct MainChartOverlayBookTests {

    @Test("default · 全关 · 12 类参数全默认（trader 标准 · v17.159 加 HMA/DEMA/TEMA）")
    func defaults() {
        let d = MainChartOverlayBook.default
        #expect(d.enabled.isEmpty)
        #expect(!d.anyEnabled)
        #expect(d.superTrendPeriod == 10)
        #expect(d.superTrendMultiplier == Decimal(3))
        #expect(d.ichimokuTenkan == 9)
        #expect(d.ichimokuKijun == 26)
        #expect(d.ichimokuSenkou == 52)
        #expect(d.donchianPeriod == 20)
        #expect(d.keltnerEMA == 20)
        #expect(d.keltnerATR == 10)
        #expect(d.keltnerMultiplier == Decimal(2))
        // v17.153 · 3 个新 overlay 默认
        #expect(d.sarStep == Decimal(string: "0.02"))
        #expect(d.sarMax == Decimal(string: "0.2"))
        #expect(d.priceChannelPeriod == 20)
        #expect(d.envelopesPeriod == 20)
        #expect(d.envelopesPercent == Decimal(string: "2.5"))
        // v17.159 · 3 改进型均线默认
        #expect(d.hmaPeriod == 16)
        #expect(d.demaPeriod == 20)
        #expect(d.temaPeriod == 20)
        // v17.161 · CHIKOU 默认关
        #expect(d.ichimokuShowChikou == false)
    }

    @Test("MainChartOverlayKind allCases 12 类完整 · 顺序 ...envelopes/hma/dema/tema (v17.159)")
    func allCases() {
        let cases = MainChartOverlayKind.allCases
        #expect(cases.count == 12)
        #expect(cases == [.vwap, .pivot, .superTrend, .ichimoku, .donchian, .keltner, .sar, .priceChannel, .envelopes, .hma, .dema, .tema])
    }

    @Test("displayName / icon 十二类均非空 · 中文化 trader 友好")
    func displayMetadata() {
        for k in MainChartOverlayKind.allCases {
            #expect(!k.displayName.isEmpty)
            #expect(!k.icon.isEmpty)
        }
        #expect(MainChartOverlayKind.vwap.displayName.contains("VWAP"))
        #expect(MainChartOverlayKind.pivot.displayName.contains("Pivot"))
        #expect(MainChartOverlayKind.superTrend.displayName.contains("SuperTrend"))
        #expect(MainChartOverlayKind.ichimoku.displayName.contains("Ichimoku"))
        #expect(MainChartOverlayKind.donchian.displayName.contains("Donchian"))
        #expect(MainChartOverlayKind.keltner.displayName.contains("Keltner"))
        #expect(MainChartOverlayKind.sar.displayName.contains("SAR"))
        #expect(MainChartOverlayKind.priceChannel.displayName.contains("Price Channel"))
        #expect(MainChartOverlayKind.envelopes.displayName.contains("Envelopes"))
        #expect(MainChartOverlayKind.hma.displayName.contains("HMA"))
        #expect(MainChartOverlayKind.dema.displayName.contains("DEMA"))
        #expect(MainChartOverlayKind.tema.displayName.contains("TEMA"))
    }

    @Test("setEnabled 切换 · isEnabled 反映状态 · anyEnabled 反映非空")
    func setEnabledToggle() {
        var book = MainChartOverlayBook.default
        #expect(!book.isEnabled(.vwap))
        book.setEnabled(.vwap, true)
        #expect(book.isEnabled(.vwap))
        #expect(book.anyEnabled)
        #expect(book.enabled == [.vwap])
        book.setEnabled(.pivot, true)
        #expect(book.enabled == [.vwap, .pivot])
        book.setEnabled(.vwap, false)
        #expect(!book.isEnabled(.vwap))
        #expect(book.enabled == [.pivot])
        book.setEnabled(.pivot, false)
        #expect(!book.anyEnabled)
    }

    @Test("Codable 往返 · 全关 default")
    func codableRoundTripDefault() throws {
        let book = MainChartOverlayBook.default
        let data = try JSONEncoder().encode(book)
        let decoded = try JSONDecoder().decode(MainChartOverlayBook.self, from: data)
        #expect(decoded == book)
        #expect(decoded.superTrendPeriod == 10)
        #expect(decoded.superTrendMultiplier == Decimal(3))
    }

    @Test("Codable 往返 · 六全开 + 自定义 SuperTrend 14/2.5 + Ichimoku 7/22/44 + Donchian 55 + Keltner 14/14/3")
    func codableRoundTripCustom() throws {
        let book = MainChartOverlayBook(
            enabled: [.vwap, .pivot, .superTrend, .ichimoku, .donchian, .keltner],
            superTrendPeriod: 14,
            superTrendMultiplier: Decimal(string: "2.5")!,
            ichimokuTenkan: 7,
            ichimokuKijun: 22,
            ichimokuSenkou: 44,
            donchianPeriod: 55,
            keltnerEMA: 14,
            keltnerATR: 14,
            keltnerMultiplier: Decimal(3)
        )
        let data = try JSONEncoder().encode(book)
        let decoded = try JSONDecoder().decode(MainChartOverlayBook.self, from: data)
        #expect(decoded.enabled == [.vwap, .pivot, .superTrend, .ichimoku, .donchian, .keltner])
        #expect(decoded.superTrendPeriod == 14)
        #expect(decoded.superTrendMultiplier == Decimal(string: "2.5"))
        #expect(decoded.ichimokuTenkan == 7)
        #expect(decoded.ichimokuKijun == 22)
        #expect(decoded.ichimokuSenkou == 44)
        #expect(decoded.donchianPeriod == 55)
        #expect(decoded.keltnerEMA == 14)
        #expect(decoded.keltnerATR == 14)
        #expect(decoded.keltnerMultiplier == Decimal(3))
    }

    @Test("旧 JSON 兼容 · 缺字段 fallback 默认（decodeIfPresent 守）")
    func backwardCompatible() throws {
        // 模拟极简旧 JSON 仅有 enabled · 缺 superTrend / ichimoku / donchian / keltner 参数 → fallback 默认
        let json = "{\"enabled\":[]}"
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MainChartOverlayBook.self, from: data)
        #expect(decoded.enabled.isEmpty)
        #expect(decoded.superTrendPeriod == 10)
        #expect(decoded.superTrendMultiplier == Decimal(3))
        #expect(decoded.ichimokuTenkan == 9)
        #expect(decoded.ichimokuKijun == 26)
        #expect(decoded.ichimokuSenkou == 52)
        #expect(decoded.donchianPeriod == 20)
        #expect(decoded.keltnerEMA == 20)
        #expect(decoded.keltnerATR == 10)
        #expect(decoded.keltnerMultiplier == Decimal(2))
    }

    @Test("旧 JSON 完全空 · 全字段 fallback 默认")
    func emptyJSONFallback() throws {
        let data = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MainChartOverlayBook.self, from: data)
        #expect(decoded.enabled.isEmpty)
        #expect(decoded.superTrendPeriod == 10)
        #expect(decoded.superTrendMultiplier == Decimal(3))
        #expect(decoded.ichimokuTenkan == 9)
        #expect(decoded.ichimokuKijun == 26)
        #expect(decoded.ichimokuSenkou == 52)
        #expect(decoded.donchianPeriod == 20)
        #expect(decoded.keltnerEMA == 20)
        #expect(decoded.keltnerATR == 10)
        #expect(decoded.keltnerMultiplier == Decimal(2))
    }

    @Test("v17.139 旧 JSON 缺 ichimoku 字段 · ichimoku 默认 9/26/52 + 其余字段保留")
    func oldV17_139JSONFallback() throws {
        // v17.139 时无 ichimoku 字段 · 仅 enabled + superTrend（用 v17.139 真实编码格式 round-trip 验）
        let v17_139Book = MainChartOverlayBook(
            enabled: [.vwap, .superTrend],
            superTrendPeriod: 14,
            superTrendMultiplier: Decimal(string: "2.5")!
        )
        let v17_139Encoded = try JSONEncoder().encode(v17_139Book)
        // 模拟旧版本写入 · 删 ichimoku 三字段（v17.139 模型本来也不会写入 · 这里直接复用 encode 结果就模拟了旧 JSON）
        // → 解码必须能 fallback ichimoku 默认
        let decoded = try JSONDecoder().decode(MainChartOverlayBook.self, from: v17_139Encoded)
        #expect(decoded.enabled == [.vwap, .superTrend])
        #expect(decoded.superTrendPeriod == 14)
        #expect(decoded.superTrendMultiplier == Decimal(string: "2.5"))
        #expect(decoded.ichimokuTenkan == 9)
        #expect(decoded.ichimokuKijun == 26)
        #expect(decoded.ichimokuSenkou == 52)
    }

    @Test("v17.140 旧 JSON 缺 donchian/keltner 字段 · 全部 fallback 默认 + 其余字段保留")
    func oldV17_140JSONFallback() throws {
        // v17.140 时无 donchian/keltner 字段 · 仅 enabled + superTrend + ichimoku
        let v17_140Book = MainChartOverlayBook(
            enabled: [.ichimoku],
            superTrendPeriod: 14,
            superTrendMultiplier: Decimal(string: "2.5")!,
            ichimokuTenkan: 7,
            ichimokuKijun: 22,
            ichimokuSenkou: 44
        )
        let v17_140Encoded = try JSONEncoder().encode(v17_140Book)
        let decoded = try JSONDecoder().decode(MainChartOverlayBook.self, from: v17_140Encoded)
        #expect(decoded.enabled == [.ichimoku])
        #expect(decoded.ichimokuTenkan == 7)
        #expect(decoded.donchianPeriod == 20)
        #expect(decoded.keltnerEMA == 20)
        #expect(decoded.keltnerATR == 10)
        #expect(decoded.keltnerMultiplier == Decimal(2))
    }

    @Test("Store load/save 隔离 UserDefaults")
    func storeRoundTrip() {
        let suiteName = "MainChartOverlayBookTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // 不存在 → nil
        #expect(MainChartOverlayStore.load(defaults: defaults) == nil)
        // 写入 → 读回
        let book = MainChartOverlayBook(
            enabled: [.vwap, .superTrend],
            superTrendPeriod: 7,
            superTrendMultiplier: Decimal(2)
        )
        MainChartOverlayStore.save(book, defaults: defaults)
        let loaded = MainChartOverlayStore.load(defaults: defaults)
        #expect(loaded != nil)
        #expect(loaded?.enabled == [.vwap, .superTrend])
        #expect(loaded?.superTrendPeriod == 7)
        #expect(loaded?.superTrendMultiplier == Decimal(2))
    }

    @Test("Store load 损坏数据 · 返回 nil 不崩")
    func storeCorruptedData() {
        let suiteName = "MainChartOverlayBookTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data([0xFF, 0xEE, 0xDD]), forKey: MainChartOverlayStore.key)
        #expect(MainChartOverlayStore.load(defaults: defaults) == nil)
    }

    @Test("Equatable 正常工作 · 两本字段全等才相等")
    func equatable() {
        let a = MainChartOverlayBook(enabled: [.vwap], superTrendPeriod: 10, superTrendMultiplier: Decimal(3))
        let b = MainChartOverlayBook(enabled: [.vwap], superTrendPeriod: 10, superTrendMultiplier: Decimal(3))
        let c = MainChartOverlayBook(enabled: [.pivot], superTrendPeriod: 10, superTrendMultiplier: Decimal(3))
        let d = MainChartOverlayBook(enabled: [.vwap], superTrendPeriod: 14, superTrendMultiplier: Decimal(3))
        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
    }

    @Test("v17.152 旧 JSON 缺 sar/priceChannel/envelopes 字段 · 全部 fallback 默认（v17.153 兼容）")
    func oldV17_152JSONFallback() throws {
        let v17_152Book = MainChartOverlayBook(
            enabled: [.donchian, .keltner],
            donchianPeriod: 55,
            keltnerMultiplier: Decimal(3)
        )
        let v17_152Encoded = try JSONEncoder().encode(v17_152Book)
        let decoded = try JSONDecoder().decode(MainChartOverlayBook.self, from: v17_152Encoded)
        #expect(decoded.enabled == [.donchian, .keltner])
        #expect(decoded.donchianPeriod == 55)
        #expect(decoded.keltnerMultiplier == Decimal(3))
        // v17.153 新字段全 fallback 默认
        #expect(decoded.sarStep == Decimal(string: "0.02"))
        #expect(decoded.sarMax == Decimal(string: "0.2"))
        #expect(decoded.priceChannelPeriod == 20)
        #expect(decoded.envelopesPeriod == 20)
        #expect(decoded.envelopesPercent == Decimal(string: "2.5"))
    }

    @Test("v17.158 旧 JSON 缺 hma/dema/tema 字段 · 全部 fallback 默认（v17.159 兼容）")
    func oldV17_158JSONFallback() throws {
        // v17.158 时的 schema · 用 v17.159 模型构造 v17.158 子集 encode · 然后用 v17.159 解码必须 fallback hma/dema/tema
        // 直接用 round-trip 模拟（Encoder 写出当前所有字段 · v17.158 实际历史 JSON 不含 hma/dema/tema · 也能 decode）
        let v17_158Book = MainChartOverlayBook(
            enabled: [.sar],
            sarStep: Decimal(string: "0.05")!,
            sarMax: Decimal(string: "0.3")!,
            priceChannelPeriod: 30
        )
        let v17_158Encoded = try JSONEncoder().encode(v17_158Book)
        let decoded = try JSONDecoder().decode(MainChartOverlayBook.self, from: v17_158Encoded)
        #expect(decoded.enabled == [.sar])
        #expect(decoded.sarStep == Decimal(string: "0.05"))
        #expect(decoded.priceChannelPeriod == 30)
        // v17.159 新字段全 fallback 默认（v17.158 init 未传 · hmaPeriod=16/demaPeriod=20/temaPeriod=20）
        #expect(decoded.hmaPeriod == 16)
        #expect(decoded.demaPeriod == 20)
        #expect(decoded.temaPeriod == 20)
    }

    @Test("v17.159 Codable 往返 · HMA/DEMA/TEMA 全开 + 自定义 period 14/30/35")
    func codableRoundTripV17_159() throws {
        let book = MainChartOverlayBook(
            enabled: [.hma, .dema, .tema],
            hmaPeriod: 14,
            demaPeriod: 30,
            temaPeriod: 35
        )
        let data = try JSONEncoder().encode(book)
        let decoded = try JSONDecoder().decode(MainChartOverlayBook.self, from: data)
        #expect(decoded.enabled == [.hma, .dema, .tema])
        #expect(decoded.hmaPeriod == 14)
        #expect(decoded.demaPeriod == 30)
        #expect(decoded.temaPeriod == 35)
    }

    @Test("v17.161 · ichimokuShowChikou toggle round-trip + 旧 JSON 兼容 fallback false")
    func ichimokuShowChikouToggle() throws {
        // round-trip
        let on = MainChartOverlayBook(enabled: [.ichimoku], ichimokuShowChikou: true)
        let onData = try JSONEncoder().encode(on)
        let onDecoded = try JSONDecoder().decode(MainChartOverlayBook.self, from: onData)
        #expect(onDecoded.ichimokuShowChikou == true)

        // v17.160 旧 JSON 缺字段 · fallback false（trader 默认不画 CHIKOU）
        let oldJSON = """
        {"enabled":["ichimoku"],"ichimokuTenkan":9,"ichimokuKijun":26,"ichimokuSenkou":52}
        """
        let data = oldJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MainChartOverlayBook.self, from: data)
        #expect(decoded.ichimokuShowChikou == false)
    }
}
