import AppKit
import SwiftUI

// Captures keys in this field only. The local monitor sees Command shortcuts
// before AppKit routes them to the app menu; it is removed with the view.
struct ShortcutCaptureField: NSViewRepresentable {
    let value: String
    let focusRequest: Int
    let onCapture: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> CaptureTextField {
        let field = CaptureTextField()
        field.placeholderString = "Click, then press shortcut"
        field.isEditable = false
        field.isSelectable = false
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .exterior
        field.cell?.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.setCurrentShortcut(value)
        context.coordinator.field = field
        context.coordinator.lastFocusRequest = focusRequest
        context.coordinator.onCapture = onCapture
        if focusRequest > 0 { field.requestFocus() }
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak coordinator = context.coordinator] event in
            guard let coordinator,
                  let field = coordinator.field,
                  event.window === field.window,
                  field.window?.firstResponder === field else { return event }
            if event.keyCode == 0x35 {
                field.window?.makeFirstResponder(nil)
                return nil
            }
            coordinator.capture(event)
            return nil
        }
        return field
    }

    func updateNSView(_ field: CaptureTextField, context: Context) {
        field.setCurrentShortcut(value)
        context.coordinator.onCapture = onCapture
        if focusRequest != context.coordinator.lastFocusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            if focusRequest > 0 { field.requestFocus() }
        }
    }

    static func dismantleNSView(_ field: CaptureTextField, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
        coordinator.field = nil
    }

    final class Coordinator {
        weak var field: CaptureTextField?
        var monitor: Any?
        var lastFocusRequest = 0
        var onCapture: ((String) -> Void)?

        func capture(_ event: NSEvent) {
            guard !event.isARepeat else { return }
            guard let shortcut = Self.shortcut(for: event) else { return }
            field?.showCapturedShortcut(shortcut)
            onCapture?(shortcut)
            field?.window?.makeFirstResponder(nil)
        }

        static func shortcut(for event: NSEvent) -> String? {
            G13ShortcutDecoder.shortcut(for: event)
        }
    }
}

final class CaptureTextField: NSTextField {
    private var currentShortcut = ""
    private var isReady = false
    private var didCapture = false
    private var focusWhenAttached = false

    override var acceptsFirstResponder: Bool { true }

    func requestFocus() {
        focusWhenAttached = true
        if let window {
            focusWhenAttached = false
            window.makeFirstResponder(self)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if focusWhenAttached, let window {
            focusWhenAttached = false
            window.makeFirstResponder(self)
        }
    }

    func setCurrentShortcut(_ value: String) {
        currentShortcut = value
        if !isReady || didCapture { stringValue = value }
    }

    func showCapturedShortcut(_ value: String) {
        currentShortcut = value
        didCapture = true
        stringValue = value
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        isReady = true
        didCapture = false
        stringValue = "●  Press shortcut"
        drawsBackground = true
        backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        isReady = false
        stringValue = currentShortcut
        backgroundColor = .controlBackgroundColor
        layer?.borderWidth = 0
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard isReady, !didCapture else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var names: [String] = []
        if flags.contains(.command) { names.append("Cmd") }
        if flags.contains(.control) { names.append("Ctrl") }
        if flags.contains(.option) { names.append("Opt") }
        if flags.contains(.shift) { names.append("Shift") }
        stringValue = names.isEmpty ? "●  Press shortcut" : names.joined(separator: " + ") + " + …"
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }
}
