import SwiftUI

@main
struct TimeCheckerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuPopover().environmentObject(model)
        } label: {
            MenuLabel().environmentObject(model)
        }
        .menuBarExtraStyle(.window)

        Window("Time Checker", id: "main") {
            MainView()
                .environmentObject(model)
                .frame(minWidth: 860, minHeight: 580)
        }
        .defaultSize(width: 980, height: 680)
        .defaultLaunchBehavior(.suppressed)
    }
}
