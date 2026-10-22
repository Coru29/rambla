/// What asking an input tracker to make its taps again did (see `MouseButtonTracker.renew`).
enum TapRenewal {
    /// The feature is off: there are no taps.
    case off
    case renewed
    /// A gesture is under way and new taps would cut it short: ask again in a moment.
    case busy
}
