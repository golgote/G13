import Foundation

@main
struct PDFLayoutSmoke {
    static func main() throws {
        var profile = G13Profile(name: "PDF layout preview")
        profile.keyMapping = ["G1": "SPACE", "LEFT": "F1", "RIGHT": "F2", "STICK": "F3"]
        profile.joystickMapping = ["UP": "UP", "DOWN": "DOWN", "LEFT": "LEFT", "RIGHT": "RIGHT"]
        for (orientation, filename) in [
            (G13PDFOrientation.portrait, "/private/tmp/g13-v23-portrait.pdf"),
            (.landscape, "/private/tmp/g13-v23-landscape.pdf")
        ] {
            let data = try G13PDFExport.renderData(profile: profile, commands: [], orientation: orientation)
            try data.write(to: URL(fileURLWithPath: filename), options: .atomic)
            assert(data.starts(with: Data("%PDF".utf8)))
        }
        print("PDF layout smoke test passed")
    }
}
