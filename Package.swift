// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Automic",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Automic", targets: ["Automic"]),
        .library(name: "AutomicKit", targets: ["AutomicKit"]),
    ],
    dependencies: [
        // In-app updates; its bin/ tools (generate_keys, sign_update, generate_appcast) also sign releases.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        // Pure logic: devices, priority lists and the switching policy. No AppKit or CoreAudio,
        // so everything here is unit-testable without audio hardware.
        .target(name: "AutomicKit"),
        // The menu bar app: AppKit lifecycle, SwiftUI settings, CoreAudio, Sparkle.
        .executableTarget(
            name: "Automic",
            dependencies: ["AutomicKit", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        // Renders the app icon PNG set; the Makefile turns it into AppIcon.icns.
        .executableTarget(name: "automic-icon"),
        .testTarget(name: "AutomicKitTests", dependencies: ["AutomicKit"]),
    ]
)
