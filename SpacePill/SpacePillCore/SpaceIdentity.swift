import Foundation

/**
 * Deriving a stable, non-empty key for a Space.
 *
 * Labels and colours in `SettingsManager.spaceConfigs` are keyed by the UUID
 * SkyLight reports for a Space, which is stable for the Space's lifetime. On
 * some Macs, though, SkyLight hands back an **empty** UUID string for the first
 * desktop (Desktop 1). An empty dictionary key is a latent correctness hole:
 * every Space SkyLight cannot identify would share the one `""` bucket and
 * clobber each other's config. Today it happens to work only because a single
 * Space has an empty UUID.
 *
 * When the UUID is empty we derive a key from `id64` -- the ManagedSpaceID,
 * which is present and stable for the life of the Space -- so every Space gets
 * its own non-empty, collision-free key. The derived key carries a recognisable
 * prefix so migration code (and anyone reading `settings.json`) can tell a
 * key we synthesised from a real SkyLight UUID.
 *
 * Pure logic, no AppKit/SwiftUI/SkyLight, so it is unit testable.
 */
public enum SpaceIdentity {
    /// Marks a key SpacePill derived itself because SkyLight reported no UUID.
    /// Real SkyLight UUIDs are hex-and-dashes ("88C597ED-4FE2-..."), so this
    /// prefix cannot collide with one.
    public static let syntheticPrefix = "sp-id64:"

    /**
     * A stable, guaranteed non-empty key for a Space.
     *
     * - Parameters:
     *   - rawUUID: the `uuid` string SkyLight reported, which may be empty or nil.
     *   - id64: the `id64` (ManagedSpaceID) SkyLight reported, used as the stable
     *     fallback when no UUID is available.
     */
    public static func key(rawUUID: String?, id64: UInt64) -> String {
        if let uuid = rawUUID, !uuid.isEmpty {
            return uuid
        }
        return "\(syntheticPrefix)\(id64)"
    }

    /// Whether `key` was synthesised by `key(rawUUID:id64:)` rather than
    /// reported by SkyLight. Used by the one-time migration of the legacy `""`
    /// config bucket onto its real, synthesised key.
    public static func isSynthetic(_ key: String) -> Bool {
        key.hasPrefix(syntheticPrefix)
    }
}
