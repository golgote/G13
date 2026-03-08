// =============================================================
//  G13App.swift
//  App entry point -- menu bar application
// =============================================================

import SwiftUI

@main
struct G13App: App {

    @StateObject private var device = G13Device()
    @StateObject private var keyMapper = KeyMapper()
    @StateObject private var profileManager = ProfileManager()

    var body: some Scene {
        MenuBarExtra("G13", systemImage: "gamecontroller.fill") {
            MenuBarView(device: device, keyMapper: keyMapper, profileManager: profileManager)
        }
    }
}
