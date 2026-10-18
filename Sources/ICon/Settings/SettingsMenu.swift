import SwiftUI

/// The gear menu in the popup header.
struct SettingsMenu: View {
    let state: AppState

    var body: some View {
        Menu {
            Toggle("Launch at Login", isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.setLaunchAtLogin($0) }
            ))
            Button("Refresh Icons") {
                Task { await state.refresh(captureAll: true) }
            }
            Divider()
            Button("Quit i-con") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
