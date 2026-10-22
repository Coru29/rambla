/// The windows of each strip that are not shown on its Space: minimized, their app hidden, an inactive native tab, or in
/// full screen on a Space of their own.
public enum HiddenWindows {
    /// The record after a pass that looked at the strips in `looked`: theirs become what the pass `found` (no entry when
    /// nothing is hidden), and every other strip that still `exists` keeps what was last seen on it. A pass sees a strip
    /// only while its Space is current, and a window in full screen is seen hidden on its desktop only from that desktop:
    /// forgetting it while the user is on the full-screen Space would hide that it came back.
    public static func update<Key: Hashable>(_ record: [Key: Set<WindowID>], found: [Key: Set<WindowID>],
                                             looked: Set<Key>, exists: (Key) -> Bool) -> [Key: Set<WindowID>] {
        record.filter { !looked.contains($0.key) && exists($0.key) }.merging(found) { _, new in new }
    }

    /// True when `id` was hidden on `key` before the pass and is shown after it.
    public static func returned<Key: Hashable>(_ id: WindowID, on key: Key, before: [Key: Set<WindowID>],
                                               now: [Key: Set<WindowID>]) -> Bool {
        before[key]?.contains(id) == true && now[key]?.contains(id) != true
    }
}
