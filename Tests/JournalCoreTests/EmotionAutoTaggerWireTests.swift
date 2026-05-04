// WP-53 v15.19 batch22 · JournalDraft.adopt 整合测试（UI wire 入口契约）

import Testing
import Foundation
@testable import JournalCore
import Shared

@Suite("EmotionAutoTagger.Tag · displayName + suggestedEmotion 全 6 类映射稳定")
struct EmotionAutoTaggerMappingTests {

    @Test("displayName 6 类不为空 + 不重复")
    func displayNamesUnique() {
        let names = EmotionAutoTagger.Tag.allCases.map(\.displayName)
        #expect(names.count == 6)
        #expect(Set(names).count == 6)
        #expect(!names.contains(""))
    }

    @Test("suggestedEmotion 仅落 calm/greedy/fearful 三类")
    func emotionRange() {
        let allowed: Set<JournalEmotion> = [.calm, .greedy, .fearful]
        for tag in EmotionAutoTagger.Tag.allCases {
            #expect(allowed.contains(tag.suggestedEmotion))
        }
    }

    @Test("revengeAfterLosses → fearful · overconfident → greedy（trader 心理共识对齐）")
    func keyMappings() {
        #expect(EmotionAutoTagger.Tag.revengeAfterLosses.suggestedEmotion == .fearful)
        #expect(EmotionAutoTagger.Tag.overconfident.suggestedEmotion == .greedy)
        #expect(EmotionAutoTagger.Tag.oversize.suggestedEmotion == .greedy)
        #expect(EmotionAutoTagger.Tag.lossOfControl.suggestedEmotion == .fearful)
    }
}
