import AppKit
import SwiftUI

/// A short message in the middle of a display that fades out on its own, for something Rambla has nothing to show for:
/// the overview of a display without windows, and a strip that came into view empty, say how to bring a window.
/// Click-through, like the focus border.
@MainActor
final class HintController {
    private static let visibleDuration: TimeInterval = 2.5
    private static let fadeDuration: TimeInterval = 0.3
    private static let cornerRadius: CGFloat = 14

    private var window: NSWindow?
    private var hosting: NSHostingView<HintContent>?
    private var hideWork: DispatchWorkItem?
    /// Invalidates the completion of a fade that a newer `show` cancelled.
    private var fadeToken = 0

    func show(_ title: String, detail: String, on screen: NSScreen) {
        let window = window ?? makeWindow()
        guard let hosting else { return }
        let content = HintContent(title: title, detail: detail)
        hosting.rootView = content
        // The view's ideal size leaves the wrapped detail one line short: measure it at the width it wraps to.
        let visible = screen.visibleFrame
        let size = NSHostingController(rootView: content).sizeThatFits(in: CGSize(width: visible.width - 24, height: visible.height))
        let width = min(size.width, visible.width - 24)
        window.setFrame(CGRect(x: (visible.midX - width / 2).rounded(), y: (visible.midY - size.height / 2).rounded(),
                               width: width, height: size.height), display: true)
        hosting.frame = window.contentView?.bounds ?? .zero
        fadeToken += 1
        window.alphaValue = 1
        window.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.fadeOut() } }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleDuration, execute: work)
    }

    /// Fades the hint out now instead of when its time is up: what it says no longer holds (the empty strip it was about
    /// was left for one with windows), or something else takes its place (the overview).
    func hide() {
        guard let window, window.isVisible else { return }
        hideWork?.cancel()
        hideWork = nil
        fadeOut()
    }

    private func fadeOut() {
        guard let window else { return }
        fadeToken += 1
        let token = fadeToken
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeDuration
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.fadeToken == token else { return }
                window.orderOut(nil)
            }
        })
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        // The window is never key, and the default state would draw the flat "inactive window" look.
        background.state = .active
        background.appearance = NSAppearance(named: .vibrantDark)
        background.maskImage = OverlayStyle.roundedMask(radius: Self.cornerRadius)
        let hosting = NSHostingView(rootView: HintContent(title: "", detail: ""))
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)
        window.contentView = background

        self.window = window
        self.hosting = hosting
        return window
    }
}

private struct HintContent: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }
}
