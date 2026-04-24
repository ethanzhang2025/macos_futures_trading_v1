import SwiftUI
import Shared
import MarketData

struct OrderPanel: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var priceText: String = ""
    @State private var volume: Int = 1
    @State private var priceType: OrderPriceType = .limitPrice

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.border)
            VStack(spacing: 10) {
                priceRow
                volumeRow
                priceTypeRow
                buttonsGrid
                quickActionsRow
            }
            .padding(12)
        }
        .background(Theme.panelBackground)
        .onAppear { autoFillIfEmpty() }
        .onChange(of: vm.selectedSymbol) { _, _ in
            priceText = ""
            autoFillIfEmpty()
        }
        .onChange(of: vm.selectedQuote?.lastPrice) { _, _ in autoFillIfEmpty() }
        .onChange(of: vm.klines.count) { _, _ in autoFillIfEmpty() }
    }

    // MARK: - UI sections

    private var header: some View {
        HStack {
            Text("快速下单")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Text(vm.selectedSymbol)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.textMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var priceRow: some View {
        HStack(spacing: 6) {
            Text("价").font(.system(size: 11)).foregroundColor(Theme.textMuted)
            TextField("", text: $priceText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Theme.chartBackground)
                .cornerRadius(3)
                .disabled(priceType == .marketPrice)
            stepperButton("−") { adjustPrice(-1) }
            stepperButton("＋") { adjustPrice(1) }
            Button("最新") { fillLastPrice() }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Theme.chartBackground).cornerRadius(3)
        }
    }

    private var volumeRow: some View {
        HStack(spacing: 6) {
            Text("量").font(.system(size: 11)).foregroundColor(Theme.textMuted)
            Text("\(volume)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(Theme.chartBackground).cornerRadius(3)
            stepperButton("−") { volume = max(1, volume - 1) }
            stepperButton("＋") { volume += 1 }
            ForEach([1, 5, 10], id: \.self) { v in
                Button("\(v)") { volume = v }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(volume == v ? Theme.textPrimary : Theme.textSecondary)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(volume == v ? Theme.selected : Theme.chartBackground)
                    .cornerRadius(3)
            }
        }
    }

    private var priceTypeRow: some View {
        HStack(spacing: 6) {
            Text("类").font(.system(size: 11)).foregroundColor(Theme.textMuted)
            Picker("", selection: $priceType) {
                Text("限价").tag(OrderPriceType.limitPrice)
                Text("市价").tag(OrderPriceType.marketPrice)
            }
            .pickerStyle(.segmented)
        }
    }

    private var buttonsGrid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                actionButton("买开 F1", color: Theme.up) { submit(.buy, .open) }
                actionButton("卖开 F2", color: Theme.down) { submit(.sell, .open) }
            }
            HStack(spacing: 6) {
                actionButton("买平 F3", color: Theme.up.opacity(0.7)) { submit(.buy, .close) }
                actionButton("卖平 F4", color: Theme.down.opacity(0.7)) { submit(.sell, .close) }
            }
        }
    }

    private var quickActionsRow: some View {
        HStack(spacing: 6) {
            Button {
                flattenAll()
            } label: {
                Text("全部平仓")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Theme.border)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .disabled(vm.trading.positions.isEmpty)
        }
    }

    private func actionButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(color)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    private func stepperButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 22, height: 22)
                .background(Theme.chartBackground)
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 动作

    private var autoFillPrice: Decimal? {
        vm.priceFallback(for: vm.selectedSymbol)
    }

    private func autoFillIfEmpty() {
        if priceText.isEmpty, let p = autoFillPrice {
            priceText = Formatters.price(p)
        }
    }

    private func submit(_ direction: Direction, _ offset: OffsetFlag) {
        let price: Decimal
        if priceType == .marketPrice {
            price = autoFillPrice ?? 0
        } else {
            price = Decimal(string: priceText) ?? 0
        }
        guard price > 0, volume > 0 else { return }
        vm.trading.placeOrder(
            symbol: vm.selectedSymbol,
            direction: direction,
            offsetFlag: offset,
            price: price,
            volume: volume
        )
    }

    private func flattenAll() {
        for pos in vm.trading.positions {
            let price = vm.priceFallback(for: pos.instrumentID) ?? pos.openAvgPrice
            vm.trading.flatten(pos, currentPrice: price)
        }
    }

    private func fillLastPrice() {
        if let p = autoFillPrice {
            priceText = Formatters.price(p)
        }
    }

    private func adjustPrice(_ delta: Int) {
        let current = Decimal(string: priceText) ?? 0
        let next = current + Decimal(delta)
        guard next > 0 else { return }
        priceText = Formatters.price(next)
    }
}
