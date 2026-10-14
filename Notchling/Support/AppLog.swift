import os

enum AppLog {
    static let subsystem = "com.notchling.app"
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let screen = Logger(subsystem: subsystem, category: "screen")
    static let panel = Logger(subsystem: subsystem, category: "panel")
    static let general = Logger(subsystem: subsystem, category: "general")
}
