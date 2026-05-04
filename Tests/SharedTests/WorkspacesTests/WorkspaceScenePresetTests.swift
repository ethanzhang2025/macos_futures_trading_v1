// WP-55 v15.19 batch38 · WorkspaceScenePreset 单测

import Testing
import Foundation
@testable import Shared

@Suite("WorkspaceScenePreset · v15.19 batch38")
struct WorkspaceScenePresetTests {

    @Test("5 类预设 displayName + helpText 不空")
    func allLabels() {
        for p in WorkspaceScenePreset.allCases {
            #expect(!p.displayName.isEmpty)
            #expect(!p.helpText.isEmpty)
        }
    }

    @Test("watching 三周期布局 5m/15m/1h · zIndex 5m 最高")
    func watching() {
        let windows = WorkspaceScenePreset.watching.defaultWindows(instrumentID: "RB0")
        #expect(windows.count == 3)
        let periods = windows.map(\.period)
        #expect(Set(periods) == Set([.minute5, .minute15, .hour1]))
        let m5 = windows.first { $0.period == .minute5 }
        #expect(m5?.zIndex == 2)
    }

    @Test("reviewing 双周期布局 daily/weekly")
    func reviewing() {
        let windows = WorkspaceScenePreset.reviewing.defaultWindows()
        #expect(windows.count == 2)
        let periods = windows.map(\.period)
        #expect(Set(periods) == Set([.daily, .weekly]))
    }

    @Test("training 单图 minute15 默认")
    func training() {
        let windows = WorkspaceScenePreset.training.defaultWindows()
        #expect(windows.count == 1)
        #expect(windows[0].period == .minute15)
    }

    @Test("kind 映射 5 类预设到 WorkspaceTemplate.Kind")
    func kindMapping() {
        #expect(WorkspaceScenePreset.watching.kind == .inMarket)
        #expect(WorkspaceScenePreset.reviewing.kind == .postMarket)
        #expect(WorkspaceScenePreset.training.kind == .custom)
        #expect(WorkspaceScenePreset.preTrade.kind == .preMarket)
        #expect(WorkspaceScenePreset.postTrade.kind == .postMarket)
    }

    @Test("makeTemplate · name 默认用 displayName")
    func makeTemplateDefaultName() {
        let t = WorkspaceScenePreset.watching.makeTemplate()
        #expect(t.name == "盯盘")
        #expect(t.kind == .inMarket)
        #expect(!t.windows.isEmpty)
    }

    @Test("makeTemplate · 自定义 name + instrumentID")
    func makeTemplateCustom() {
        let t = WorkspaceScenePreset.preTrade.makeTemplate(name: "我的盘前", instrumentID: "IF0")
        #expect(t.name == "我的盘前")
        #expect(t.windows.allSatisfy { $0.instrumentID == "IF0" })
    }

    @Test("makeTemplate · windows 是 deep copy（不同 id）")
    func makeTemplateDeepCopy() {
        let t1 = WorkspaceScenePreset.watching.makeTemplate()
        let t2 = WorkspaceScenePreset.watching.makeTemplate()
        // 两次 make · windows id 应不同（每次 UUID）
        let ids1 = Set(t1.windows.map(\.id))
        let ids2 = Set(t2.windows.map(\.id))
        #expect(ids1.intersection(ids2).isEmpty)
    }
}
