import Foundation

@main
struct DisplayPageTests {
    static func main() {
        assert(G13DisplayPage.overview.next == .profiles)
        assert(G13DisplayPage.profiles.next == .system)
        assert(G13DisplayPage.system.next == .overview)

        let names = ["Default", "Pro Tools", "Editing", "Mixing", "Games"]
        assert(G13LCDLayout.profileRows(names: names, activeIndex: 0, startupIndex: 1) == [
            "> 1 Default", " *2 Pro Tools", "  3 Editing"
        ])
        assert(G13LCDLayout.profileRows(names: names, activeIndex: 3, startupIndex: 1) == [
            "  3 Editing", "> 4 Mixing", "  5 Games"
        ])
        assert(G13LCDLayout.profileRows(names: ["Pro Tools"], activeIndex: 0, startupIndex: 0) == [
            ">*1 Pro Tools"
        ])
        let lcd = G13LCD()
        lcd.drawProfileSoftKeys()
        func lit(_ x: Int, _ y: Int) -> Bool {
            (lcd.buffer[(y / 8) * G13LCD.width + x] & (1 << (y % 8))) != 0
        }
        assert(lit(20, 36) && lit(60, 41) && lit(100, 39))
        assert(!lit(140, 39))
        print("Display page and profile list tests passed")
    }
}
