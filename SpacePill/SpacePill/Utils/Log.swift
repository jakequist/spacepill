import Foundation
import os

/**
 * Unified-logging channels for SpacePill.
 *
 * `print()` is useless in a packaged menu bar app: there is no attached terminal,
 * and stdout is block-buffered when it is not a TTY, so messages are silently
 * swallowed. `os.Logger` routes to the system log instead, which is readable at
 * any time with:
 *
 *     log stream --predicate 'subsystem == "com.jake.SpacePill"' --level debug
 *     log show --predicate 'subsystem == "com.jake.SpacePill"' --last 5m
 *
 * Note on privacy: string interpolation into a Logger is redacted as `<private>`
 * by default. Space labels are user data and stay redacted; IDs, indices and
 * status codes are marked `.public` at the call site so they survive into the log.
 */
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.jake.SpacePill"

    /// App lifecycle: launch, termination, state save.
    static let app = Logger(subsystem: subsystem, category: "app")

    /// Space detection and transitions (SkyLight / event tap).
    static let spaces = Logger(subsystem: subsystem, category: "spaces")

    /// Carbon global hotkey registration and dispatch.
    static let hotkeys = Logger(subsystem: subsystem, category: "hotkeys")

    /// Menu bar item, popovers, and the notes panel.
    static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Settings load/save and migration.
    static let settings = Logger(subsystem: subsystem, category: "settings")

    /// Per-space notes persistence.
    static let notes = Logger(subsystem: subsystem, category: "notes")
}
