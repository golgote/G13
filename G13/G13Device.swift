// =============================================================
//  G13Device.swift
//  USB communication with the Logitech G13 via IOKit HID.
//  Supports automatic reconnection on plug/unplug.
// =============================================================

import Foundation
import Combine
import IOKit
import IOKit.hid

class G13Device: ObservableObject {

    static let vendorID:  Int = 0x046D
    static let productID: Int = 0xC21C

    // -- Published state for SwiftUI --
    @Published var isConnected = false
    @Published var pressedKeys: Set<String> = []
    @Published var joystickX: UInt8 = 127
    @Published var joystickY: UInt8 = 127

    // -- Internal references --
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var reportBuffer = [UInt8](repeating: 0, count: 8)
    private var previousReport = Data(count: 8)
    private var isFirstReport = true

    let lcd = G13LCD()

    // Callbacks for key and joystick events
    var onKeyChanged: ((_ keyName: String, _ isPressed: Bool) -> Void)?
    var onJoystickChanged: ((_ x: UInt8, _ y: UInt8) -> Void)?

    // Called when the device connects (or reconnects)
    var onDeviceConnected: (() -> Void)?

    // Called when the device disconnects
    var onDeviceDisconnected: (() -> Void)?

    // Key names ordered by bit position in bytes 3-7 of the input report
    static let keyNames: [String] = [
        "G1",  "G2",  "G3",  "G4",  "G5",  "G6",  "G7",  "G8",
        "G9",  "G10", "G11", "G12", "G13", "G14", "G15", "G16",
        "G17", "G18", "G19", "G20", "G21", "G22", "UNDEF1", "LIGHT_STATE",
        "BD",  "L1",  "L2",  "L3",  "L4",  "M1",  "M2",  "M3",
        "MR",  "LEFT", "RIGHT", "STICK", "UNDEF2", "LIGHT", "LIGHT2", "MISC_TOGGLE"
    ]

    static let ignoredKeys: Set<String> = [
        "MISC_TOGGLE", "LIGHT_STATE", "UNDEF1", "UNDEF2", "LIGHT", "LIGHT2"
    ]

    // MARK: - Start / Stop monitoring

    // Start monitoring for G13 connections and disconnections.
    // This should be called once at app startup. It will automatically
    // handle connect/disconnect events for the lifetime of the app.
    func startMonitoring() {
        guard manager == nil else { return }

        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = manager else { return }

        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey as String: G13Device.vendorID,
            kIOHIDProductIDKey as String: G13Device.productID
        ] as CFDictionary)

        // Register callbacks for device matching (plug in) and removal (unplug).
        // We pass 'self' as the opaque context pointer.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, g13DeviceMatchedCallback, selfPtr)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, g13DeviceRemovedCallback, selfPtr)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            print("[G13Device] Failed to open HID Manager: \(String(format: "0x%08X", openResult))")
        } else {
            print("[G13Device] Monitoring for G13 connections...")
        }
    }

    // Stop monitoring and disconnect
    func stopMonitoring() {
        detachDevice()
        if let manager = manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        print("[G13Device] Stopped monitoring")
    }

    // Legacy connect method for compatibility. Now just starts monitoring.
    func connect() {
        startMonitoring()
    }

    func disconnect() {
        stopMonitoring()
    }

    // MARK: - Device attach / detach (called from callbacks)

    fileprivate func attachDevice(_ newDevice: IOHIDDevice) {
        // If we already have a device, detach it first
        if device != nil {
            detachDevice()
        }

        device = newDevice
        isConnected = true
        isFirstReport = true
        previousReport = Data(count: 8)
        pressedKeys = []
        joystickX = 127
        joystickY = 127

        print("[G13Device] G13 connected")

        // Register input report callback
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            newDevice, &reportBuffer, reportBuffer.count,
            g13InputReportCallback, selfPtr
        )
        IOHIDDeviceScheduleWithRunLoop(
            newDevice, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue
        )

        // Notify the app so it can re-apply profile settings
        DispatchQueue.main.async { [weak self] in
            self?.onDeviceConnected?()
        }
    }

    fileprivate func detachDevice() {
        guard let dev = device else { return }

        IOHIDDeviceUnscheduleFromRunLoop(dev, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        device = nil
        isConnected = false
        pressedKeys = []
        print("[G13Device] G13 disconnected")

        DispatchQueue.main.async { [weak self] in
            self?.onDeviceDisconnected?()
        }
    }

    // MARK: - Commands

    func setBacklightColor(red: UInt8, green: UInt8, blue: UInt8) {
        guard let device = device else { return }
        var data: [UInt8] = [0x07, red, green, blue, 0x00]
        IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0x07, &data, data.count)
    }

    func setMLEDs(_ leds: UInt8) {
        guard let device = device else { return }
        var data: [UInt8] = [0x05, leds, 0x00, 0x00, 0x00]
        IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0x05, &data, data.count)
    }

    func updateLCD() {
        guard let device = device else { return }
        var report = [UInt8](repeating: 0, count: 992)
        report[0] = 0x03
        for i in 0..<G13LCD.bufferSize {
            report[32 + i] = lcd.buffer[i]
        }
        IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(0x03), &report, report.count)
    }

    // MARK: - Input report processing

    fileprivate func processInputReport(_ data: Data) {
        guard data.count >= 8 else { return }

        if isFirstReport {
            previousReport = data
            isFirstReport = false
            joystickX = data[1]
            joystickY = data[2]
            return
        }

        let jx = data[1], jy = data[2]
        if jx != previousReport[1] || jy != previousReport[2] {
            joystickX = jx
            joystickY = jy
            onJoystickChanged?(jx, jy)
        }

        for byteIndex in 3..<min(8, data.count) {
            let cur = data[byteIndex]
            let prev = previousReport[byteIndex]
            if cur != prev {
                for bit in 0..<8 {
                    let mask: UInt8 = 1 << bit
                    let was = (prev & mask) != 0
                    let now = (cur & mask) != 0
                    if was != now {
                        let idx = (byteIndex - 3) * 8 + bit
                        let name = idx < G13Device.keyNames.count ? G13Device.keyNames[idx] : "?"
                        if G13Device.ignoredKeys.contains(name) { continue }
                        if now { pressedKeys.insert(name) } else { pressedKeys.remove(name) }
                        onKeyChanged?(name, now)
                    }
                }
            }
        }
        previousReport = data
    }
}

// =============================================================
// C callbacks for IOKit HID
// =============================================================

// Called when a G13 is plugged in (or was already plugged in at startup)
private func g13DeviceMatchedCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context = context else { return }
    let g13 = Unmanaged<G13Device>.fromOpaque(context).takeUnretainedValue()
    g13.attachDevice(device)
}

// Called when the G13 is unplugged
private func g13DeviceRemovedCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context = context else { return }
    let g13 = Unmanaged<G13Device>.fromOpaque(context).takeUnretainedValue()
    g13.detachDevice()
}

// Called for each input report from the G13
private func g13InputReportCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard let context = context else { return }
    let g13 = Unmanaged<G13Device>.fromOpaque(context).takeUnretainedValue()
    g13.processInputReport(Data(bytes: report, count: reportLength))
}
