// =============================================================
//  SettingsWindowController.swift
//  Manages the settings window via AppKit (like Clipy does)
// =============================================================

import SwiftUI

class SettingsWindowController {

    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(device: G13Device, keyMapper: KeyMapper, profileManager: ProfileManager) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = ContentView(
            device: device,
            keyMapper: keyMapper,
            profileManager: profileManager
        )

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "G13 Settings"
        newWindow.contentView = NSHostingView(rootView: contentView)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.isRestorable = false
        newWindow.setFrameAutosaveName("G13Settings")

        self.window = newWindow

        newWindow.makeKeyAndOrderFront(nil)
        newWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}
