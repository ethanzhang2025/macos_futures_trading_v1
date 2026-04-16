import SwiftUI

/// 图表右键菜单
struct ChartContextMenu: View {
    @EnvironmentObject var vm: AppViewModel
    @Binding var mainOverlay: MainOverlay
    @Binding var chartStyle: ChartStyle

    var body: some View {
        Group {
            // 图表类型
            Menu("图表类型") {
                ForEach(ChartStyle.allCases, id: \.self) { style in
                    Button(action: { chartStyle = style }) {
                        HStack {
                            Text(style.rawValue)
                            if chartStyle == style { Image(systemName: "checkmark") }
                        }
                    }
                }
            }

            Divider()
            // 周期切换
            Menu("切换周期") {
                ForEach(["分时", "日线", "60分", "15分", "5分"], id: \.self) { period in
                    Button(action: { vm.selectPeriod(period) }) {
                        HStack {
                            Text(period)
                            if vm.selectedPeriod == period { Image(systemName: "checkmark") }
                        }
                    }
                }
            }

            Divider()

            // 主图指标
            Menu("主图指标") {
                ForEach(MainOverlay.allCases, id: \.self) { overlay in
                    Button(action: { mainOverlay = overlay }) {
                        HStack {
                            Text(overlay.rawValue)
                            if mainOverlay == overlay { Image(systemName: "checkmark") }
                        }
                    }
                }

                Divider()

                // MA线开关
                ForEach(vm.maConfig.lines.indices, id: \.self) { idx in
                    Button(action: { vm.maConfig.lines[idx].enabled.toggle() }) {
                        HStack {
                            Text("MA\(vm.maConfig.lines[idx].period)")
                            if vm.maConfig.lines[idx].enabled { Image(systemName: "checkmark") }
                        }
                    }
                }

                Divider()

                Button(action: { vm.showBoll.toggle() }) {
                    HStack {
                        Text("布林带 BOLL(20,2)")
                        if vm.showBoll { Image(systemName: "checkmark") }
                    }
                }
            }

            // 副图指标
            Menu("副图指标") {
                ForEach(SubChartType.allCases, id: \.self) { type in
                    Button(action: { vm.subChartType = type }) {
                        HStack {
                            Text(type.rawValue)
                            if vm.subChartType == type { Image(systemName: "checkmark") }
                        }
                    }
                }
            }

            Divider()

            // 绘图工具
            Menu("绘图工具") {
                Menu("线条") {
                    ForEach(DrawingToolType.lineTools, id: \.self) { tool in
                        Button(tool.rawValue) { vm.drawingState.startTool(tool) }
                    }
                }
                Menu("区域/分析") {
                    ForEach(DrawingToolType.areaTools, id: \.self) { tool in
                        Button(tool.rawValue) { vm.drawingState.startTool(tool) }
                    }
                }
                Menu("标注") {
                    ForEach(DrawingToolType.annotationTools, id: \.self) { tool in
                        Button(tool.rawValue) { vm.drawingState.startTool(tool) }
                    }
                }
                Divider()
                Button("删除选中 (Delete)") { vm.drawingState.deleteSelected() }
                    .disabled(!vm.drawingState.objects.contains { $0.isSelected })
                Button("清除全部绘图") { vm.drawingState.clearAll() }
            }

            Divider()

            // 指标参数
            Button("指标参数设置...") {
                vm.showingIndicatorSettings = true
            }

            Divider()

            // 截图
            Button("保存截图") {
                saveScreenshot()
            }

            Divider()

            // 快捷键提示
            Menu("快捷键") {
                Text("↑↓  切换合约")
                Text("←→  平移K线")
                Text("1-5  切换周期")
                Text("+/-  缩放K线")
                Text("Tab  切换副图")
            }
        }
    }

    private func saveScreenshot() {
        guard let window = NSApp.mainWindow else { return }
        guard let cgImage = CGWindowListCreateImage(
            window.frame,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            .bestResolution
        ) else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(vm.selectedName)_\(vm.selectedPeriod)_\(dateString()).png"
        panel.allowedContentTypes = [.png]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            try? data.write(to: url)
        }
    }

    private func dateString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        return fmt.string(from: Date())
    }
}
