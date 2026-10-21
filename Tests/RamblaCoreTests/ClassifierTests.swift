import Testing
@testable import RamblaCore

private let ownBundle = "io.github.coru29.Rambla"

/// A perfectly ordinary document window: the only thing that makes it differ is what each test changes.
private let ordinaryWindow = WindowTraits(
    role: "AXWindow", subrole: "AXStandardWindow", isResizable: true, isMinimized: false,
    isFullscreen: false, hasCloseButton: true, bundleID: "com.apple.TextEdit", appIsRegular: true)

private func classify(_ traits: WindowTraits, rules: [AppRule] = []) -> WindowKind {
    Classifier.classify(traits, rules: rules, ownBundleID: ownBundle)
}

private func changed(_ edit: (inout WindowTraits) -> Void) -> WindowTraits {
    var traits = ordinaryWindow
    edit(&traits)
    return traits
}

@Test func classifierOrder() {
    let floatRule = AppRule(bundleID: "com.apple.TextEdit", name: "TextEdit", behavior: .float)

    // 9. otherwise tile
    #expect(classify(ordinaryWindow) == .tile)
    // 1. role is not AXWindow -> ignore
    #expect(classify(changed { $0.role = "AXSheet" }) == .ignore)
    #expect(classify(changed { $0.role = nil }) == .ignore)
    // 2. the app is not regular (accessory or background app) -> ignore
    #expect(classify(changed { $0.appIsRegular = false }) == .ignore)
    // 3. a window of Rambla itself -> ignore
    #expect(classify(changed { $0.bundleID = ownBundle }) == .ignore)
    // 4. native full screen -> ignore
    #expect(classify(changed { $0.isFullscreen = true }) == .ignore)
    // 5. an app rule that floats the app -> float
    #expect(classify(ordinaryWindow, rules: [floatRule]) == .float)
    // 6. not a standard window (dialog, floating panel, Quick Look...) -> float
    #expect(classify(changed { $0.subrole = "AXDialog" }) == .float)
    #expect(classify(changed { $0.subrole = "AXFloatingWindow" }) == .float)
    #expect(classify(changed { $0.subrole = nil }) == .float)
    // 7. not resizable -> float
    #expect(classify(changed { $0.isResizable = false }) == .float)
    // 8. no close button -> float
    #expect(classify(changed { $0.hasCloseButton = false }) == .float)
}

@Test func classifierEarlierRulesWinOverLaterOnes() {
    let floatRule = AppRule(bundleID: "com.apple.TextEdit", name: "TextEdit", behavior: .float)

    // role beats everything below it
    let sheet = changed { $0.role = "AXSheet"; $0.subrole = "AXDialog"; $0.isResizable = false }
    #expect(classify(sheet, rules: [floatRule]) == .ignore)
    // not-regular beats the later checks (full screen, rules)
    #expect(classify(changed { $0.appIsRegular = false; $0.isFullscreen = true }, rules: [floatRule]) == .ignore)
    // own windows are ignored, never floated, even if somebody wrote a rule for them
    let ownRule = AppRule(bundleID: ownBundle, name: "Rambla", behavior: .float)
    #expect(classify(changed { $0.bundleID = ownBundle }, rules: [ownRule]) == .ignore)
    // full screen is ignored (it leaves the strip) rather than floated by a rule
    #expect(classify(changed { $0.isFullscreen = true }, rules: [floatRule]) == .ignore)
    // a float rule on a window that would float anyway is still float
    #expect(classify(changed { $0.subrole = "AXDialog" }, rules: [floatRule]) == .float)
}

@Test func classifierRulesOnlyApplyToTheirBundle() {
    let otherRule = AppRule(bundleID: "com.apple.finder", name: "Finder", behavior: .float)
    #expect(classify(ordinaryWindow, rules: [otherRule]) == .tile)
    // A window without a bundle id matches no rule.
    #expect(classify(changed { $0.bundleID = nil }, rules: [otherRule]) == .tile)
    // A tile rule does not rescue windows that are not tileable.
    let tileRule = AppRule(bundleID: "com.apple.TextEdit", name: "TextEdit", behavior: .tile)
    #expect(classify(ordinaryWindow, rules: [tileRule]) == .tile)
    #expect(classify(changed { $0.subrole = "AXDialog" }, rules: [tileRule]) == .float)
    #expect(classify(changed { $0.isResizable = false }, rules: [tileRule]) == .float)
    // The first rule for a bundle decides.
    let floatFirst = AppRule(bundleID: "com.apple.TextEdit", name: "TextEdit", behavior: .float)
    #expect(classify(ordinaryWindow, rules: [floatFirst, tileRule]) == .float)
    #expect(classify(ordinaryWindow, rules: [tileRule, floatFirst]) == .tile)
}

@Test func classifierIgnoresMinimizedFlag() {
    // Minimized windows stay in the strip (their column collapses), so the flag is not a classification input.
    #expect(classify(changed { $0.isMinimized = true }) == .tile)
}
