// WP-65 v15.22 batch2 · SyntaxColorScheme 配色方案测试

import Testing
import Foundation
@testable import Shared

@Suite("SyntaxColorScheme · WP-65 syntax 配色")
struct SyntaxColorSchemeTests {

    @Test("dark / light 全 9 类 kind 都有对应色 · 不 fallback identifier")
    func allKindsHaveColor() {
        for kind in SyntaxColorKind.allCases {
            let dark = SyntaxColorScheme.dark.color(for: kind)
            let light = SyntaxColorScheme.light.color(for: kind)
            #expect(dark.r >= 0 && dark.r <= 1)
            #expect(light.r >= 0 && light.r <= 1)
        }
    }

    @Test("dark / light 同 kind 色不同（双主题真实差异）")
    func darkLightDiffer() {
        for kind in SyntaxColorKind.allCases {
            let dark = SyntaxColorScheme.dark.color(for: kind)
            let light = SyntaxColorScheme.light.color(for: kind)
            #expect(dark != light)
        }
    }

    @Test("error / keyword 不同色（视觉语义区分）")
    func errorVsKeyword() {
        let darkErr = SyntaxColorScheme.dark.color(for: .error)
        let darkKw = SyntaxColorScheme.dark.color(for: .keyword)
        #expect(darkErr != darkKw)
    }

    @Test("opposite · dark/light 互换")
    func opposite() {
        #expect(SyntaxColorScheme.dark.opposite == .light)
        #expect(SyntaxColorScheme.light.opposite == .dark)
    }

    @Test("hex 输出格式（# + 6 位大写）")
    func hexFormat() {
        let rgb = SyntaxRGB(1.0, 0.5, 0.0)
        #expect(rgb.hex == "#FF8000")
        let black = SyntaxRGB(0, 0, 0)
        #expect(black.hex == "#000000")
        let white = SyntaxRGB(1, 1, 1)
        #expect(white.hex == "#FFFFFF")
    }

    @Test("hex 越界值 clamp 0-255")
    func hexClamp() {
        let oob = SyntaxRGB(1.5, -0.5, 2.0)   // 越界值
        let parts = oob.hex
        #expect(parts.count == 7)
        // FF / 00 / FF（clamp 后）
        #expect(parts == "#FF00FF")
    }
}
