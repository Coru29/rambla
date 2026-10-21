// Computes the next version from Conventional Commits since the last release tag and writes the release notes.
//   feat: → minor   fix: / perf: → patch   "!" after the type or a "BREAKING CHANGE:" footer → major
//   other types (docs, chore, refactor, test, build, ci, style) do not trigger a release.
// Usage: swift scripts/next-version.swift [notes-output-file]
// Prints the next version ("1.2.0") or "none". With no previous v* tag it releases the VERSION file as is.
import Foundation

func git(_ args: [String]) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    try? p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

struct Commit { let type: String; let scope: String?; let breaking: Bool; let summary: String; let hash: String }

/// "feat(updates)!: text" → Commit. Non-conventional subjects return nil.
func parse(subject: String, body: String, hash: String) -> Commit? {
    let pattern = #"^([a-z]+)(\(([^)]+)\))?(!)?: (.+)$"#
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(subject.startIndex..., in: subject)
    guard let m = regex.firstMatch(in: subject, range: range) else { return nil }
    func group(_ i: Int) -> String? { Range(m.range(at: i), in: subject).map { String(subject[$0]) } }
    let breaking = group(4) != nil || body.contains("BREAKING CHANGE:") || body.contains("BREAKING-CHANGE:")
    return Commit(type: group(1)!, scope: group(3), breaking: breaking, summary: group(5)!, hash: String(hash.prefix(7)))
}

let notesPath = CommandLine.arguments.dropFirst().first
let root = git(["rev-parse", "--show-toplevel"]).out.trimmingCharacters(in: .whitespacesAndNewlines)
let fileVersion = (try? String(contentsOfFile: root + "/VERSION", encoding: .utf8))?
    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "1.0.0"
let lastTag = git(["describe", "--tags", "--abbrev=0", "--match", "v[0-9]*"])
let hasTag = lastTag.status == 0
let tag = lastTag.out.trimmingCharacters(in: .whitespacesAndNewlines)
let range = hasTag ? "\(tag)..HEAD" : "HEAD"
let log = git(["log", range, "--no-merges", "--format=%H%x1f%s%x1f%b%x1e"]).out
let commits = log.split(separator: "\u{1e}").compactMap { record -> Commit? in
    let fields = record.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\u{1f}")
    guard fields.count >= 2 else { return nil }
    return parse(subject: fields[1], body: fields.count > 2 ? fields[2] : "", hash: fields[0])
}

var parts = (hasTag ? String(tag.dropFirst()) : fileVersion).split(separator: ".").compactMap { Int($0) }
while parts.count < 3 { parts.append(0) }
let next: String
if !hasTag {
    next = fileVersion
} else if commits.contains(where: \.breaking) {
    next = "\(parts[0] + 1).0.0"
} else if commits.contains(where: { $0.type == "feat" }) {
    next = "\(parts[0]).\(parts[1] + 1).0"
} else if commits.contains(where: { $0.type == "fix" || $0.type == "perf" }) {
    next = "\(parts[0]).\(parts[1]).\(parts[2] + 1)"
} else {
    print("none")
    exit(0)
}

func section(_ title: String, _ items: [Commit]) -> String {
    guard !items.isEmpty else { return "" }
    let lines = items.map { c -> String in
        let scope = c.scope.map { "**\($0):** " } ?? ""
        let first = c.summary.prefix(1).uppercased() + c.summary.dropFirst()
        return "- \(scope)\(first) (\(c.hash))"
    }
    return "### \(title)\n\n" + lines.joined(separator: "\n") + "\n\n"
}

var notes = ""
notes += section("Breaking changes / Cambios incompatibles", commits.filter(\.breaking))
notes += section("Features / Novedades", commits.filter { $0.type == "feat" && !$0.breaking })
notes += section("Fixes / Arreglos", commits.filter { $0.type == "fix" && !$0.breaking })
notes += section("Performance / Rendimiento", commits.filter { $0.type == "perf" && !$0.breaking })
if !hasTag && notes.isEmpty {
    notes = "First public release. / Primera versión pública.\n\n"
}
notes += "**Download / Descargar:** [Rambla.dmg](https://github.com/Coru29/rambla/releases/download/v\(next)/Rambla.dmg)\n"
if let notesPath { try? notes.write(toFile: notesPath, atomically: false, encoding: .utf8) }
print(next)
