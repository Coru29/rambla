// Compares the texts the app shows with the English translation.
// Usage: swift scripts/check-localization.swift <dir with .stringsdata files> <Localizable.strings>
// The .stringsdata files come from compiling with `-emit-localized-strings` (see check-localization.sh): the
// compiler lists every string passed to an API that localizes it (SwiftUI's Text, Button…, String(localized:)).
// Prints the texts without a translation (with where they are) and the translations nobody uses; fails on the first.
import Foundation

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 2, let dataDir = arguments.first, let stringsPath = arguments.last else {
    print("usage: check-localization.swift <stringsdata dir> <Localizable.strings>")
    exit(2)
}

struct Use { let file: String; let line: Int }
var uses: [String: [Use]] = [:]
let files = (try? FileManager.default.contentsOfDirectory(atPath: dataDir)) ?? []
for name in files.sorted() where name.hasSuffix(".stringsdata") {
    guard let data = FileManager.default.contents(atPath: dataDir + "/" + name),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let source = json["source"] as? String,
          let tables = json["tables"] as? [String: [[String: Any]]] else { continue }
    let file = source.components(separatedBy: "/Sources/").last ?? source
    for entry in tables["Localizable"] ?? [] {
        guard let key = entry["key"] as? String else { continue }
        let line = (entry["location"] as? [String: Any])?["startingLine"] as? Int ?? 0
        uses[key, default: []].append(Use(file: file, line: line))
    }
}
guard !uses.isEmpty else {
    print("No localizable strings found in \(dataDir): was the app compiled with -emit-localized-strings?")
    exit(2)
}
guard let translations = NSDictionary(contentsOfFile: stringsPath) as? [String: String] else {
    print("Could not read \(stringsPath)")
    exit(2)
}

let missing = uses.keys.filter { translations[$0] == nil }.sorted()
let unused = translations.keys.filter { uses[$0] == nil }.sorted()
for key in missing {
    let places = uses[key]!.map { "\($0.file):\($0.line)" }.joined(separator: ", ")
    print("missing: \(key.debugDescription)  (\(places))")
}
for key in unused {
    print("unused:  \(key.debugDescription)")
}
print("\(uses.count) texts, \(translations.count) translations, \(missing.count) missing, \(unused.count) unused")
exit(missing.isEmpty ? 0 : 1)
