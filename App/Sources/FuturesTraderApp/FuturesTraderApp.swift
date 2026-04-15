import SwiftUI

@main
struct FuturesTraderApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup("期货交易终端") {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 1200, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1400, height: 850)
    }
}
