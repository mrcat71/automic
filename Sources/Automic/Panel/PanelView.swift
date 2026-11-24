import AutomicKit
import SwiftUI

/// The panel under the menu bar icon: the automatic switching switch, the volume of the
/// current output and input, and both rankings. Click a device to use it now; drag to rerank.
struct PanelView: View {
    var onOpenSettings: () -> Void = {}
    var onQuit: () -> Void = {}

    private let switcher = DeviceSwitcher.shared
    private let settings = AppSettings.shared
    @AppStorage("panel.showAll") private var showAll = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(spacing: 6) {
                VolumeRow(scope: .output)
                VolumeRow(scope: .input)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            PanelDivider()
            DeviceSection(scope: .output, title: "Speakers and Headphones", showAll: showAll)
            PanelDivider()
            DeviceSection(scope: .input, title: "Microphones", showAll: showAll)
            PanelDivider()
            Toggle("Show disconnected and never-used devices", isOn: $showAll)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            PanelDivider()
            footer
        }
        .padding(.vertical, 6)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .background { surface }
    }

    private var header: some View {
        HStack {
            Text("Automatic switching")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Toggle("Automatic switching", isOn: Binding(
                get: { settings.autoSwitch },
                set: { switcher.setAutoSwitch($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Button(action: onOpenSettings) {
                Label("Automic Settings…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PanelButtonStyle())
            Button(action: onQuit) {
                Image(systemName: "power")
            }
            .buttonStyle(PanelButtonStyle())
            .help("Quit Automic")
            .accessibilityLabel("Quit Automic")
        }
        .font(.system(size: 13))
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }

    @ViewBuilder private var surface: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if reduceTransparency {
            shape.fill(Color(nsColor: .windowBackgroundColor))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.6))
        } else {
            shape.fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                .glassEffect(.regular, in: shape)
        }
    }
}

private struct PanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(height: 0.5)
            .padding(.horizontal, 14)
    }
}

/// A round tile with the device's symbol; the device in use is a solid accent tile.
struct DeviceBadge: View {
    let symbol: String
    var isActive = false
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .frame(width: size, height: size)
            .background(Circle().fill(isActive ? Color.accentColor : Color.primary.opacity(0.09)))
            .accessibilityHidden(true)
    }
}

private struct VolumeRow: View {
    let scope: AudioScope
    private let switcher = DeviceSwitcher.shared

    var body: some View {
        let device = switcher.connected[scope, default: []].first { $0.uid == switcher.current[scope] }
        HStack(spacing: 10) {
            // Speaker or microphone, not the device: a headset is both and would look the same twice.
            DeviceBadge(symbol: scope.symbolName)
            if let volume = switcher.volumes[scope] {
                Slider(value: Binding(
                    get: { Double(volume) },
                    set: { switcher.setVolume(Float($0), scope) }
                ), in: 0...1)
                .controlSize(.small)
                .accessibilityLabel("\(scope == .output ? "Output" : "Input") volume")
                Text("\(Int((volume * 100).rounded()))%")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            } else {
                Text(device == nil ? "No \(scope.title.lowercased()) device" : "No volume control")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .help(device?.name ?? "")
    }
}

private struct DeviceSection: View {
    let scope: AudioScope
    let title: String
    let showAll: Bool
    private let switcher = DeviceSwitcher.shared
    @State private var dropTarget: String?

    var body: some View {
        let visible = switcher.ranking(scope).entries.filter {
            showAll || (switcher.isConnected($0.uid, scope) && !$0.isDisabled)
        }
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            if visible.isEmpty {
                Text(showAll ? "No devices yet" : "Nothing connected")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                DeviceRow(scope: scope, entry: entry, rank: index + 1, isDropTarget: dropTarget == entry.uid)
                    .draggable(entry.uid) {
                        Label(entry.name, systemImage: entry.transport.symbolName(for: scope))
                            .font(.system(size: 13))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: .capsule)
                    }
                    .dropDestination(for: String.self) { items, _ in
                        move(items.first, onto: entry.uid, in: visible.map(\.uid))
                    } isTargeted: { targeted in
                        if targeted {
                            dropTarget = entry.uid
                        } else if dropTarget == entry.uid {
                            dropTarget = nil
                        }
                    }
            }
        }
        .padding(.bottom, 6)
    }

    /// Dropping a row on another puts it in that row's place.
    private func move(_ dragged: String?, onto target: String, in visible: [String]) -> Bool {
        guard let dragged, let from = visible.firstIndex(of: dragged), let to = visible.firstIndex(of: target), from != to else {
            return false
        }
        switcher.editRanking(scope) {
            $0.move(visible: visible, fromOffsets: [from], toOffset: to > from ? to + 1 : to)
        }
        return true
    }
}

private struct DeviceRow: View {
    let scope: AudioScope
    let entry: PriorityEntry
    let rank: Int
    let isDropTarget: Bool
    private let switcher = DeviceSwitcher.shared
    private let settings = AppSettings.shared
    @State private var isHovered = false

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        let connected = switcher.isConnected(entry.uid, scope)
        let inUse = switcher.current[scope] == entry.uid
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 14, alignment: .trailing)
            DeviceBadge(symbol: entry.transport.symbolName(for: scope), isActive: inUse)
            Text(entry.name)
                .font(.system(size: 13, weight: inUse ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            if let detail = detail(connected: connected) {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if inUse, settings.autoSwitch, switcher.isOverridden(scope) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .help("Chosen by hand: kept until a device connects or disconnects")
            }
        }
        .opacity(connected && !entry.isDisabled ? 1 : 0.5)
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isDropTarget ? Color.accentColor.opacity(0.18) : Color.primary.opacity(isHovered && connected ? 0.06 : 0))
        )
        .padding(.horizontal, 6)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onTapGesture {
            if connected { switcher.select(entry.uid, scope) }
        }
        .contextMenu { actions(connected: connected) }
        .help(connected ? "Click to use now, drag to change its priority" : "Drag to change its priority")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(rank). \(entry.name)\(inUse ? ", in use" : "")\(detail(connected: connected).map { ", \($0)" } ?? "")")
        .accessibilityAction(named: "Use Now") {
            if connected { switcher.select(entry.uid, scope) }
        }
    }

    private func detail(connected: Bool) -> String? {
        if !connected {
            guard let lastSeen = entry.lastSeen else { return "Disconnected" }
            return "Last seen \(Self.relative.localizedString(for: lastSeen, relativeTo: Date()))"
        }
        return entry.isDisabled ? "Never used automatically" : nil
    }

    @ViewBuilder private func actions(connected: Bool) -> some View {
        Button("Use Now") { switcher.select(entry.uid, scope) }
            .disabled(!connected)
        Divider()
        Button("Move to Top") { edit { $0.move(entry.uid, by: -$0.entries.count) } }
        Button("Move Up") { edit { $0.move(entry.uid, by: -1) } }
        Button("Move Down") { edit { $0.move(entry.uid, by: 1) } }
        Divider()
        Toggle("Never Use Automatically", isOn: Binding(
            get: { entry.isDisabled },
            set: { disabled in edit { $0.setDisabled(entry.uid, disabled) } }
        ))
        Button("Forget Device", role: .destructive) { edit { $0.forget(entry.uid) } }
            .disabled(connected)
    }

    private func edit(_ change: (inout PriorityList) -> Void) {
        switcher.editRanking(scope, change)
    }
}

/// A full-width row button that highlights on hover, like a menu item.
private struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PanelButton(configuration: configuration)
    }

    private struct PanelButton: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 8)
                .frame(minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : isHovered ? 0.06 : 0))
                )
                .contentShape(.rect)
                .onHover { isHovered = $0 }
        }
    }
}
