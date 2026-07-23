import Foundation
import CoreGraphics

/**
 * The user's own "Switch to Desktop N" keyboard shortcuts, read from
 * System Settings.
 *
 * Switching spaces has no API, so SpacePill can only simulate the shortcut the
 * user already has bound. That makes their configuration load-bearing:
 *
 *  - These shortcuts are **disabled by default** on macOS. A stock machine has
 *    no way to jump to a desktop by number, so posting Ctrl+N there does
 *    nothing at all and the app has no direct way to notice.
 *  - Users can rebind them. Assuming Ctrl+N sends the wrong keystroke for
 *    anyone who has.
 *
 * Both cases used to fail silently. Reading the real binding lets the UI grey
 * out what it genuinely cannot reach and press the right keys for the rest.
 *
 * Storage lives in the `com.apple.symbolichotkeys` preference domain under
 * `AppleSymbolicHotKeys`, keyed by symbolic hotkey ID:
 *
 *     118 = Switch to Desktop 1 ... 127 = Switch to Desktop 10
 *
 *     <key>118</key>
 *     <dict>
 *         <key>enabled</key><true/>
 *         <key>value</key><dict>
 *             <key>type</key><string>standard</string>
 *             <key>parameters</key>
 *             <array>
 *                 <integer>65535</integer>   <!-- ASCII char, 65535 = none -->
 *                 <integer>18</integer>      <!-- virtual key code -->
 *                 <integer>262144</integer>  <!-- modifier flags -->
 *             </array>
 *         </dict>
 *     </dict>
 *
 * An absent entry means the shortcut is at its factory default, which for these
 * particular IDs is *off* -- verified on macOS 26 by posting Ctrl+4 with no 118...127
 * entries present and observing no space change, while an explicitly enabled
 * shortcut in the same session worked. So absent is treated as unavailable.
 */
struct SpaceShortcut {
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags
}

enum SpaceShortcuts {
    /// macOS only defines "Switch to Desktop" shortcuts for the first ten desktops.
    static let maxDesktop = 10

    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let key = "AppleSymbolicHotKeys" as CFString

    /// Symbolic hotkey ID for a 1-based desktop number.
    private static func symbolicHotKeyID(forDesktop desktop: Int) -> String {
        String(117 + desktop)
    }

    /// Parsed bindings, keyed by desktop number. Rebuilt by `refresh()`.
    private static var cache: [Int: SpaceShortcut] = [:]
    private static var hasLoaded = false

    /// Re-read System Settings. Call before showing any UI that reflects
    /// reachability, so changes made while SpacePill is running are picked up.
    static func refresh() {
        CFPreferencesAppSynchronize(domain)

        var parsed: [Int: SpaceShortcut] = [:]
        defer {
            cache = parsed
            hasLoaded = true
            Log.spaces.info("Desktop switch shortcuts available: \(parsed.keys.sorted().map(String.init).joined(separator: ","), privacy: .public)")
        }

        guard let raw = CFPreferencesCopyAppValue(key, domain) as? [String: Any] else {
            Log.spaces.notice("Could not read AppleSymbolicHotKeys; treating all desktop shortcuts as unavailable")
            return
        }

        for desktop in 1...maxDesktop {
            guard let entry = raw[symbolicHotKeyID(forDesktop: desktop)] as? [String: Any] else {
                continue // absent -> factory default -> off
            }
            // `enabled` may be a Bool or an NSNumber depending on how it was written.
            guard let enabled = entry["enabled"] as? Bool, enabled else { continue }
            guard let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [Int],
                  parameters.count >= 3 else { continue }

            let keyCode = parameters[1]
            // 65535 is macOS's "no key assigned" sentinel.
            guard keyCode != 65535, keyCode >= 0, keyCode <= Int(UInt16.max) else { continue }

            parsed[desktop] = SpaceShortcut(
                keyCode: CGKeyCode(keyCode),
                modifiers: eventFlags(fromCocoaModifiers: parameters[2])
            )
        }
    }

    private static func loadIfNeeded() {
        if !hasLoaded { refresh() }
    }

    /**
     * The shortcut bound to a given desktop, or nil if there is none.
     */
    static func shortcut(forDesktop desktop: Int) -> SpaceShortcut? {
        loadIfNeeded()
        return cache[desktop]
    }

    /// Whether any desktop can be jumped to at all. False on a stock macOS install.
    static var hasAnyShortcuts: Bool {
        loadIfNeeded()
        return !cache.isEmpty
    }

    /**
     * Desktop numbers that currently have a usable shortcut.
     *
     * Views should read this into `@State` rather than querying per row: this
     * type is a plain static cache, so mutating it does not invalidate any
     * SwiftUI view that depends on it.
     */
    static func reachableDesktops() -> Set<Int> {
        loadIfNeeded()
        return Set(cache.keys)
    }

    /**
     * NSEvent-style modifier flags to CGEventFlags.
     *
     * The two share bit positions for the four modifiers we care about, but the
     * stored value also carries device-dependent bits that must not be forwarded
     * into a synthetic event.
     */
    private static func eventFlags(fromCocoaModifiers raw: Int) -> CGEventFlags {
        var flags: CGEventFlags = []
        if raw & (1 << 17) != 0 { flags.insert(.maskShift) }
        if raw & (1 << 18) != 0 { flags.insert(.maskControl) }
        if raw & (1 << 19) != 0 { flags.insert(.maskAlternate) }
        if raw & (1 << 20) != 0 { flags.insert(.maskCommand) }
        return flags
    }
}
