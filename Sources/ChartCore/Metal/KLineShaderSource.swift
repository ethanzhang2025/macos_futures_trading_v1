// ChartCore · WP-20 K 线 MSL Shader 源码（运行时通过 device.makeLibrary(source:) 编译）
//
// 为何内嵌而非独立 .metal：
// - PoC 阶段省去 Swift Package resources 配置 · Linux 端不打包 metal 文件
// - Shader 极简（vertex 5 行 / fragment 1 行）· 可读性损失小
// - WP-40 完整图表引擎再分离到独立 .metal 资源（届时配 .process resource）
//
// 顶点契约（与 KLineVertex struct 内存布局一一对齐）：
// - position: float2 = [barIndex（逻辑 K 索引）, price（原始价 Float）]
// - color:    float4 = rgba 0..1（涨绿 / 跌红 · CPU 端预算）
//
// 矩阵契约：
// - viewMatrix [[buffer(1)]] = ortho 4×4 · CPU 端按 viewport(startIndex/visibleCount/priceRange) 构建
// - 顶点是逻辑坐标，每帧仅更新 viewMatrix · vertex buffer 仅在 K 数据变化时重建（M6 zoom/pan 60fps 关键）

import Foundation

public enum KLineShaderSource {
    public static let metalSourceCode: String = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexIn {
        float2 position [[attribute(0)]];
        float4 color    [[attribute(1)]];
    };

    struct VertexOut {
        float4 position [[position]];
        float4 color;
    };

    vertex VertexOut kline_vertex(VertexIn in [[stage_in]],
                                    constant float4x4 &viewMatrix [[buffer(1)]]) {
        VertexOut out;
        out.position = viewMatrix * float4(in.position.x, in.position.y, 0.0, 1.0);
        out.color = in.color;
        return out;
    }

    fragment float4 kline_fragment(VertexOut in [[stage_in]]) {
        return in.color;
    }
    """

    /// vertex function 名（Pipeline 构建用）
    public static let vertexFunctionName = "kline_vertex"
    /// fragment function 名
    public static let fragmentFunctionName = "kline_fragment"
}
