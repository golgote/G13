import SwiftUI

@main
struct G13App: App {
    @NSApplicationDelegateAdaptor(G13AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("G13 Studio", systemImage: "gamecontroller.fill") {
            MenuBarView(runtime: .shared)
        }
    }
}
