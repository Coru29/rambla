// Live checks for scripts/e2e.sh: reads Rambla's state (`scroll dump`) and the real window bounds.
// Usage: e2e-check <command> [args]   (exit 0 = pass)
import AppKit

let cli = "/Applications/Rambla.app/Contents/MacOS/Rambla"

func run(_ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: cli)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    try? p.run()
    p.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

func dump() -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(run(["dump"]).utf8))) as? [String: Any] ?? [:]
}

func currentStrip(_ d: [String: Any]) -> [String: Any]? {
    (d["strips"] as? [[String: Any]])?.first { ($0["current"] as? Bool) == true && !(($0["columns"] as? [Any]) ?? []).isEmpty }
}

func columns(_ s: [String: Any]) -> [[String: Any]] { s["columns"] as? [[String: Any]] ?? [] }

/// Real bounds from the WindowServer (AX coordinates).
func bounds(_ id: UInt32) -> CGRect? {
    guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]])?.first,
          let b = info[kCGWindowBounds as String] as? [String: Double] else { return nil }
    return CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
}

func display(_ d: [String: Any]) -> (frame: CGRect, visible: CGRect) {
    let disp = (d["displays"] as? [[String: Any]])?.first ?? [:]
    func rect(_ o: Any?) -> CGRect {
        let r = o as? [String: Double] ?? [:]
        return CGRect(x: r["x"] ?? 0, y: r["y"] ?? 0, width: r["w"] ?? 0, height: r["h"] ?? 0)
    }
    return (rect(disp["frame"]), rect(disp["visible"]))
}

func fail(_ message: String) -> Never {
    print("FAIL: \(message)")
    exit(1)
}

func pass(_ message: String) {
    print("PASS: \(message)")
}

func waitUntil(_ timeout: Double = 6, _ condition: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if condition() { return true }
        usleep(150_000)
    }
    return condition()
}

func windowIDs(_ s: [String: Any]) -> [UInt32] {
    columns(s).flatMap { ($0["windows"] as? [NSNumber] ?? []).map(\.uint32Value) }
}

/// Runs `rambla <command>` and samples window `id`'s real frame every 4 ms for 1.5 s.
func samples(_ id: UInt32, running command: [String]) -> [CGRect] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: cli)
    p.arguments = command
    try? p.run()
    var result: [CGRect] = []
    let end = Date().addingTimeInterval(1.5)
    while Date() < end {
        if let b = bounds(id) { result.append(b) }
        usleep(4_000)
    }
    p.waitUntilExit()
    return result
}

func activeDisplays() -> Int {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    return Int(count)
}

/// How much of `r` shows on `display`, in points across.
func shown(_ r: CGRect, on display: CGRect) -> Double {
    r.intersects(display) ? r.intersection(display).width : 0
}

func trace(_ frames: [CGRect], on display: CGRect) -> String {
    frames.filter { shown($0, on: display) > 3 }.map { "\(Int($0.minX))" }.joined(separator: " ")
}

/// `fail` for the commands whose output the script keeps (`$(…)`): the message must not end up in the value.
func failAside(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

// MARK: - Stacked strips

/// How much of a parked window stays on its display, in points (`WindowManager.sliver`).
let sliver = 1.0

/// A display of the dump, with the Space it shows.
struct DumpDisplay {
    let uuid: String
    let frame: CGRect
    let space: UInt64?
}

/// A rectangle of the dump ({x, y, w, h}).
func rectFrom(_ o: Any?) -> CGRect {
    let r = o as? [String: Double] ?? [:]
    return CGRect(x: r["x"] ?? 0, y: r["y"] ?? 0, width: r["w"] ?? 0, height: r["h"] ?? 0)
}

/// The displays of the dump; the first is the one the test windows open on (`display(_:)`).
func dumpDisplays(_ d: [String: Any]) -> [DumpDisplay] {
    (d["displays"] as? [[String: Any]] ?? []).compactMap { entry in
        guard let uuid = entry["uuid"] as? String else { return nil }
        return DumpDisplay(uuid: uuid, frame: rectFrom(entry["frame"]), space: (entry["space"] as? NSNumber)?.uint64Value)
    }
}

/// The stack in view on a display (the strips of the Space it shows; the display of the test windows unless `uuid`
/// says another): the level in view and the highest one. Nil when the dump does not have it. Unlike `currentStrip`, it
/// is there while the level in view is empty.
func stackInView(_ d: [String: Any], on uuid: String? = nil) -> (display: DumpDisplay, active: Int, top: Int)? {
    let all = dumpDisplays(d)
    let chosen: DumpDisplay?
    if let uuid { chosen = all.first { $0.uuid == uuid } } else { chosen = all.first }
    guard let disp = chosen, let space = disp.space else { return nil }
    let stack = (d["stacks"] as? [[String: Any]] ?? []).first {
        ($0["display"] as? String) == disp.uuid && ($0["space"] as? NSNumber)?.uint64Value == space
    }
    guard let active = (stack?["active"] as? NSNumber)?.intValue, let top = (stack?["top"] as? NSNumber)?.intValue else { return nil }
    return (disp, active, top)
}

/// The level of the strip that holds window `id`, at any level.
func levelHolding(_ id: UInt32, in d: [String: Any]) -> Int? {
    let holder = (d["strips"] as? [[String: Any]] ?? []).first { windowIDs($0).contains(id) }
    return (holder?["level"] as? NSNumber)?.intValue
}

/// A window out of view: one of a level that is not in view of a stack that is (`float` false), or a floating window
/// parked with such a level (`float`).
struct OutOfView {
    let id: UInt32
    let display: DumpDisplay
    let level: Int
    let float: Bool
}

/// The windows out of view on the displays that show a stack: those of the levels that are not in view, and the
/// floating windows parked with them.
func outOfView(_ d: [String: Any]) -> [OutOfView] {
    var found: [OutOfView] = []
    for disp in dumpDisplays(d) {
        guard let space = disp.space, let view = stackInView(d, on: disp.uuid) else { continue }
        for strip in d["strips"] as? [[String: Any]] ?? []
        where (strip["display"] as? String) == disp.uuid && (strip["space"] as? NSNumber)?.uint64Value == space {
            let level = (strip["level"] as? NSNumber)?.intValue ?? 0
            if level != view.active { found += windowIDs(strip).map { OutOfView(id: $0, display: disp, level: level, float: false) } }
        }
        found += parkedFloats(d, on: disp).filter { $0.level != view.active }
    }
    return found
}

/// The floating windows parked with a level (`floatShelf`) of the stack the display shows.
func parkedFloats(_ d: [String: Any], on disp: DumpDisplay) -> [OutOfView] {
    guard let space = disp.space else { return [] }
    return (d["floatShelf"] as? [[String: Any]] ?? []).flatMap { shelf -> [OutOfView] in
        guard (shelf["display"] as? String) == disp.uuid, (shelf["space"] as? NSNumber)?.uint64Value == space else { return [] }
        let level = (shelf["level"] as? NSNumber)?.intValue ?? 0
        return (shelf["windows"] as? [NSNumber] ?? []).map { OutOfView(id: $0.uint32Value, display: disp, level: level, float: true) }
    }
}

/// What is wrong with how window `id` hides, in words: more than its sliver (and 1 pt) on its own display, or
/// anything on another one: the real ones in `all`, and `extra`, frames of displays that are not there (the one
/// `debug-neighbor` plugs). Nil when it hides.
func exposure(of id: UInt32, on own: DumpDisplay, among all: [DumpDisplay], extra: [CGRect]) -> String? {
    guard let real = bounds(id) else { return "has no window" }
    var problems: [String] = []
    let onOwn = shown(real, on: own.frame)
    if onOwn > sliver + 1 { problems.append("\(Int(onOwn)) pt on its own display") }
    for other in all where other.uuid != own.uuid && shown(real, on: other.frame) > 0.5 {
        problems.append("\(Int(shown(real, on: other.frame))) pt on display \(other.uuid.prefix(8))")
    }
    for frame in extra where shown(real, on: frame) > 0.5 {
        problems.append("\(Int(shown(real, on: frame))) pt on the display plugged at \(Int(frame.minX)),\(Int(frame.minY))")
    }
    return problems.isEmpty ? nil : "at \(Int(real.minX)),\(Int(real.minY)) (\(Int(real.width)) wide) shows " + problems.joined(separator: ", ")
}

/// The optional frame in `args` from `index` on (X Y W H): the display `debug-neighbor` plugs, which the checks for
/// windows out of sight also look at.
func pluggedDisplay(_ args: [String], from index: Int) -> [CGRect] {
    guard args.count > index else { return [] }
    let v = args[index...].compactMap(Double.init)
    guard args.count == index + 4, v.count == 4 else { fail("the display to look at takes X Y W H, not: \(args[index...].joined(separator: " "))") }
    return [CGRect(x: v[0], y: v[1], width: v[2], height: v[3])]
}

// MARK: - Pause

/// Whether the dump says Rambla is paused, once it has said the same for `hold` seconds: a `toggle-pause` sent a moment
/// ago may not be applied yet. Nil when it says nothing for that long (Rambla is not there to answer).
func pausedOnceSteady(hold: Double = 1, timeout: Double = 10) -> Bool? {
    func reading() -> Int { (dump()["paused"] as? Bool).map { $0 ? 1 : 0 } ?? -1 }
    var value = reading()
    var since = Date()
    let end = Date().addingTimeInterval(timeout)
    while Date() < end, Date().timeIntervalSince(since) < hold {
        usleep(150_000)
        let now = reading()
        if now != value {
            value = now
            since = Date()
        }
    }
    return value < 0 ? nil : value == 1
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "wait-columns":
    let n = Int(args[1])!
    let ok = waitUntil { (currentStrip(dump()).map(columns)?.count ?? 0) == n }
    if ok { pass("strip has \(n) columns") } else { fail("expected \(n) columns, dump: \(currentStrip(dump()).map(columns)?.count ?? 0)") }
case "settle":
    // Wait for animations: two dumps 300 ms apart with identical real bounds.
    _ = waitUntil(4) {
        let a = windowIDs(currentStrip(dump()) ?? [:]).compactMap(bounds)
        usleep(300_000)
        let b = windowIDs(currentStrip(dump()) ?? [:]).compactMap(bounds)
        return a == b
    }
    pass("settled")
case "check-tiles":
    let d = dump()
    guard let s = currentStrip(d) else { fail("no current strip") }
    let disp = display(d)
    let frames = columns(s).compactMap { c -> CGRect? in
        let ids = (c["windows"] as? [NSNumber] ?? []).map(\.uint32Value)
        return ids.first.flatMap(bounds)
    }
    // Parked windows share the edge (1 pt visible); only compare windows that are really on screen.
    let onScreen = frames.filter { !$0.intersection(disp.frame).isNull && $0.intersection(disp.frame).width > 2 }
    for (a, b) in zip(onScreen, onScreen.dropFirst()) {
        let bothVisible = a.maxX <= disp.frame.maxX && b.minX >= disp.frame.minX && a.width > 2 && b.width > 2
        if b.minX <= a.minX { fail("columns not in increasing x order: \(a) then \(b)") }
        if bothVisible && b.minX - a.maxX > 1, abs((b.minX - a.maxX) - 8) > 2 { fail("gap \(b.minX - a.maxX) != 8±2 between \(a) and \(b)") }
    }
    pass("\(frames.count) columns in x order with 8 pt gaps")
case "check-parked":
    let d = dump()
    guard let s = currentStrip(d), let placements = s["placements"] as? [String: [String: Any]] else { fail("no strip") }
    let disp = display(d)
    var parked = 0
    for (key, p) in placements where (p["kind"] as? String) == "parked" {
        guard let id = UInt32(key), let real = bounds(id) else { continue }
        let inside = real.intersection(disp.frame)
        if inside.isNull || abs(inside.width - 1) > 0.5 { fail("parked window \(id) shows \(inside.isNull ? 0 : inside.width) pt (real \(real))") }
        parked += 1
    }
    pass("\(parked) parked windows show exactly 1 pt")
case "check-focused-visible":
    let d = dump()
    guard let focused = (d["focused"] as? NSNumber)?.uint32Value, let real = bounds(focused) else { fail("no focused window") }
    let disp = display(d)
    if disp.visible.insetBy(dx: -2, dy: -2).contains(real) { pass("focused window \(focused) fully visible") } else { fail("focused \(real) not inside \(disp.visible)") }
case "check-focused-index":
    let n = Int(args[1])!
    let d = dump()
    guard let s = currentStrip(d) else { fail("no strip") }
    let f = (s["focused"] as? NSNumber)?.intValue ?? -1
    if f == n { pass("focused column index \(n)") } else { fail("focused column index \(f), expected \(n)") }
case "check-gathered":
    let d = dump()
    let disp = display(d)
    let ids = ((d["windows"] as? [[String: Any]]) ?? []).compactMap { ($0["id"] as? NSNumber)?.uint32Value }
    // Nothing to look at (Rambla gave no dump, or knows no window) is no pass.
    guard !ids.isEmpty else { fail("the dump lists no windows") }
    var looked = 0
    for id in ids {
        guard let real = bounds(id) else { continue }
        looked += 1
        if !disp.visible.insetBy(dx: -2, dy: -2).contains(real) { fail("window \(id) at \(real) is outside \(disp.visible)") }
    }
    guard looked > 0 else { fail("none of the \(ids.count) windows in the dump has a window to look at") }
    pass("all \(looked) windows inside the visible area")
case "check-floating":
    let id = UInt32(args[1])!
    let d = dump()
    let floating = (d["floating"] as? [NSNumber] ?? []).map(\.uint32Value)
    if floating.contains(id) { pass("window \(id) is floating") } else { fail("window \(id) is not floating: \(floating)") }
case "check-frame":
    let id = UInt32(args[1])!, x = Double(args[2])!, y = Double(args[3])!
    guard let real = bounds(id) else { fail("no window \(id)") }
    if abs(real.minX - x) <= 2 && abs(real.minY - y) <= 2 { pass("window \(id) stayed at \(x),\(y)") } else { fail("window \(id) is at \(real.origin), expected \(x),\(y)") }
case "host":
    DistributedNotificationCenter.default().postNotificationName(Notification.Name("TestHost.command"), object: args[1], userInfo: nil, deliverImmediately: true)
    usleep(200_000)
    pass("host \(args[1])")
case "column-order":
    // The strip's columns, as the first window of each, in order.
    guard let s = currentStrip(dump()) else { failAside("no strip") }
    print(columns(s).compactMap { ($0["windows"] as? [NSNumber])?.first?.stringValue }.joined(separator: ","))
case "check-order":
    guard let s = currentStrip(dump()) else { fail("no strip") }
    let order = columns(s).compactMap { ($0["windows"] as? [NSNumber])?.first?.stringValue }.joined(separator: ",")
    let floating = (dump()["floating"] as? [NSNumber] ?? []).map(\.uint32Value)
    if !floating.isEmpty { fail("windows floating: \(floating)") }
    if order == args[1] { pass("columns in the same order: \(order)") } else { fail("columns \(order), expected \(args[1])") }
case "check-columns":
    // The strip's columns are these, in this order (windows floating since earlier steps do not matter).
    guard let s = currentStrip(dump()) else { fail("no strip") }
    let order = columns(s).compactMap { ($0["windows"] as? [NSNumber])?.first?.stringValue }.joined(separator: ",")
    if order == args[1] { pass("columns in the same order: \(order)") } else { fail("columns \(order), expected \(args[1])") }
case "window-at":
    let n = Int(args[1])!
    guard let s = currentStrip(dump()) else { failAside("no strip") }
    let cols = columns(s)
    guard cols.indices.contains(n), let id = (cols[n]["windows"] as? [NSNumber])?.first else { failAside("no column \(n)") }
    print(id.uint32Value)
case "check-placed":
    // Every window of the current strips (one per display) is exactly where its strip puts it (visible or parked).
    let d = dump()
    let current = (d["strips"] as? [[String: Any]] ?? []).filter { ($0["current"] as? Bool) == true }
    let placements = current.reduce(into: [String: [String: Any]]()) { all, s in
        all.merge(s["placements"] as? [String: [String: Any]] ?? [:]) { a, _ in a }
    }
    if placements.isEmpty { fail("no windows in the strips") }
    var misplaced: [String] = []
    for (key, p) in placements {
        guard let id = UInt32(key), let real = bounds(id), let f = p["frame"] as? [String: Double] else { continue }
        let want = CGRect(x: f["x"] ?? 0, y: f["y"] ?? 0, width: f["w"] ?? 0, height: f["h"] ?? 0)
        if abs(real.minX - want.minX) > 2 || abs(real.minY - want.minY) > 2 || abs(real.width - want.width) > 2 {
            misplaced.append("\(id) at \(Int(real.minX)),\(Int(real.minY)) \(Int(real.width)) instead of \(Int(want.minX)),\(Int(want.minY)) \(Int(want.width))")
        }
    }
    if misplaced.isEmpty { pass("\(placements.count) windows where the strip puts them") } else { fail("misplaced: \(misplaced.joined(separator: "; "))") }
case "wait-displays":
    // N [SECONDS]: waits until N displays are on (the lid opened or closed by hand).
    let n = Int(args[1])!, timeout = Double(args.count > 2 ? args[2] : "120")!
    if waitUntil(timeout, { activeDisplays() == n }) { pass("\(n) displays") } else { fail("still \(activeDisplays()) displays") }
case "other-display":
    // The display that is not the one the test windows open on.
    let ids = ((dump()["displays"] as? [[String: Any]]) ?? []).compactMap { $0["uuid"] as? String }
    guard ids.count > 1 else { fail("one display only") }
    print(ids[1])
case "wait-columns-on":
    // UUID N [SECONDS]: the current strip of that display has N columns.
    let uuid = args[1], n = Int(args[2])!, timeout = Double(args.count > 3 ? args[3] : "15")!
    func count() -> Int {
        let strips = (dump()["strips"] as? [[String: Any]] ?? []).filter { ($0["display"] as? String) == uuid && ($0["current"] as? Bool) == true }
        return strips.first.map { columns($0).count } ?? 0
    }
    if waitUntil(timeout, { count() == n }) { pass("display \(uuid.prefix(8)) has \(n) columns") } else { fail("display \(uuid.prefix(8)) has \(count()) columns, expected \(n)") }
case "watch-until-displays":
    // N sliver|half ID: samples the window until N displays are on (the lid opened or closed by hand), and 8 s more.
    // On the display it started on it never shows more than its sliver, or than half of it (it never crosses it).
    // macOS itself may push a parked window onto that display as the other one appears: a flash shorter than 0.15 s
    // is that, not Rambla moving it across.
    let n = Int(args[1])!, half = args[2] == "half", id = UInt32(args[3])!
    let disp = display(dump()).frame
    var samples: [(at: Date, frame: CGRect)] = []
    var end: Date?
    let deadline = Date().addingTimeInterval(120)
    while Date() < (end ?? deadline) {
        if let b = bounds(id) { samples.append((Date(), b)) }
        if end == nil, activeDisplays() == n { end = Date().addingTimeInterval(8) }
        usleep(4_000)
    }
    if end == nil { fail("the displays did not change") }
    let frames = samples.map(\.frame)
    let limit = half ? (frames.first?.width ?? 0) / 2 : 3
    var longest = 0.0, since: Date?
    for sample in samples {
        if shown(sample.frame, on: disp) > limit {
            since = since ?? sample.at
            longest = max(longest, sample.at.timeIntervalSince(since!))
        } else {
            since = nil
        }
    }
    let most = frames.map { shown($0, on: disp) }.max() ?? 0
    if longest < 0.15 {
        pass("window \(id) showed at most \(Int(most)) pt, over its limit for \(Int(longest * 1000)) ms (\(frames.count) samples)")
    } else {
        fail("window \(id) showed \(Int(most)) pt for \(Int(longest * 1000)) ms at x: \(trace(frames, on: disp))")
    }
case "neighbor-right":
    // Arguments for `rambla debug-neighbor`: a laptop-sized display right of the strip's one.
    let f = display(dump()).frame
    guard f.width > 0 else { failAside("no display in the dump") }
    print("\(Int(f.maxX)) \(Int(f.minY)) 1512 \(Int(f.height))")
case "watch-hidden":
    // ID COMMAND...: while the command runs, the window never shows more than its sliver.
    let id = UInt32(args[1])!
    let disp = display(dump()).frame
    let frames = samples(id, running: Array(args.dropFirst(2)))
    let most = frames.map { shown($0, on: disp) }.max() ?? 0
    if frames.count < 50 { fail("only \(frames.count) samples of window \(id)") }
    if most <= 3 { pass("window \(id) stayed out of sight") } else { fail("window \(id) showed \(most) pt at x: \(trace(frames, on: disp))") }
case "watch-enters", "watch-leaves":
    // ID right|left COMMAND...: the window comes into view (or goes out of it) through that side only, so every frame
    // that shows lies on that side of where it ends (or starts): it never crosses the display on the way.
    let id = UInt32(args[1])!, right = args[2] == "right", entering = args[0] == "watch-enters"
    let disp = display(dump()).frame
    guard let before = bounds(id) else { fail("no window \(id)") }
    let frames = samples(id, running: Array(args.dropFirst(3)))
    guard let after = frames.last else { fail("no samples of window \(id)") }
    let reference = entering ? after : before
    if entering != (shown(after, on: disp) > 3) { fail("window \(id) did not \(entering ? "come into" : "leave") view: \(after)") }
    let wrong = frames.filter { shown($0, on: disp) > 3 && (right ? $0.minX < reference.minX - 2 : $0.minX > reference.minX + 2) }
    if wrong.isEmpty {
        pass("window \(id) \(entering ? "came in" : "went out") through the \(args[2]) side")
    } else {
        fail("window \(id) crossed the display at x: \(trace(frames, on: disp)) (\(entering ? "ends" : "starts") at \(Int(reference.minX)))")
    }
case "watch-reparked":
    // ID COMMAND...: the command moves window ID, parked out of sight, away from its parking spot (another app moving
    // it), and Rambla parks it again: while it runs, the window is seen away from that spot (or at another size), and
    // it ends back there. A window that never moved would pass a check of where it ends alone.
    let id = UInt32(args[1])!
    guard let spot = bounds(id) else { fail("no window \(id)") }
    func atSpot(_ r: CGRect) -> Bool {
        abs(r.minX - spot.minX) <= 2 && abs(r.minY - spot.minY) <= 2 && abs(r.width - spot.width) <= 2
            && abs(r.height - spot.height) <= 2
    }
    func describe(_ r: CGRect) -> String { "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))" }
    let frames = samples(id, running: Array(args.dropFirst(2)))
    if frames.count < 50 { fail("only \(frames.count) samples of window \(id)") }
    guard let away = frames.first(where: { !atSpot($0) }) else {
        fail("window \(id) was never seen away from its parking spot at \(describe(spot)) (\(frames.count) samples): "
             + "the move did not happen, so nothing shows it was parked again")
    }
    guard let last = frames.last, atSpot(last) else {
        fail("window \(id) was moved to \(describe(away)) and is not back at its parking spot \(describe(spot)): "
             + "it is at \(frames.last.map(describe) ?? "?")")
    }
    pass("window \(id) was moved to \(describe(away)) and parked again at \(describe(spot))")
case "watch-moves-once":
    // ID COMMAND...: while the command runs, window ID goes where it goes in a single move: its corner changes at most
    // once (by more than 2 pt), never to a first place and then on to another (a strip laid out where it was, then
    // scrolled to the column that gets the focus: a switch in two steps).
    let id = UInt32(args[1])!
    let frames = samples(id, running: Array(args.dropFirst(2)))
    if frames.count < 50 { fail("only \(frames.count) samples of window \(id)") }
    var places: [CGPoint] = []
    for frame in frames where places.last.map({ abs($0.x - frame.minX) > 2 || abs($0.y - frame.minY) > 2 }) ?? true {
        places.append(frame.origin)
    }
    let path = places.prefix(12).map { "\(Int($0.x)),\(Int($0.y))" }.joined(separator: " → ")
        + (places.count > 12 ? " → …" : "")
    if places.count <= 2 {
        pass("window \(id) moved at most once: \(path)")
    } else {
        fail("window \(id) moved \(places.count - 1) times on the way: \(path)")
    }
case "check-levels", "check-levels-on":
    // COUNT ACTIVE [SECONDS]  (check-levels-on: UUID COUNT ACTIVE [SECONDS]): the stack in view on the display of the test
    // windows (or on that one) has COUNT levels, 0 to COUNT - 1, and ACTIVE is the one in view. It is there while the
    // level in view is empty too, which `currentStrip` is not.
    let on = args[0] == "check-levels-on"
    let uuid = on ? args[1] : nil
    let rest = Array(args.dropFirst(on ? 2 : 1))
    let count = Int(rest[0])!, active = Int(rest[1])!, timeout = Double(rest.count > 2 ? rest[2] : "6")!
    let whose = uuid.map { "display \($0.prefix(8))" } ?? "the display of the test windows"
    let wanted = "\(count) strips, level \(active) in view"
    func found() -> String { stackInView(dump(), on: uuid).map { "\($0.top + 1) strips, level \($0.active) in view" } ?? "no stack" }
    if waitUntil(timeout, { found() == wanted }) { pass("\(whose) has \(wanted)") } else { fail("\(whose) has \(found()), expected \(wanted)") }
case "check-shelved":
    // COUNT [X Y W H]: the windows out of view are COUNT (those of the levels not in view of the stacks in view, and the
    // floating windows parked with them), and each shows at most its sliver (and 1 pt) on its own display and nothing on
    // any other: the real ones, and the one `debug-neighbor` plugs at X Y W H. It waits for them to get there, as the
    // moves of windows out of sight are not tracked by `settle`.
    guard args.count >= 2, let count = Int(args[1]) else { fail("usage: check-shelved COUNT [X Y W H]") }
    let extra = pluggedDisplay(args, from: 2)
    var problems: [String] = []
    var out: [OutOfView] = []
    let ok = waitUntil {
        let d = dump()
        let all = dumpDisplays(d)
        out = outOfView(d)
        problems = out.compactMap { w in
            exposure(of: w.id, on: w.display, among: all, extra: extra)
                .map { "window \(w.id) (level \(w.level)\(w.float ? ", floating" : "")) \($0)" }
        }
        if out.count != count { problems.insert("\(out.count) windows are out of view, expected \(count)", at: 0) }
        return problems.isEmpty
    }
    if ok {
        pass("\(out.count) windows out of view (\(out.filter(\.float).count) floating) show at most \(Int(sliver + 1)) pt")
    } else {
        fail(problems.joined(separator: "; "))
    }
case "check-float-parked":
    // ID [X Y W H]: window ID is parked with a level out of view (it is in `floatShelf`), and hides as the windows of that
    // level do (`check-shelved`).
    let id = UInt32(args[1])!
    let extra = pluggedDisplay(args, from: 2)
    var problem = ""
    let ok = waitUntil {
        let d = dump()
        let all = dumpDisplays(d)
        let parked = all.flatMap { parkedFloats(d, on: $0) }
        guard let shelf = parked.first(where: { $0.id == id }) else {
            problem = "window \(id) is not parked with any level (floatShelf has \(parked.map(\.id)))"
            return false
        }
        if let view = stackInView(d, on: shelf.display.uuid), view.active == shelf.level {
            problem = "window \(id) is parked with level \(shelf.level), which is the one in view"
            return false
        }
        if let why = exposure(of: id, on: shelf.display, among: all, extra: extra) {
            problem = "floating window \(id) (parked with level \(shelf.level)) \(why)"
            return false
        }
        return true
    }
    if ok { pass("floating window \(id) is parked out of sight") } else { fail(problem) }
case "level-of":
    // ID [LEVEL [SECONDS]]: prints the level of the strip that holds window ID, at any level; with LEVEL, checks that it is
    // that one instead.
    let id = UInt32(args[1])!
    if args.count > 2 {
        let want = Int(args[2])!, timeout = Double(args.count > 3 ? args[3] : "6")!
        if waitUntil(timeout, { levelHolding(id, in: dump()) == want }) {
            pass("window \(id) is on level \(want)")
        } else {
            fail("window \(id) is on level \(levelHolding(id, in: dump()).map(String.init) ?? "none (no strip holds it)"), expected \(want)")
        }
    } else {
        var found: Int?
        let held = waitUntil { found = levelHolding(id, in: dump()); return found != nil }
        guard held, let level = found else { failAside("no strip holds window \(id)") }
        print(level)
    }
case "check-not-floating":
    // ID: window ID is in a strip, not floating (what a window another app moves while it is out of sight must stay).
    let id = UInt32(args[1])!
    let d = dump()
    guard !d.isEmpty else { fail("no dump") }
    let floating = (d["floating"] as? [NSNumber] ?? []).map(\.uint32Value)
    if floating.contains(id) { fail("window \(id) is floating: \(floating)") }
    guard let level = levelHolding(id, in: d) else { fail("window \(id) is in no strip") }
    pass("window \(id) is not floating; it is on level \(level)")
case "frame-of":
    // ID: where window ID is, once it stops moving, as the X Y W H that `check-frame-near` takes.
    let id = UInt32(args[1])!
    var last: CGRect?
    let steady = waitUntil(4) {
        let before = bounds(id)
        usleep(300_000)
        last = bounds(id)
        return before != nil && before == last
    }
    guard steady, let f = last else {
        failAside("window \(id) \(bounds(id).map { "keeps moving: \($0)" } ?? "is gone")")
    }
    print("\(Int(f.minX.rounded())) \(Int(f.minY.rounded())) \(Int(f.width.rounded())) \(Int(f.height.rounded()))")
case "check-frame-near":
    // ID X Y W H: window ID is at that frame, in every number within 2 pt (`check-frame` looks at the corner only).
    let id = UInt32(args[1])!
    let v = args.dropFirst(2).compactMap(Double.init)
    guard args.count == 6, v.count == 4 else { fail("usage: check-frame-near ID X Y W H") }
    let want = CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
    func near(_ r: CGRect) -> Bool {
        abs(r.minX - want.minX) <= 2 && abs(r.minY - want.minY) <= 2 && abs(r.width - want.width) <= 2 && abs(r.height - want.height) <= 2
    }
    func describe(_ r: CGRect) -> String { "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))" }
    let there = waitUntil { bounds(id).map(near) ?? false }
    if there {
        pass("window \(id) is at \(bounds(id).map(describe) ?? "?"), where it was (\(describe(want)))")
    } else {
        fail("window \(id) is at \(bounds(id).map(describe) ?? "nowhere"), expected \(describe(want))")
    }
case "window-number":
    // ID: the number the test app gives window ID, for `host "focus N"`: the one in its title ("Prueba N").
    let id = UInt32(args[1])!
    let title = ((dump()["windows"] as? [[String: Any]]) ?? []).first { ($0["id"] as? NSNumber)?.uint32Value == id }?["title"] as? String
    guard let number = title?.split(separator: " ").last.flatMap({ Int($0) }) else {
        failAside("window \(id) has no test app number in its title: \(title ?? "no such window")")
    }
    print(number)
case "pointer-to-display":
    // The strip commands that start from nothing focused (an empty strip in view) act on the display under the pointer:
    // put it on the display of the test windows, if it is on another one.
    let frame = display(dump()).frame
    guard frame.width > 0 else { fail("no display in the dump") }
    let mouse = NSEvent.mouseLocation
    let pointer = CGPoint(x: mouse.x, y: (NSScreen.screens.first?.frame.height ?? 0) - mouse.y)
    if frame.contains(pointer) {
        pass("the pointer is on the display of the test windows")
    } else {
        CGWarpMouseCursorPosition(CGPoint(x: frame.midX, y: frame.midY))
        CGAssociateMouseAndMouseCursorPosition(1)
        pass("the pointer went to the display of the test windows")
    }
case "check-paused":
    // true|false [SECONDS]: Rambla is paused (true) or active (false), as a `toggle-pause` leaves it.
    let want = args[1] == "true", timeout = Double(args.count > 2 ? args[2] : "6")!
    let there = waitUntil(timeout) { dump()["paused"] as? Bool == want }
    if there { pass("Rambla is \(want ? "paused" : "active")") } else { fail("Rambla is not \(want ? "paused" : "active"), as it should be") }
case "resume":
    // Resumes Rambla if it is paused, for a run that fails between two `toggle-pause`: its preferences keep a pause across
    // launches, and a reinstall does not undo it. `toggle-pause` only flips, so it is sent only when the dump says paused,
    // and only once the dump has said so for a second (a toggle sent a moment ago may not be applied yet).
    guard let paused = pausedOnceSteady() else { fail("Rambla does not answer: it cannot tell whether it is paused") }
    if paused {
        _ = run(["toggle-pause"])
        let resumed = waitUntil { dump()["paused"] as? Bool == false }
        if resumed { pass("Rambla was paused: resumed") } else { fail("Rambla is still paused") }
    } else {
        pass("Rambla is not paused")
    }
case "frontmost-is":
    // BUNDLE [SECONDS]: the app in front is BUNDLE. A focus that reaches a window of the app in front is the app moving
    // between its own windows; one that comes with another app being activated (⌘Tab, the Dock) is routed differently.
    let want = args[1], timeout = Double(args.count > 2 ? args[2] : "3")!
    func front() -> String {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))   // lets the workspace hear of a change
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "no app"
    }
    let there = waitUntil(timeout) { front() == want }
    if there {
        pass("\(want) is the app in front")
    } else {
        fail("the app in front is \(front()), not \(want): a focus given to a window of \(want) now would be an activation, not a move between its windows")
    }
default:
    print("usage: e2e-check wait-columns N | settle | check-tiles | check-parked | check-focused-visible | check-focused-index N | check-gathered | check-floating ID | check-frame ID X Y | column-order | check-order IDS | check-columns IDS | window-at N | neighbor-right | watch-hidden ID COMMAND... | watch-enters ID right|left COMMAND... | watch-leaves ID right|left COMMAND... | wait-displays N [S] | other-display | wait-columns-on UUID N [S] | watch-until-displays N sliver|half ID | watch-reparked ID COMMAND... | watch-moves-once ID COMMAND... | check-levels COUNT ACTIVE [S] | check-levels-on UUID COUNT ACTIVE [S] | check-shelved COUNT [X Y W H] | check-float-parked ID [X Y W H] | level-of ID [LEVEL [S]] | check-not-floating ID | frame-of ID | check-frame-near ID X Y W H | window-number ID | pointer-to-display | check-paused true|false [S] | resume | frontmost-is BUNDLE [S]")
    exit(2)
}
