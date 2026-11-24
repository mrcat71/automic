import SwiftUI

struct GeneralSettingsPane: View {
    private let switcher = DeviceSwitcher.shared
    private let settings = AppSettings.shared
    private let updater = Updater.shared
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup("Switching") {
                Toggle("Switch automatically", isOn: Binding(
                    get: { settings.autoSwitch },
                    set: { switcher.setAutoSwitch($0) }
                ))
                Text("When a device connects or disconnects, Automic makes the highest connected device in Output and Input the default. A device you pick by hand stays until the next one connects or disconnects.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsGroup("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        LoginItem.set(enabled)
                        launchAtLogin = LoginItem.isEnabled
                    }
            }
            SettingsGroup("Updates") {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updater.checksAutomatically },
                    set: { updater.checksAutomatically = $0 }
                ))
                .disabled(!updater.isAvailable)
                HStack {
                    Text("Automic \(Updater.version)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
                if !updater.isAvailable {
                    Text("Updates are not available in this build: only a packaged release with an update key has them.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .toggleStyle(.checkbox)
        .padding(20)
        .frame(width: 520, height: 460, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Flat card under a title, as in Cuadro's settings.
struct SettingsGroup<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
    }
}
