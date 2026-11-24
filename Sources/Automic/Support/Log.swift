import OSLog

/// Unified logging; read with `/usr/bin/log show --predicate 'subsystem == "io.github.mrcat71.automic"'`.
enum Log {
    nonisolated static let subsystem = "io.github.mrcat71.automic"
    nonisolated static let app = Logger(subsystem: subsystem, category: "app")
    nonisolated static let audio = Logger(subsystem: subsystem, category: "audio")
}
