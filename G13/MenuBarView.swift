import SwiftUI

struct MenuBarView: View {
    @ObservedObject var runtime: G13Runtime
    @ObservedObject var device: G13Device
    @ObservedObject var profiles: ProfileManager

    init(runtime: G13Runtime) {
        self.runtime = runtime
        self.device = runtime.device
        self.profiles = runtime.profileManager
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(device.isConnected ? "G13 connected" : "G13 disconnected")
            Text("\(profiles.activeProfileName) · M\(profiles.activeLayer)")
                .foregroundStyle(.secondary)
            Divider()
            Button("Open G13 Studio") { SettingsWindowController.shared.show(runtime: runtime) }
            Toggle("Safe test mode", isOn: Binding(
                get: { runtime.isSafeTestMode },
                set: { runtime.setSafeTestMode($0) }
            ))
            Divider()
            Button("Quit G13 Studio") {
                runtime.stop()
                NSApp.terminate(nil)
            }
        }
        .padding(8)
    }
}
