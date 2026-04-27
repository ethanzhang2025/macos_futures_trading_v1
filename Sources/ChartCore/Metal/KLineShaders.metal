// ChartCore · WP-20 K 线 MSL Shader（reference 文件 · Package.swift exclude · 不参与编译）
//
// 实际运行时 shader 通过 KLineShaderSource.metalSourceCode 内嵌字符串
// device.makeLibrary(source:options:) 在 Mac 端运行时编译。
//
// 本文件存在的唯一目的：
// 1. Xcode 打开时享受 Metal 语法高亮 / 错误检查
// 2. 修改时与 KLineShaderSource.swift 内嵌字符串保持同步
// 3. WP-40 完整图表引擎升级时直接迁移为 .process resource

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
