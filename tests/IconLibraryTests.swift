import AppKit
import ImageIO

@main
struct IconLibraryTests {
    static func main() {
        assert(G13IconStore.matchingSymbols("mute").contains { $0.title == "Mute" })
        assert(G13IconStore.matchingSymbols("track").contains { $0.title == "New Track" })
        assert(G13IconStore.matchingSymbols("zoom in").contains { $0.name == "plus.magnifyingglass" })
        assert(G13IconStore.matchingSymbols("zoom out").contains { $0.name == "minus.magnifyingglass" })
        assert(G13IconStore.matchingComposedIcons("save as").contains { $0.reference == "studio:save-as" })
        assert(G13IconStore.matchingComposedIcons("duplicate").contains { $0.reference == "studio:duplicate-front" })
        assert(G13IconStore.matchingSymbols("zzzz").isEmpty)
        let missing = G13IconStore.symbols.filter {
            NSImage(systemSymbolName: $0.name, accessibilityDescription: nil) == nil
        }
        assert(missing.isEmpty, "Missing symbols: \(missing.map(\.name))")
        let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: 64, height: 64))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 22, y: 16, width: 20, height: 32))
        let normalized = try! G13IconStore.normalizedPNGData(from: context.makeImage()!)
        let source = CGImageSourceCreateWithData(normalized as CFData, nil)!
        let icon = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        assert(icon.width == 128 && icon.height == 128)
        assert(normalized.count < 4_000_000)
        print("Icon library tests passed: \(G13IconStore.symbols.count) symbols")
    }
}
