import AutomicKit
import SwiftUI

/// The ranking of one scope: drag to reorder, mark a device never to be used, forget one that
/// is gone.
struct PriorityPane: View {
    let scope: AudioScope
    private let switcher = DeviceSwitcher.shared
    private let settings = AppSettings.shared

    var body: some View {
        let entries = switcher.ranking(scope).entries
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(scope.title) priority")
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("The highest connected device becomes the default \(scope == .output ? "output" : "microphone"). Drag to reorder.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Group {
                if entries.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            PriorityRow(scope: scope, entry: entry, rank: index + 1, count: entries.count)
                        }
                        .onMove { offsets, destination in
                            switcher.editRanking(scope) { $0.move(fromOffsets: offsets, toOffset: destination) }
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: false))
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.035), in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            footnote
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 520, height: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var footnote: some View {
        if !settings.autoSwitch {
            Label("Automatic switching is off. Turn it on in General or from the menu bar.", systemImage: "pause.circle")
        } else if switcher.isOverridden(scope) {
            Label("You picked the current \(scope.title.lowercased()) by hand. Automic keeps it until a device connects or disconnects.", systemImage: "hand.raised")
        } else {
            Text("New devices join at the bottom, so they never take over until you move them up.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: scope.symbolName)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No \(scope.title.lowercased()) devices yet")
                .font(.system(size: 13, weight: .semibold))
            Text("Devices appear here the first time they connect.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

private struct PriorityRow: View {
    let scope: AudioScope
    let entry: PriorityEntry
    let rank: Int
    let count: Int
    private let switcher = DeviceSwitcher.shared

    var body: some View {
        let connected = switcher.isConnected(entry.uid, scope)
        let inUse = switcher.current[scope] == entry.uid
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
            Image(systemName: entry.transport.symbolName(for: scope))
                .font(.system(size: 13))
                .frame(width: 22)
                .foregroundStyle(connected ? .primary : .tertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 13))
                    .foregroundStyle(connected && !entry.isDisabled ? .primary : .secondary)
                    .strikethrough(entry.isDisabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(status(connected: connected))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if inUse {
                Text("In use")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.14), in: .capsule)
            }
            Menu {
                actions(connected: connected)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More actions for \(entry.name)")
            .accessibilityLabel("More actions for \(entry.name)")
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
        .contextMenu { actions(connected: connected) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rank). \(entry.name), \(status(connected: connected))\(inUse ? ", in use" : "")")
    }

    private func status(connected: Bool) -> String {
        var parts = [connected ? "Connected" : "Not connected"]
        if entry.isDisabled { parts.append("never used automatically") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func actions(connected: Bool) -> some View {
        Button("Move to Top") { edit { $0.move(entry.uid, by: -count) } }
            .disabled(rank == 1)
        Button("Move Up") { edit { $0.move(entry.uid, by: -1) } }
            .disabled(rank == 1)
        Button("Move Down") { edit { $0.move(entry.uid, by: 1) } }
            .disabled(rank == count)
        Divider()
        Toggle("Never Use Automatically", isOn: Binding(
            get: { entry.isDisabled },
            set: { disabled in edit { $0.setDisabled(entry.uid, disabled) } }
        ))
        Divider()
        Button("Forget Device", role: .destructive) { edit { $0.forget(entry.uid) } }
            .disabled(connected)
    }

    private func edit(_ change: (inout PriorityList) -> Void) {
        switcher.editRanking(scope, change)
    }
}
