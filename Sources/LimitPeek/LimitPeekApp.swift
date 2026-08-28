import SwiftUI

@main
struct LimitPeekApp: App {
    @State private var store = AccountStore()
    @State private var label = MenuBarLabelCache()
    @State private var refresher = Refresher()

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(refresher: refresher)
                .environment(store)
        } label: {
            Image(nsImage: label.image)
                .onAppear { refresher.start(store: store) }
                .onChange(of: store.display?.sessionPercent) { _, percent in
                    label.update(percent: percent)
                }
        }
        .menuBarExtraStyle(.window)
    }
}
