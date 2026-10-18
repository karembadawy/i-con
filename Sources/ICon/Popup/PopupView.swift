import SwiftUI

struct PopupView: View {
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.permissions.accessibility {
                content
            } else {
                AccessibilityOnboarding(permissions: state.permissions)
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }

    @ViewBuilder private var content: some View {
        HStack(spacing: 6) {
            Text("Hidden").font(.headline)
            Spacer()
            Button(state.isEditing ? "Done" : "Edit") { state.setEditing(!state.isEditing) }
                .controlSize(.small)
            SettingsMenu(state: state)
        }

        if case .unavailable(let reason) = state.engineState {
            Label("Can't hide icons: \(reason)", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }

        let outside = state.appsMacOSWillHide
        if !outside.isEmpty {
            let names = ListFormatter.localizedString(byJoining: outside.map(\.name))
            Label(
                "\(names) \(outside.count == 1 ? "isn't" : "aren't") in the Applications folder, so macOS hides \(outside.count == 1 ? "its icon" : "their icons") while i-con is hiding others. Move \(outside.count == 1 ? "it" : "them") to /Applications.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        }

        ItemRow(
            state: state,
            section: .hidden,
            items: state.hiddenItems,
            placeholder: state.isEditing ? "Drag icons here to hide them" : "No hidden icons. Click Edit to choose some."
        )

        if state.isEditing {
            Text("Menu bar").font(.headline).padding(.top, 4)
            ItemRow(state: state, section: .menuBar, items: state.visibleItems, placeholder: "Drag icons here to show them")
            Text("Drag icons between the rows. Don't ⌘-drag icons out of the menu bar: macOS deletes them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !state.permissions.screenRecording {
            HStack(alignment: .firstTextBaseline) {
                Text("Showing app icons. Allow Screen Recording to see the real menu bar icons.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Allow") { state.permissions.requestScreenRecording() }
                    .controlSize(.small)
            }
        }
    }
}

/// A row of icons that accepts drops. Dropping on a tile inserts before it.
private struct ItemRow: View {
    let state: AppState
    let section: AppState.Section
    let items: [MenuBarItem]
    let placeholder: String

    @State private var isRowTargeted = false
    @State private var targetedID: String?

    var body: some View {
        FlowLayout(spacing: 2) {
            ForEach(items) { item in
                ItemTile(item: item, icon: state.icons.icon(for: item), onTap: tapAction(for: item))
                    .draggable(item.bundleID)
                    .dropDestination(for: String.self) { ids, _ in
                        state.drop(ids, into: section, before: item.bundleID)
                    } isTargeted: { targeted in
                        if targeted {
                            targetedID = item.bundleID
                        } else if targetedID == item.bundleID {
                            targetedID = nil
                        }
                    }
                    .overlay(alignment: .leading) {
                        if targetedID == item.bundleID {
                            Capsule().fill(Color.accentColor).frame(width: 2).offset(x: -2)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isRowTargeted ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
        )
        .overlay {
            if items.isEmpty {
                Text(placeholder).font(.callout).foregroundStyle(.secondary)
            }
        }
        .dropDestination(for: String.self) { ids, _ in
            state.drop(ids, into: section, before: nil)
        } isTargeted: { isRowTargeted = $0 }
        .animation(.snappy(duration: 0.2), value: items.map(\.bundleID))
    }

    private func tapAction(for item: MenuBarItem) -> (() -> Void)? {
        guard section == .hidden, !state.isEditing else { return nil }
        return { state.activate(item) }
    }
}

private struct AccessibilityOnboarding: View {
    let permissions: Permissions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Allow Accessibility", systemImage: "hand.raised.fill").font(.headline)
            Text("i-con needs Accessibility access to find menu bar icons and open hidden ones. Click Open System Settings and turn on i-con in the list. If it's on but this message stays, click Restart.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open System Settings") { permissions.openAccessibilitySettings() }
                Spacer()
                Button("Restart") { permissions.relaunch() }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
