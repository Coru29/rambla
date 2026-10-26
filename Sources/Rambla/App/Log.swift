import Foundation
import os

/// Unified logging plus a small rolling file in ~/Library/Logs/Rambla (shown by "Mostrar registro").
enum Log {
    private static let logger = Logger(subsystem: "io.github.coru29.Rambla", category: "app")
    private static let queue = DispatchQueue(label: "io.github.coru29.Rambla.log")
    private static let maxBytes: UInt64 = 512 * 1024
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static let fileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Rambla", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("rambla.log")
    }()

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        append("INFO", message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        append("ERROR", message)
    }

    /// Waits until every line logged so far is in the file: an `exit` would drop those still on their way.
    static func flush() {
        queue.sync {}
    }

    private static func append(_ level: String, _ message: String) {
        let line = "\(formatter.string(from: Date())) [\(level)] \(message)\n"
        queue.async {
            let fm = FileManager.default
            if let size = (try? fm.attributesOfItem(atPath: fileURL.path))?[.size] as? UInt64, size > maxBytes {
                let old = fileURL.appendingPathExtension("1")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: fileURL, to: old)
            }
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}
