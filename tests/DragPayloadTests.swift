import AppKit
import UniformTypeIdentifiers

@main
struct DragPayloadTests {
    static func main() {
        let assignment = "@12345678-1234-1234-1234-123456789ABC"
        let provider = NSItemProvider(object: assignment as NSString)
        assert(provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier))
        assert(provider.canLoadObject(ofClass: NSString.self))
        var received: String?
        provider.loadObject(ofClass: NSString.self) { object, _ in
            received = object as? String
        }
        let deadline = Date().addingTimeInterval(1)
        while received == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        assert(received == assignment)
        print("Drag payload tests passed")
    }
}
