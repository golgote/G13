import AppKit
import UniformTypeIdentifiers

private enum G13PDFError: LocalizedError {
    case contextUnavailable

    var errorDescription: String? { "The profile PDF could not be created." }
}

enum G13PDFOrientation {
    case portrait
    case landscape
}

enum G13PDFExport {
    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792

    static func save(profile: G13Profile, commands: [G13Command],
                     orientation: G13PDFOrientation = .portrait) throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        let safeName = profile.name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "G13 - \(safeName) - \(orientation == .landscape ? "Landscape" : "Portrait").pdf"
        panel.message = "Save a three-page \(orientation == .landscape ? "landscape" : "portrait") key map (M1, M2, M3)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try renderData(profile: profile, commands: commands,
                       orientation: orientation).write(to: url, options: .atomic)
    }

    static func renderData(profile: G13Profile, commands: [G13Command],
                           orientation: G13PDFOrientation = .portrait) throws -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
            throw G13PDFError.contextUnavailable
        }
        var box = CGRect(x: 0, y: 0,
                         width: orientation == .landscape ? pageHeight : pageWidth,
                         height: orientation == .landscape ? pageWidth : pageHeight)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw G13PDFError.contextUnavailable
        }
        for layer in 1...3 {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            if orientation == .landscape {
                drawLandscapePage(profile: profile, commands: commands, layer: layer)
            } else {
                drawPage(profile: profile, commands: commands, layer: layer)
            }
            NSGraphicsContext.current?.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    private static func drawPage(profile: G13Profile, commands: [G13Command], layer: Int) {
        let base = G13BacklightColor(red: profile.backlightR,
                                     green: profile.backlightG,
                                     blue: profile.backlightB)
        let color = layer == 2 ? profile.m2BacklightColor ?? base
            : layer == 3 ? profile.m3BacklightColor ?? base : base
        let keyMapping = layer == 2 ? profile.m2KeyMapping ?? [:]
            : layer == 3 ? profile.m3KeyMapping ?? [:] : profile.keyMapping
        let joystickMapping = layer == 2 ? profile.m2JoystickMapping ?? [:]
            : layer == 3 ? profile.m3JoystickMapping ?? [:] : profile.joystickMapping
        let icons = layer == 2 ? profile.m2KeyIcons ?? [:]
            : layer == 3 ? profile.m3KeyIcons ?? [:] : profile.keyIcons ?? [:]

        func assignment(_ key: String, joystick: Bool = false) -> String {
            let raw = joystick ? joystickMapping[key] ?? "" : keyMapping[key] ?? ""
            if let command = commands.first(where: { $0.assignment == raw }) { return command.name }
            return raw.hasPrefix("@") ? "Unavailable command" : raw.isEmpty ? "—" : raw
        }
        func icon(_ key: String, joystick: Bool = false) -> String? {
            let id = (joystick ? "joy:" : "key:") + key
            if let override = icons[id] { return override == "none" ? nil : override }
            let raw = joystick ? joystickMapping[key] ?? "" : keyMapping[key] ?? ""
            return commands.first(where: { $0.assignment == raw })?.iconReference
        }

        drawText("G13 KEY MAP", x: 36, top: 34, width: 380, height: 32,
                 size: 24, weight: .bold)
        drawText(profile.name, x: 36, top: 68, width: 400, height: 23,
                 size: 16, weight: .semibold)
        let appName = profile.applicationDisplayName ??
            (profile.isUniversalDefault == true ? "All applications" :
             profile.applicationBundleID ?? "Manual profile")
        drawText(appName, x: 36, top: 91, width: 400, height: 17,
                 size: 10, color: .darkGray)
        drawText("M\(layer)", x: 500, top: 40, width: 72, height: 35,
                 size: 26, weight: .bold, alignment: .right)
        NSColor(calibratedRed: CGFloat(color.red) / 255,
                green: CGFloat(color.green) / 255,
                blue: CGFloat(color.blue) / 255, alpha: 1).setFill()
        NSBezierPath(ovalIn: rect(x: 548, top: 79, width: 21, height: 21)).fill()
        NSColor.lightGray.setStroke()
        let divider = NSBezierPath()
        divider.move(to: CGPoint(x: 36, y: pageHeight - 116))
        divider.line(to: CGPoint(x: 576, y: pageHeight - 116))
        divider.stroke()

        drawText("LCD / DISPLAY BUTTONS", x: 36, top: 128, width: 300,
                 height: 16, size: 10, weight: .bold)
        for (index, key) in (["BD", "L1", "L2", "L3", "L4"] as [String]).enumerated() {
            drawKey(key, title: key, action: assignment(key), iconReference: icon(key),
                    x: 74 + CGFloat(index) * 93, top: 148, width: 88)
        }
        drawText("G-KEYS", x: 36, top: 222, width: 250,
                 height: 16, size: 10, weight: .bold)
        for row in 0..<2 {
            for column in 0..<7 {
                let number = row * 7 + column + 1
                let key = "G\(number)"
                drawKey(key, title: key, action: assignment(key), iconReference: icon(key),
                        x: 53 + CGFloat(column) * 73, top: 243 + CGFloat(row) * 65, width: 68)
            }
        }
        for (index, number) in (15...19).enumerated() {
            let key = "G\(number)"
            let width: CGFloat = index == 0 ? 80 : 68
            let x: CGFloat = index == 0 ? 116 : 116 + 85 + CGFloat(index - 1) * 73
            drawKey(key, title: key, action: assignment(key), iconReference: icon(key),
                    x: x, top: 373, width: width)
        }
        for (index, key) in (["G20", "G21", "G22"] as [String]).enumerated() {
            let widths: [CGFloat] = [80, 72, 116]
            let positions: [CGFloat] = [166, 251, 328]
            drawKey(key, title: key, action: assignment(key), iconReference: icon(key),
                    x: positions[index], top: 438, width: widths[index])
        }
        drawText("THUMB BUTTONS / JOYSTICK", x: 36, top: 510, width: 350,
                 height: 16, size: 10, weight: .bold)
        drawText("Joystick / stick click", x: 292, top: 535, width: 200,
                 height: 16, size: 9, weight: .semibold)
        drawText("Thumb buttons", x: 170, top: 615, width: 120,
                 height: 16, size: 9, weight: .semibold)
        NSColor(calibratedWhite: 0.89, alpha: 1).setStroke()
        NSBezierPath(ovalIn: rect(x: 292, top: 573, width: 146, height: 146)).stroke()
        for (key, title, x, top) in [
            ("LEFT", "Thumb L", CGFloat(170), CGFloat(640)),
            ("RIGHT", "Thumb B", CGFloat(170), CGFloat(698))
        ] {
            drawKey(key, title: title, action: assignment(key),
                    iconReference: icon(key), x: x, top: top,
                    width: 82, tileHeight: 52)
        }
        let stickControls: [(String, String, Bool, CGFloat, CGFloat)] = [
            ("UP", "↑", true, 334, 555),
            ("LEFT", "←", true, 267, 615),
            ("STICK", "Click", false, 334, 615),
            ("RIGHT", "→", true, 401, 615),
            ("DOWN", "↓", true, 334, 675)
        ]
        for control in stickControls {
            drawKey(control.0, title: control.1,
                    action: assignment(control.0, joystick: control.2),
                    iconReference: icon(control.0, joystick: control.2),
                    x: control.3, top: control.4, width: 62, tileHeight: 56)
        }
        drawText("G13 Studio - icons appear in the app and this PDF, not on the physical keys.",
                 x: 36, top: 768, width: 540, height: 10, size: 8, color: .darkGray)
    }

    private static func drawLandscapePage(profile: G13Profile,
                                          commands: [G13Command], layer: Int) {
        let height: CGFloat = 612
        let base = G13BacklightColor(red: profile.backlightR,
                                     green: profile.backlightG,
                                     blue: profile.backlightB)
        let color = layer == 2 ? profile.m2BacklightColor ?? base
            : layer == 3 ? profile.m3BacklightColor ?? base : base
        let keys = layer == 2 ? profile.m2KeyMapping ?? [:]
            : layer == 3 ? profile.m3KeyMapping ?? [:] : profile.keyMapping
        let joystick = layer == 2 ? profile.m2JoystickMapping ?? [:]
            : layer == 3 ? profile.m3JoystickMapping ?? [:] : profile.joystickMapping
        let icons = layer == 2 ? profile.m2KeyIcons ?? [:]
            : layer == 3 ? profile.m3KeyIcons ?? [:] : profile.keyIcons ?? [:]
        func action(_ key: String, joystickDirection: Bool = false) -> String {
            let raw = joystickDirection ? joystick[key] ?? "" : keys[key] ?? ""
            if let command = commands.first(where: { $0.assignment == raw }) { return command.name }
            return raw.isEmpty ? "—" : raw
        }
        func icon(_ key: String, joystickDirection: Bool = false) -> String? {
            let id = (joystickDirection ? "joy:" : "key:") + key
            if let override = icons[id] { return override == "none" ? nil : override }
            let raw = joystickDirection ? joystick[key] ?? "" : keys[key] ?? ""
            return commands.first(where: { $0.assignment == raw })?.iconReference
        }
        func label(_ text: String, x: CGFloat, top: CGFloat, width: CGFloat,
                   size: CGFloat = 9, weight: NSFont.Weight = .regular,
                   color: NSColor = .black) {
            drawText(text, x: x, top: top, width: width, height: size + 4,
                     size: size, weight: weight, color: color, pageHeight: height)
        }
        func tile(_ key: String, title: String, x: CGFloat, top: CGFloat,
                  width: CGFloat = 68, joystickDirection: Bool = false,
                  tileHeight: CGFloat = 60) {
            drawKey(key, title: title, action: action(key, joystickDirection: joystickDirection),
                    iconReference: icon(key, joystickDirection: joystickDirection),
                    x: x, top: top, width: width,
                    pageHeight: height, tileHeight: tileHeight)
        }

        label("G13 KEY MAP", x: 28, top: 24, width: 260, size: 22, weight: .bold)
        label(profile.name, x: 28, top: 55, width: 450, size: 14, weight: .semibold)
        label(profile.applicationDisplayName ??
              (profile.isUniversalDefault == true ? "All applications" :
               profile.applicationBundleID ?? "Manual profile"),
              x: 28, top: 76, width: 450, size: 10, color: .darkGray)
        label("M\(layer)", x: 710, top: 27, width: 55, size: 26, weight: .bold)
        NSColor(calibratedRed: CGFloat(color.red) / 255,
                green: CGFloat(color.green) / 255,
                blue: CGFloat(color.blue) / 255, alpha: 1).setFill()
        NSBezierPath(ovalIn: rect(x: 741, top: 70, width: 20, height: 20,
                                  pageHeight: height)).fill()
        NSColor.lightGray.setStroke()
        let divider = NSBezierPath()
        divider.move(to: CGPoint(x: 28, y: height - 98))
        divider.line(to: CGPoint(x: 764, y: height - 98))
        divider.stroke()

        label("LCD / DISPLAY BUTTONS", x: 28, top: 110, width: 300,
              size: 10, weight: .bold)
        for (index, key) in ["BD", "L1", "L2", "L3", "L4"].enumerated() {
            tile(key, title: key, x: 32 + CGFloat(index) * 100, top: 130, width: 88)
        }
        label("G-KEYS", x: 28, top: 203, width: 200, size: 10, weight: .bold)
        for row in 0..<2 {
            for column in 0..<7 {
                let number = row * 7 + column + 1
                tile("G\(number)", title: "G\(number)",
                     x: 42 + CGFloat(column) * 75,
                     top: 222 + CGFloat(row) * 63)
            }
        }
        for (index, number) in (15...19).enumerated() {
            tile("G\(number)", title: "G\(number)",
                 x: 116 + CGFloat(index) * 76, top: 348)
        }
        for (index, number) in (20...22).enumerated() {
            tile("G\(number)", title: "G\(number)",
                 x: 188 + CGFloat(index) * 76, top: 411)
        }
        label("THUMB / JOYSTICK", x: 578, top: 112, width: 185,
              size: 10, weight: .bold)
        label("Stick directions + click", x: 621, top: 137, width: 164,
              size: 9, weight: .semibold)
        NSColor(calibratedWhite: 0.89, alpha: 1).setStroke()
        NSBezierPath(ovalIn: rect(x: 639, top: 179, width: 116,
                                  height: 116, pageHeight: height)).stroke()
        tile("UP", title: "↑", x: 679, top: 157,
             width: 52, joystickDirection: true, tileHeight: 52)
        tile("LEFT", title: "←", x: 623, top: 214,
             width: 52, joystickDirection: true, tileHeight: 52)
        tile("STICK", title: "Click", x: 679, top: 214,
             width: 52, tileHeight: 52)
        tile("RIGHT", title: "→", x: 735, top: 214,
             width: 52, joystickDirection: true, tileHeight: 52)
        tile("DOWN", title: "↓", x: 679, top: 271,
             width: 52, joystickDirection: true, tileHeight: 52)
        label("Thumb buttons", x: 582, top: 347, width: 150,
              size: 9, weight: .semibold)
        tile("LEFT", title: "Thumb L", x: 584, top: 365,
             width: 84, tileHeight: 52)
        tile("RIGHT", title: "Thumb B", x: 584, top: 425,
             width: 84, tileHeight: 52)
        label("Icons appear in the app and PDF, not on the physical keys.",
              x: 28, top: 582, width: 550, size: 8, color: .darkGray)
    }

    private static func drawKey(_ key: String, title: String, action: String,
                                iconReference: String?, x: CGFloat, top: CGFloat,
                                width: CGFloat, pageHeight: CGFloat = 792,
                                tileHeight: CGFloat = 60) {
        let tile = rect(x: x, top: top, width: width, height: tileHeight,
                        pageHeight: pageHeight)
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSBezierPath(roundedRect: tile, xRadius: 5, yRadius: 5).fill()
        NSColor(calibratedWhite: 0.75, alpha: 1).setStroke()
        NSBezierPath(roundedRect: tile, xRadius: 5, yRadius: 5).stroke()
        if let iconReference {
            let iconSize: CGFloat = tileHeight < 60 ? 16 : 18
            if iconReference == "studio:duplicate-front" {
                let rear = rect(x: x + width / 2 - 2, top: top + 6,
                                width: 12, height: 12, pageHeight: pageHeight)
                let front = rect(x: x + width / 2 - 10, top: top + 2,
                                 width: 12, height: 12, pageHeight: pageHeight)
                NSColor.black.setStroke()
                NSBezierPath(roundedRect: rear, xRadius: 1, yRadius: 1).stroke()
                NSBezierPath(roundedRect: front, xRadius: 1, yRadius: 1).stroke()
            } else if iconReference.hasPrefix("sf:") || iconReference.hasPrefix("studio:") {
                let glyphName = iconReference.hasPrefix("sf:")
                    ? String(iconReference.dropFirst(3)) : iconReference
                drawText(symbolGlyph(for: glyphName),
                         x: x + width / 2 - 17, top: top + 3,
                         width: 34, height: iconSize + 2, size: 14,
                         alignment: .center, pageHeight: pageHeight)
            } else if let image = G13IconStore.image(for: iconReference) {
                image.draw(in: rect(x: x + width / 2 - iconSize / 2, top: top + 4,
                                    width: iconSize, height: iconSize,
                                    pageHeight: pageHeight))
            }
        }
        let titleTop = tileHeight < 60 ? top + 22 : top + 26
        let actionTop = tileHeight < 60 ? top + 37 : top + 41
        drawText(title, x: x + 2, top: titleTop, width: width - 4,
                 height: 14, size: 9, weight: .semibold,
                 alignment: .center, pageHeight: pageHeight)
        drawText(action, x: x + 2, top: actionTop, width: width - 4,
                 height: tileHeight < 60 ? 13 : 16, size: 8, alignment: .center,
                 pageHeight: pageHeight)
    }

    private static func symbolGlyph(for name: String) -> String {
        switch name {
        case "playpause.fill": return "▶Ⅱ"
        case "play.fill": return "▶"
        case "stop.fill": return "■"
        case "record.circle": return "●"
        case "pencil": return "✎"
        case "scissors": return "✂"
        case "waveform": return "∿"
        case "bookmark.fill": return "▮"
        case "magnifyingglass": return "⌕"
        case "plus.magnifyingglass": return "⌕+"
        case "minus.magnifyingglass": return "⌕−"
        case "studio:save-as": return "↓+"
        case "arrow.uturn.backward": return "↶"
        case "arrow.uturn.forward": return "↷"
        case "square.on.square": return "▣"
        case "square.and.arrow.down": return "↓"
        case "plus.rectangle.on.rectangle": return "+▣"
        case "shuffle": return "⇄"
        case "arrow.left.and.right": return "↔"
        case "scope": return "◎"
        case "square.grid.3x3": return "▦"
        case "crop": return "⌗"
        case "cursorarrow": return "➤"
        case "hand.point.up.left.fill": return "☛"
        case "hammer.fill": return "⚒"
        case "repeat": return "↻"
        case "metronome": return "♩"
        case "speaker.slash.fill": return "×"
        case "headphones": return "S"
        case "waveform.path": return "∿"
        case "pianokeys": return "♫"
        case "slider.horizontal.3": return "≡"
        case "square.and.arrow.up": return "↑"
        case "folder": return "▱"
        case "music.note": return "♪"
        case "arrow.left": return "←"
        case "arrow.right": return "→"
        case "flag.fill": return "⚑"
        case "f.square": return "F"
        case "rectangle.stack.fill": return "▣"
        case "trash.fill": return "×"
        case "backward.end.fill": return "|◀"
        case "forward.end.fill": return "▶|"
        case "lock.fill": return "▣"
        case "info.circle": return "ⓘ"
        case "square.stack.3d.up.fill": return "▤"
        case "arrow.down": return "↓"
        case "arrow.up": return "↑"
        default: return "●"
        }
    }

    private static func drawText(_ text: String, x: CGFloat, top: CGFloat,
                                 width: CGFloat, height: CGFloat, size: CGFloat,
                                 weight: NSFont.Weight = .regular,
                                 color: NSColor = .black,
                                 alignment: NSTextAlignment = .left,
                                 pageHeight: CGFloat = 792) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: style
        ]
        NSAttributedString(string: text, attributes: attributes)
            .draw(in: rect(x: x, top: top, width: width,
                           height: height, pageHeight: pageHeight))
    }

    private static func rect(x: CGFloat, top: CGFloat,
                             width: CGFloat, height: CGFloat,
                             pageHeight: CGFloat = 792) -> NSRect {
        NSRect(x: x, y: pageHeight - top - height, width: width, height: height)
    }
}
