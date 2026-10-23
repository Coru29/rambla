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

/// How much of `r` shows on `display`, in points across.
func shown(_ r: CGRect, on display: CGRect) -> Double {
    r.intersects(display) ? r.intersection(display).width : 0
}

func trace(_ frames: [CGRect], on display: CGRect) -> String {
    frames.filter { shown($0, on: display) > 3 }.map { "\(Int($0.minX))" }.joined(separator: " ")
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
    for id in ids {
        guard let real = bounds(id) else { continue }
        if !disp.visible.insetBy(dx: -2, dy: -2).contains(real) { fail("window \(id) at \(real) is outside \(disp.visible)") }
    }
    pass("all \(ids.count) windows inside the visible area")
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
    guard let s = currentStrip(dump()) else { fail("no strip") }
    print(columns(s).compactMap { ($0["windows"] as? [NSNumber])?.first?.stringValue }.joined(separator: ","))
case "check-order":
    guard let s = currentStrip(dump()) else { fail("no strip") }
    let order = columns(s).compactMap { ($0["windows"] as? [NSNumber])?.first?.stringValue }.joined(separator: ",")
    let floating = (dump()["floating"] as? [NSNumber] ?? []).map(\.uint32Value)
    if !floating.isEmpty { fail("windows floating: \(floating)") }
    if order == args[1] { pass("columns in the same order: \(order)") } else { fail("columns \(order), expected \(args[1])") }
case "window-at":
    let n = Int(args[1])!
    guard let s = currentStrip(dump()) else { fail("no strip") }
    let cols = columns(s)
    guard cols.indices.contains(n), let id = (cols[n]["windows"] as? [NSNumber])?.first else { fail("no column \(n)") }
    print(id.uint32Value)
case "neighbor-right":
    // Arguments for `rambla debug-neighbor`: a laptop-sized display right of the strip's one.
    let f = display(dump()).frame
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
default:
    print("usage: e2e-check wait-columns N | settle | check-tiles | check-parked | check-focused-visible | check-focused-index N | check-gathered | check-floating ID | check-frame ID X Y | column-order | check-order IDS | window-at N | neighbor-right | watch-hidden ID COMMAND... | watch-enters ID right|left COMMAND... | watch-leaves ID right|left COMMAND...")
    exit(2)
}
