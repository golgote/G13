import AppKit
import SwiftUI

// Watches only the command editor's window while Record is on. A local key-down
// monitor receives Command shortcuts before AppKit routes them to menu items.
// Modifier transitions are never saved as partial command steps.
struct CommandShortcutRecorder: NSViewRepresentable {
    let isRecording: Bool
    let onShortcut: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.isRecording = isRecording
        context.coordinator.onShortcut = onShortcut
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak coordinator = context.coordinator] event in
            guard let coordinator, coordinator.isRecording,
                  let window = coordinator.view?.window,
                  event.window === window else { return event }
            guard !event.isARepeat,
                  let shortcut = G13ShortcutDecoder.shortcut(for: event) else {
                return event
            }
            coordinator.onShortcut?(shortcut)
            return nil
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.isRecording = isRecording
        context.coordinator.onShortcut = onShortcut
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
        coordinator.view = nil
    }

    final class Coordinator {
        weak var view: NSView?
        var monitor: Any?
        var isRecording = false
        var onShortcut: ((String) -> Void)?
    }
}
