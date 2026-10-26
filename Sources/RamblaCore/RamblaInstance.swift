/// A running Rambla, as the check for a second one compares them: its process id and when it started.
///
/// Of the Ramblas running at once, the one that started first keeps managing the windows: a Rambla yields only to one
/// that started before it, so two started together leave exactly one. When they started is the kernel's record of it,
/// not the process id, which wraps around on a Mac that stays up long enough and would make an old Rambla look new.
public struct RamblaInstance: Equatable, Sendable {
    public let pid: Int32
    /// When it started, in seconds, on the same clock for every process.
    public let start: Double

    public init(pid: Int32, start: Double) {
        self.pid = pid
        self.start = start
    }

    /// It started before `other`: earlier, or at the same moment with the lower process id.
    public func startedBefore(_ other: RamblaInstance) -> Bool {
        (start, pid) < (other.start, other.pid)
    }
}
