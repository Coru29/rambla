import Foundation

/// What the hint of a strip that came into view empty says besides its title: that anything can be opened there, how
/// to bring a window from the nearest strip that has some, and how to go back to it. Kept apart from the overlay so
/// that every combination of strips, shortcuts and gestures can be tested.
public enum EmptyStripHint {
    /// The sentences of the hint's detail, joined with a space. `active` is the empty level in view, `occupied` the
    /// levels of its stack with windows, and `shortcutName` writes a shortcut the way the app shows it.
    ///
    /// The first sentence is always there. The others point at the nearest strip with windows
    /// (`StripLevels.nearestOccupied`) and are left out when there is none:
    /// - **Bringing a window** is done from that strip, with the shortcut that sends its focused window to this one: up
    ///   from a strip below, down from one above. (The empty strip has no focused window to send.) A shortcut that is
    ///   not bound leaves the sentence out.
    /// - **Going back** names the shortcut that goes there and, when a swipe on the trackpad changes strips (it is on,
    ///   so are its vertical swipes, and they are not set to change the width), which way the fingers go. Without the
    ///   shortcut it names only the swipe, and without the swipe only the shortcut; without either, there is no
    ///   sentence.
    public static func detail(active: Int, occupied: Set<Int>, prefs: Preferences,
                              shortcutName: (KeyCombo) -> String) -> String {
        var sentences = [String(localized: "Abrí acá lo que quieras.")]
        guard let nearest = StripLevels.nearestOccupied(from: active, occupied: occupied) else { return sentences[0] }
        let below = nearest < active
        func shortcut(_ action: Action) -> String? { prefs.shortcuts(for: action).first.map(shortcutName) }

        if let send = shortcut(below ? .sendStripUp : .sendStripDown) {
            sentences.append(below
                ? String(localized: "O mandá una ventana desde la tira de abajo con \(send).")
                : String(localized: "O mandá una ventana desde la tira de arriba con \(send).")
            )
        }

        let swipe = swipeChangesStrips(prefs) ? fingersGo(toStripAbove: !below, natural: prefs.trackpad.natural) : nil
        switch (swipe, shortcut(below ? .stripDown : .stripUp)) {
        case let (.up?, back?): sentences.append(String(localized: "Para volver, deslizá hacia arriba o usá \(back)."))
        case let (.down?, back?): sentences.append(String(localized: "Para volver, deslizá hacia abajo o usá \(back)."))
        case (.up?, nil): sentences.append(String(localized: "Para volver, deslizá hacia arriba."))
        case (.down?, nil): sentences.append(String(localized: "Para volver, deslizá hacia abajo."))
        case let (nil, back?): sentences.append(String(localized: "Para volver, usá \(back)."))
        case (nil, nil): break
        }
        return sentences.joined(separator: " ")
    }

    private enum Swipe { case up, down }

    /// A swipe on the trackpad changes strip: the trackpad takes swipes, its vertical ones are on, and they change
    /// strips rather than the width.
    private static func swipeChangesStrips(_ prefs: Preferences) -> Bool {
        prefs.trackpad.enabled && prefs.trackpad.verticalSwipe && prefs.verticalGesture == .strips
    }

    /// Which way the fingers go on a short swipe that brings the strip above (`above`) or the one below into view:
    /// going up shows the strip above without the natural direction, and the one below with it.
    private static func fingersGo(toStripAbove above: Bool, natural: Bool) -> Swipe {
        StripLevels.stripAbove(fingersUp: true, natural: natural) == above ? .up : .down
    }
}
