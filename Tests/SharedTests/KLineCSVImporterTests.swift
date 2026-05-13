// v17.169 · KLineCSVImporter 单测
//
// 覆盖：
// - 表头 / 无表头嗅探
// - 5 种时间格式自动识别
// - 列映射（关键词匹配 / 默认顺序）
// - 错误行不中断 · 加入 errors 报告
// - 极简错误（空文件 / 无法识别时间）

import Testing
import Foundation
@testable import Shared

@Suite("v17.169 · KLineCSVImporter CSV 导入")
struct KLineCSVImporterTests {

    @Test("标准表头 · OHLCV · ISO 时间")
    func standardHeaderISO() throws {
        let csv = """
        time,open,high,low,close,volume
        2026-05-12 09:00:00,3000,3010,2995,3005,100
        2026-05-12 09:01:00,3005,3015,3000,3012,120
        """
        let r = try KLineCSVImporter.parse(csv: csv, instrumentID: "RB", period: .minute1)
        #expect(r.bars.count == 2)
        #expect(r.errors.isEmpty)
        #expect(r.detectedFormat == "yyyy-MM-dd HH:mm:ss")
        #expect(r.bars[0].open == 3000)
        #expect(r.bars[0].close == 3005)
        #expect(r.bars[0].volume == 100)
        #expect(r.bars[1].close == 3012)
    }

    @Test("无表头 · 默认列序 trader 通用")
    func headerlessDefaultOrder() throws {
        let csv = """
        2026-05-12 09:00:00,3000,3010,2995,3005,100
        2026-05-12 09:01:00,3005,3015,3000,3012,120
        """
        let r = try KLineCSVImporter.parse(csv: csv, instrumentID: "RB", period: .minute1)
        #expect(r.bars.count == 2)
        #expect(r.errors.isEmpty)
        #expect(r.bars[0].open == 3000)
    }

    @Test("Tushare 紧凑格式 yyyyMMdd HHmmss")
    func tushareFormat() throws {
        let csv = """
        20260512 090000,3000,3010,2995,3005,100
        20260512 090100,3005,3015,3000,3012,120
        """
        let r = try KLineCSVImporter.parse(csv: csv, instrumentID: "RB", period: .minute1)
        #expect(r.bars.count == 2)
        #expect(r.detectedFormat == "yyyyMMdd HHmmss")
    }

    @Test("Daily 简化格式 yyyy-MM-dd · 无 volume 列")
    func dailyOnlyOHLC() throws {
        let csv = """
        date,open,high,low,close
        2026-05-12,3000,3010,2995,3005
        2026-05-13,3005,3015,3000,3012
        """
        let r = try KLineCSVImporter.parse(csv: csv, instrumentID: "RB", period: .daily)
        #expect(r.bars.count == 2)
        #expect(r.bars[0].volume == 0)
        #expect(r.detectedFormat == "yyyy-MM-dd")
    }

    @Test("Unix timestamp · 10 位秒")
    func unixTimestamp() throws {
        let ts = Int(Date().timeIntervalSince1970)
        let csv = """
        \(ts),3000,3010,2995,3005,100
        \(ts + 60),3005,3015,3000,3012,120
        """
        let r = try KLineCSVImporter.parse(csv: csv, instrumentID: "RB", period: .minute1)
        #expect(r.bars.count == 2)
        #expect(r.detectedFormat == "UNIX")
    }

    @Test("中文表头 · 开/高/低/收/量")
    func chineseHeader() throws {
        let csv = """
        时间,开盘,最高,最低,收盘,成交量
        2026-05-12 09:00:00,3000,3010,2995,3005,100
        2026-05-12 09:01:00,3005,3015,3000,3012,120
        """
        let r = try KLineCSVImporter.parse(csv: csv, instrumentID: "RB", period: .minute1)
        #expect(r.bars.count == 2)
        #expect(r.errors.isEmpty)
        #expect(r.bars[0].open == 3000)
        #expect(r.bars[0].volume == 100)
    }

    @Test("混合错误 · 部分行不规范 · 剩余仍解析成功 + errors 报告")
    func partialErrors() throws {
        let csv = """
        time,open,high,low,close,volume
        2026-05-12 09:00:00,3000,3010,2995,3005,100
        2026-05-12 09:01:00,BADDATA,3015,3000,3012,120
        2026-05-12 09:02:00,3010,3020,3005,3015,150
        """
        let r = try KLineCSVImporter.parse(csv: csv, instrumentID: "RB", period: .minute1)
        #expect(r.bars.count == 2, "2 行有效")
        #expect(r.errors.count == 1)
        #expect(r.errors[0].contains("第 3 行"))
    }

    @Test("空 CSV · throws emptyFile")
    func emptyFile() {
        #expect(throws: KLineCSVImporter.ImportError.emptyFile) {
            _ = try KLineCSVImporter.parse(csv: "", instrumentID: "X", period: .daily)
        }
        #expect(throws: KLineCSVImporter.ImportError.emptyFile) {
            _ = try KLineCSVImporter.parse(csv: "   \n  \n  ", instrumentID: "X", period: .daily)
        }
    }

    @Test("无法识别时间格式 · throws timeFormatNotDetected")
    func unrecognizedTime() {
        let csv = """
        time,open,high,low,close
        WeirdTime,3000,3010,2995,3005
        """
        #expect(throws: KLineCSVImporter.ImportError.timeFormatNotDetected) {
            _ = try KLineCSVImporter.parse(csv: csv, instrumentID: "X", period: .daily)
        }
    }

    @Test("列数不足 · 加入 errors 不中断")
    func tooFewColumns() throws {
        let csv = """
        time,open,high,low,close
        2026-05-12,3000,3010
        2026-05-13,3005,3015,3000,3012
        """
        let r = try KLineCSVImporter.parse(csv: csv, instrumentID: "X", period: .daily)
        #expect(r.bars.count == 1)
        #expect(r.errors.count == 1)
        #expect(r.errors[0].contains("列数不足"))
    }
}
