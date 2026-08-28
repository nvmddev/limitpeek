import SwiftUI

@main
struct LimitPeekApp: App {
    @State private var store = AccountStore()
    @State private var label = MenuBarLabelCache()
    @State private var refresher = Refresher()
    @AppStorage(MenuBarStyle.defaultsKey) private var style = MenuBarStyle.both

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(refresher: refresher)
                .environment(store)
        } label: {
            Image(nsImage: label.image)
                .onAppear {
                    refresher.start(store: store)
                    updateLabel()
                }
                .onChange(of: store.display?.sessionPercent) { _, _ in updateLabel() }
                .onChange(of: style) { _, _ in updateLabel() }
        }
        .menuBarExtraStyle(.window)
    }

    private func updateLabel() {
        label.update(percent: store.display?.sessionPercent, style: style)
    }
}
