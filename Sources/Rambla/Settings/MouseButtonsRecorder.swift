import AppKit
import RamblaCore
import SwiftUI

/// A button that records the mouse buttons of the "Botones del mouse" gestures: click, then press the buttons together
/// and let go. Clicking again, leaving the page or switching to another app cancels.
struct MouseButtonsRecorder: View {
    @Binding var buttons: [Int]
    let backend: SettingsBackend?

    @State private var isRecording = false
    /// The buttons down right now, while recording.
    @State private var pressed: [Int] = []

    static let width: CGFloat = 190

    var body: some View {
        Button(action: toggle) {
            Text(label)
                .font(.callout)
                .foregroundStyle(isRecording ? Color.accentColor : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(RecorderPillStyle(isRecording: isRecording, isFlagged: false, width: Self.width))
        .disabled(backend == nil)
        .help(isRecording ? "Apretá juntos los botones que quieras usar y soltalos; un clic acá cancela"
                          : "Hacé clic y apretá los botones del mouse")
        .accessibilityLabel("Botones")
        .accessibilityValue(label)
        .onDisappear(perform: cancel)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in cancel() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in cancel() }
    }

    private var label: String {
        guard isRecording else { return KeyNames.mouseButtons(buttons) }
        return pressed.isEmpty ? String(localized: "Apretá los botones…") : KeyNames.mouseButtons(pressed)
    }

    private func toggle() {
        guard let backend else { return }
        if isRecording {
            cancel()
            return
        }
        pressed = []
        isRecording = true
        backend.recordMouseButtons(onChange: { pressed = $0 }, onDone: { recorded in
            buttons = recorded
            isRecording = false
            pressed = []
        })
    }

    private func cancel() {
        guard isRecording else { return }
        backend?.stopRecordingMouseButtons()
        isRecording = false
        pressed = []
    }
}
