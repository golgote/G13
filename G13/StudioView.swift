import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct StudioView: View {
    @ObservedObject var runtime: G13Runtime
    @ObservedObject var device: G13Device
    @ObservedObject var mapper: KeyMapper
    @ObservedObject var profiles: ProfileManager
    @State private var selectedKey = "G1"
    @State private var selectedIsJoystick = false
    @State private var hasSelectedControl = false
    @State private var editingCommand: G13Command?
    @State private var assignEditedCommandToSelectedControl = false
    @State private var showNewProfile = false
    @State private var newProfileName = ""
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showRGB = false
    @State private var pdfError: String?
    @State private var libraryError: String?
    @State private var commandSearch = ""
    @State private var showWarnings = false
    @State private var showSettings = false
    @State private var shortcutFocusRequest = 0
    @State private var dropTarget: String?
    @State private var profileToDelete: UUID?
    @State private var folderToDelete: G13CommandFolder?
    @State private var folderToRename: UUID?
    @State private var showFolderNamePrompt = false
    @State private var folderNameDraft = ""
    @State private var folderNameError: String?
    @State private var folderMoveError: String?
    @State private var collapsedFolderIDs: Set<UUID> = []
    @State private var collapsedScopeIDs: Set<String> = []
    @State private var collapsedUnfiledScopeIDs: Set<String> = []
    @State private var showNamedCommandPicker = false
    @State private var namedCommandSearch = ""
    @FocusState private var namedCommandSearchFocused: Bool
    @AppStorage("studioCommandSort") private var commandSort = "name"
    @AppStorage("studioLightMode") private var lightMode = false
    @AppStorage("studioIconsOnly") private var legacyIconsOnly = false
    @AppStorage("studioDisplayMigratedV13") private var displayMigrated = false
    @AppStorage("studioShowIcons") private var showIcons = true
    @AppStorage("studioShowControlLabels") private var showControlLabels = true
    @AppStorage("studioShowAssignments") private var showAssignments = true
    @AppStorage("studioShowShortcutText") private var showShortcutText = false
    @AppStorage("studioDefaultIconColor") private var defaultIconColor = "automatic"

    private let cyan = Color(red: 0.0, green: 0.76, blue: 0.88)
    private var accent: Color { lightMode ? Color(red: 0, green: 0.38, blue: 0.55) : cyan }
    private var tileFill: Color { lightMode ? .white : Color.black.opacity(0.7) }
    private var panelFill: Color { lightMode ? Color.black.opacity(0.045) : Color.white.opacity(0.055) }
    private let palette: [(String, UInt8, UInt8, UInt8)] = [
        ("White", 255, 255, 255), ("Red", 255, 45, 45), ("Orange", 255, 130, 0),
        ("Yellow", 255, 220, 0), ("Green", 30, 230, 70), ("Teal", 0, 210, 195),
        ("Blue", 0, 100, 255), ("Purple", 155, 65, 255), ("Pink", 255, 50, 160)
    ]

    init(runtime: G13Runtime) {
        self.runtime = runtime
        self.device = runtime.device
        self.mapper = runtime.keyMapper
        self.profiles = runtime.profileManager
    }

    var body: some View {
        HStack(spacing: 0) {
            commandsSidebar
                .frame(width: 222)
            VStack(alignment: .leading, spacing: 6) {
                header
                profileBar
                layerBar
                HStack(alignment: .top, spacing: 16) {
                    keypad.frame(maxWidth: .infinity)
                    assignmentPanel
                }
                statusBar
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 1080, height: 715)
        .preferredColorScheme(lightMode ? .light : .dark)
        .onAppear(perform: migrateDisplaySettings)
        .onChange(of: profiles.activeProfileIndex) { _, _ in hasSelectedControl = false }
        .onChange(of: profiles.activeLayer) { _, _ in hasSelectedControl = false }
        .background(lightMode ? Color(red: 0.96, green: 0.98, blue: 0.99) :
                    Color(red: 0.045, green: 0.07, blue: 0.09))
        .sheet(item: $editingCommand, onDismiss: {
            assignEditedCommandToSelectedControl = false
        }) { command in
            CommandEditor(command: command,
                          profiles: profiles,
                          appBundleID: profiles.activeProfile?.applicationBundleID,
                          appName: profiles.activeProfile?.applicationDisplayName ?? profiles.activeProfileName) { updated in
                profiles.saveCommand(updated)
                if assignEditedCommandToSelectedControl && hasSelectedControl {
                    _ = profiles.assignVisibleCommand(updated.assignment, to: selectedKey,
                                                      isJoystick: selectedIsJoystick)
                }
            }
        }
        .alert("New profile", isPresented: $showNewProfile) {
            TextField("Profile name", text: $newProfileName)
            Button("Create") {
                let name = newProfileName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    profiles.addProfile(name: name)
                    profiles.switchToProfile(at: profiles.profiles.count - 1)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename profile", isPresented: $showRename) {
            TextField("Profile name", text: $renameText)
            Button("Save") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { profiles.renameProfile(at: profiles.activeProfileIndex, to: name) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete profile?", isPresented: Binding(
            get: { profileToDelete != nil }, set: { if !$0 { profileToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete profile", role: .destructive) {
                if let id = profileToDelete,
                   let index = profiles.profiles.firstIndex(where: { $0.id == id }) {
                    profiles.deleteProfile(at: index)
                }
                profileToDelete = nil
            }
            Button("Cancel", role: .cancel) { profileToDelete = nil }
        } message: {
            Text("Delete \(profiles.profiles.first(where: { $0.id == profileToDelete })?.name ?? "this profile") and its three layers? This cannot be undone. Save a backup first if you may need it later.")
        }
        .alert(folderToRename == nil ? "New command folder" : "Rename command folder",
               isPresented: $showFolderNamePrompt) {
            TextField("Folder name", text: $folderNameDraft)
            Button(folderToRename == nil ? "Create" : "Save") { commitFolderName() }
            Button("Cancel", role: .cancel) { folderToRename = nil }
        } message: {
            Text("Folders organize commands within All Apps or the selected application.")
        }
        .confirmationDialog("Delete command folder?", isPresented: Binding(
            get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete folder", role: .destructive) {
                if let id = folderToDelete?.id { profiles.deleteCommandFolder(id) }
                folderToDelete = nil
            }
            Button("Cancel", role: .cancel) { folderToDelete = nil }
        } message: {
            Text("Commands in \(folderToDelete?.name ?? "this folder") will move to Unfiled. Their key assignments will stay in place.")
        }
        .alert("Folder name", isPresented: Binding(
            get: { folderNameError != nil }, set: { if !$0 { folderNameError = nil } }
        )) {
            Button("OK") { folderNameError = nil }
        } message: {
            Text(folderNameError ?? "")
        }
        .alert("Command could not be moved", isPresented: Binding(
            get: { folderMoveError != nil }, set: { if !$0 { folderMoveError = nil } }
        )) {
            Button("OK") { folderMoveError = nil }
        } message: {
            Text(folderMoveError ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .g13OpenRecorder)) { _ in
            editingCommand = newCommand(kind: .multiKey)
        }
        .alert("PDF could not be saved", isPresented: Binding(
            get: { pdfError != nil }, set: { if !$0 { pdfError = nil } }
        )) {
            Button("OK") { pdfError = nil }
        } message: {
            Text(pdfError ?? "")
        }
        .alert("Profile library", isPresented: Binding(
            get: { libraryError != nil }, set: { if !$0 { libraryError = nil } }
        )) {
            Button("OK") { libraryError = nil }
        } message: {
            Text(libraryError ?? "")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("G13 Studio").font(.title.bold()).foregroundStyle(accent)
                Text("\(profiles.activeProfileName) · M\(profiles.activeLayer)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .help("Settings")
            .accessibilityLabel("Settings")
            .popover(isPresented: $showSettings) { settingsPopover }
            Button {
                lightMode.toggle()
            } label: {
                Image(systemName: lightMode ? "moon.fill" : "sun.max.fill")
            }
            .help(lightMode ? "Switch to dark mode" : "Switch to light mode")
            Toggle("Safe Test", isOn: Binding(
                get: { runtime.isSafeTestMode },
                set: { runtime.setSafeTestMode($0) }
            ))
            .toggleStyle(.switch)
            .help("Show G13 actions without sending keys or scroll events to macOS")
            Menu {
                Button("Portrait") { savePDF(.portrait) }
                Button("Landscape") { savePDF(.landscape) }
            } label: {
                Image(systemName: "printer")
            }
            .help("Save keypad layout as PDF")
            .accessibilityLabel("Save PDF")
        }
    }

    private func migrateDisplaySettings() {
        guard !displayMigrated else { return }
        if legacyIconsOnly {
            showIcons = true
            showControlLabels = false
            showAssignments = false
        }
        displayMigrated = true
    }

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("G13 Studio Settings").font(.title3.bold())
            Text("SHOW ON KEYPAD")
                .font(.caption.bold()).foregroundStyle(accent)
            Toggle("Icon", isOn: $showIcons)
                .disabled(showIcons && !showControlLabels && !showAssignments)
            Toggle("Control name (G1, L1, joystick…)", isOn: $showControlLabels)
                .disabled(showControlLabels && !showIcons && !showAssignments)
            Toggle("Assigned command or shortcut", isOn: $showAssignments)
                .disabled(showAssignments && !showIcons && !showControlLabels)
            Picker("Show assignment as", selection: $showShortcutText) {
                Text("Command name").tag(false)
                Text("Keystroke").tag(true)
            }
            .pickerStyle(.segmented)
            Text("Named commands can show their title, such as Undo, or their actual keys, such as CMD+Z. Multi Key commands show their steps.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Choose any combination. At least one item stays visible. In Icons only mode, keys without icons show their assignments.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Icons only") {
                    showIcons = true
                    showControlLabels = false
                    showAssignments = false
                }
                Button("Show all three") {
                    showIcons = true
                    showControlLabels = true
                    showAssignments = true
                }
            }
            HStack {
                Picker("Shared icon color", selection: $defaultIconColor) {
                    ForEach(G13IconColor.allCases, id: \.rawValue) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                Button("Apply to all") { profiles.clearAllIconColorOverrides() }
                    .help("Use the shared color for every command and key icon")
            }
            Text("Automatic is black in Light mode and white in Dark mode. Choose a color for an individual command or key in its editor. Original keeps imported image colors.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Label(mapper.hasAccessibility ? "Accessibility enabled" : "Accessibility needed for output",
                      systemImage: mapper.hasAccessibility ? "checkmark.shield" : "hand.raised")
                    .font(.caption)
                Spacer()
                if !mapper.hasAccessibility {
                    Button("Request Access") { mapper.checkAccessibility(prompt: true) }
                }
            }
            Text("G13 Studio uses macOS Accessibility only to send your assigned keys and scrolling. Safe Test works without it.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Use default display controls is beside G13 Keys. When checked, BD and L1–L4 are reserved and their assignment editors are disabled. Uncheck it to program those buttons; saved assignments return when default controls are off.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("HELP").font(.caption.bold()).foregroundStyle(accent)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    helpItem("Profiles", "Default is the universal output profile. When Pro Tools is frontmost, its matching profile supplies keys. In other apps without a matching profile, Default supplies keys even if you leave Pro Tools selected in this editor. The editor shows your selected profile for configuration. Selecting a manual, unbound profile uses it for output in any app. Opening this editor pauses output. Auto-switch selects an application profile when that app becomes frontmost.")
                    helpItem("M1, M2, M3", "These are three independent key layers within a profile. Each layer remembers its assignments, key images, joystick mode, and backlight color.")
                    helpItem("Assign a shortcut", "Click a control on the diagram, then press a complete shortcut such as Cmd+Opt+W. The Selected Control field highlights while ready. Press Escape to cancel. You can also click the field or use Type… for manual entry. Click the selected control again, or use the X in Selected Control, to clear the selection.")
                    helpItem("Hold modifiers while clicking", "Assign SHIFT, ALT, or a chord such as ALT+SHIFT to one control, then hold it while pressing a control assigned Left Click or Right Click. For a modifier-only chord, use Type… in Selected Control or type it in the Command editor; the recorder waits for a non-modifier key. Mouse clicks carry the held modifiers. Keep Safe Test off and the editor closed when checking live output.")
                    helpItem("Clear or replace a key", "Right-click a control for Record shortcut, Assign command, or Clear assignment. Drag a named command from the Commands list onto a control to assign it. Clearing or replacing an assignment also resets that key's image override, so the new command image appears.")
                    helpItem("Commands and folders", "Use + in Commands and choose Keystroke for one chord, Multi Key for up to 16 steps, or Mouse for clicks at the current pointer position. Mouse commands can include Shift, Control, Option, or Command, such as Shift + Left Click. All Apps commands work in every profile; application commands appear only in that app profile. The scope, Unfiled, and named folders can all be collapsed. Sort by name or date added, and type in Choose command to filter assignments. Drag a command onto another folder in the same scope to move it. To change between All Apps and an application, edit Available in. Deleting a folder moves its commands to Unfiled.")
                    helpItem("Timed hold", "In a Keystroke command, enable Hold key for a set time and choose 0.1–30 seconds. Assign the command to a G13 button. For a direct shortcut, select its button and choose Make timed hold command. Disconnecting or changing profiles releases the key immediately.")
                    helpItem("Icons and printout", "Choose a built-in symbol or import a PNG/JPEG image for a command or key. Imported artwork is centered in a standard square. A key image overrides its command image. In Icons only mode, controls without an icon show their command text. Hover over a control to see its full assignment. Save PDF produces portrait or landscape pages for all three layers of the selected profile.")
                    helpItem("Icon colors", "Settings has a shared icon color. Automatic appears black in Light mode and white in Dark mode. Choose an icon color in a command editor or Selected Control to override it. Apply to all clears those overrides. Original keeps the colors in imported artwork.")
                    helpItem("Safe Test and permissions", "G13 Studio starts ready for live output. Turn on Safe Test to preview G13 actions without sending keystrokes, clicks, or scrolling to macOS. Accessibility permission is required for output; use Request Access above if needed.")
                    helpItem("Joystick", "Choose Keys, Vertical scroll, Horizontal scroll, or Both axes scroll per layer. Vertical scroll uses Up/Down for scrolling and leaves Left/Right as keys; Horizontal scroll does the reverse. Both axes scroll uses all four directions. Scrolling directions are dimmed but their saved key assignments return in Keys mode. Vertical and horizontal speeds are separate for each profile. Centering the stick, disconnecting, or switching profiles stops scrolling.")
                    helpItem("Backup and device storage", "The archive icon beside Profiles saves profiles, commands, layer settings, and custom images to a local JSON file. Restore replaces the current library after confirmation. Settings are saved in this Mac account; saving them to G13 onboard memory is not supported.")
                    helpItem("LCD pages and startup profile", "Check Use default display controls beside G13 Keys to reserve BD and L1–L4 for the screen. Their tiles and assignment editors are disabled while checked. BD cycles Overview, Profiles, then combined CPU/RAM. Overview shows the output profile and M layer. Profiles shows a scrolling list, with up, down, and lock icons over L1–L3; those buttons change or save the startup profile only on this page. CPU/RAM shows two live usage bars. The L buttons have no LCD action on Overview or CPU/RAM, and L4 has no LCD action. Uncheck the box to use saved BD/L shortcuts. These readings are approximate; game statistics need a game-specific source.")
                    helpItem("Commands and MR", "Use + in Commands to create a Keystroke or Multi Key command. Both types can be recorded in the editor. The physical MR button opens that same editor with Multi Key selected.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 290)
        }
        .frame(width: 410, alignment: .leading)
        .padding(16)
    }

    private func helpItem(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.bold())
            Text(detail).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var commandsSidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("COMMANDS").font(.headline).foregroundStyle(accent)
                Spacer()
                Button {
                    editingCommand = newCommand(kind: .keystroke)
                } label: {
                    Image(systemName: "plus").frame(width: 22, height: 22)
                }
                .help("New command")
                .accessibilityLabel("New command")
                Button {
                    folderToRename = nil
                    folderNameDraft = ""
                    showFolderNamePrompt = true
                } label: {
                    Image(systemName: "folder.badge.plus").frame(width: 22, height: 22)
                }
                .help("New command folder")
                .accessibilityLabel("New command folder")
            }
            .buttonStyle(.bordered)
            TextField("Search commands or shortcuts", text: $commandSearch)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search commands")
            Picker("Sort commands", selection: $commandSort) {
                Text("Name A–Z").tag("name")
                Text("Name Z–A").tag("nameDescending")
                Text("Date added").tag("added")
            }
            .pickerStyle(.menu)
            .font(.caption)
            GeometryReader { viewport in
                ScrollView([.vertical, .horizontal], showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        if visibleCommands.isEmpty && (!commandSearch.isEmpty ||
                            (profiles.folders(for: nil).isEmpty &&
                             profiles.folders(for: profiles.activeProfile?.applicationBundleID).isEmpty)) {
                            Text("No matching commands")
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.vertical, 16)
                        }
                        commandScopeSection("All Apps", bundleID: nil)
                        if let bundleID = profiles.activeProfile?.applicationBundleID {
                            commandScopeSection(profiles.activeProfile?.applicationDisplayName ?? profiles.activeProfileName,
                                                bundleID: bundleID)
                        }
                    }
                    .frame(width: commandListWidth, alignment: .leading)
                    .frame(minHeight: viewport.size.height, alignment: .topLeading)
                    .padding(.horizontal, 2)
                }
                .id(commandListIdentity)
            }
            Text("Drag a command by its grip onto a key. Click its name to edit.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(lightMode ? Color(red: 0.9, green: 0.95, blue: 0.97) :
                    Color(red: 0.04, green: 0.10, blue: 0.13))
    }

    private var commandListIdentity: String {
        let profileID = profiles.activeProfile?.id.uuidString ?? "none"
        let folderState = collapsedFolderIDs.map(\.uuidString).sorted().joined(separator: ",")
        let scopeState = collapsedScopeIDs.sorted().joined(separator: ",")
        let unfiledState = collapsedUnfiledScopeIDs.sorted().joined(separator: ",")
        return "\(profileID)|\(folderState)|\(scopeState)|\(unfiledState)|\(commandSearch)|\(commandSort)"
    }

    private var commandListWidth: CGFloat {
        let commandFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        let longestName = visibleCommands.filter {
            $0.folderID.map { !collapsedFolderIDs.contains($0) } ?? true
        }.map {
            ($0.name as NSString).size(withAttributes: [.font: commandFont]).width
        }.max() ?? 0
        let folderFont = NSFont.systemFont(ofSize: 11, weight: .bold)
        let displayedFolders = profiles.folders(for: nil) +
            profiles.folders(for: profiles.activeProfile?.applicationBundleID)
        let longestFolder = displayedFolders.map {
            ($0.name as NSString).size(withAttributes: [.font: folderFont]).width
        }.max() ?? 0
        return max(192, ceil(longestName) + 105, ceil(longestFolder) + 55)
    }

    private var commandRowWidth: CGFloat { commandListWidth - 24 }

    private var visibleCommands: [G13Command] {
        let query = commandSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let commands = profiles.commandsVisibleInActiveProfile()
        guard !query.isEmpty else { return sortedCommands(commands) }
        return sortedCommands(commands.filter { command in
            let folderName = command.folderID.flatMap { id in
                profiles.commandFolders.first(where: { $0.id == id })?.name
            }
            return command.name.localizedCaseInsensitiveContains(query) ||
                command.steps.contains(where: { $0.localizedCaseInsensitiveContains(query) }) ||
                (folderName?.localizedCaseInsensitiveContains(query) ?? false) ||
                (command.kind == .multiKey ? "multi key macro" :
                 command.kind == .mouseFunction ? "mouse left right middle double click" : "keystroke")
                    .localizedCaseInsensitiveContains(query)
        })
    }

    private func sortedCommands(_ commands: [G13Command]) -> [G13Command] {
        guard commandSort != "added" else { return commands }
        return commands.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            if order == .orderedSame { return $0.id.uuidString < $1.id.uuidString }
            return commandSort == "nameDescending" ? order == .orderedDescending : order == .orderedAscending
        }
    }

    @ViewBuilder
    private func commandScopeSection(_ title: String, bundleID: String?) -> some View {
        let scoped = visibleCommands.filter { $0.applicationBundleID?.lowercased() == bundleID?.lowercased() }
        let folders = profiles.folders(for: bundleID)
        let scopeID = bundleID?.lowercased() ?? "all-apps"
        if !scoped.isEmpty || (commandSearch.isEmpty && !folders.isEmpty) {
            DisclosureGroup(isExpanded: Binding(
                get: { !collapsedScopeIDs.contains(scopeID) || !commandSearch.isEmpty },
                set: { expanded in
                    if expanded { collapsedScopeIDs.remove(scopeID) }
                    else { collapsedScopeIDs.insert(scopeID) }
                }
            )) {
            let unfiled = scoped.filter { command in
                command.folderID == nil || !folders.contains(where: { $0.id == command.folderID })
            }
            if !unfiled.isEmpty {
                DisclosureGroup(isExpanded: Binding(
                    get: { !collapsedUnfiledScopeIDs.contains(scopeID) || !commandSearch.isEmpty },
                    set: { expanded in
                        if expanded { collapsedUnfiledScopeIDs.remove(scopeID) }
                        else { collapsedUnfiledScopeIDs.insert(scopeID) }
                    }
                )) {
                    ForEach(unfiled) { command in commandRow(command) }
                } label: {
                    Label("Unfiled (\(unfiled.count))", systemImage: "tray")
                        .font(.caption.bold())
                }
            }
            ForEach(folders) { folder in
                let items = scoped.filter { $0.folderID == folder.id }
                if !items.isEmpty || commandSearch.isEmpty {
                    let folderTarget = "folder:\(folder.id.uuidString)"
                    DisclosureGroup(isExpanded: Binding(
                        get: { !collapsedFolderIDs.contains(folder.id) || !commandSearch.isEmpty },
                        set: { expanded in
                            if expanded { collapsedFolderIDs.remove(folder.id) }
                            else { collapsedFolderIDs.insert(folder.id) }
                        }
                    )) {
                        ForEach(items) { command in commandRow(command) }
                    } label: {
                        Label("\(folder.name) (\(items.count))", systemImage: "folder.fill")
                            .font(.caption.bold())
                            .frame(width: commandListWidth - 24, alignment: .leading)
                            .contentShape(Rectangle())
                            .background(dropTarget == folderTarget ? accent.opacity(0.25) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 5))
                            .onDrop(of: [UTType.utf8PlainText.identifier],
                                    isTargeted: dropBinding(for: folderTarget)) { providers in
                                moveCommandDrop(providers, to: folder)
                            }
                    }
                    .frame(width: commandListWidth, alignment: .leading)
                    .contextMenu {
                        Button("Rename folder") {
                            folderToRename = folder.id
                            folderNameDraft = folder.name
                            showFolderNamePrompt = true
                        }
                        Button("Delete folder", role: .destructive) { folderToDelete = folder }
                    }
                }
            }
            } label: {
                Label("\(title) (\(scoped.count))", systemImage: bundleID == nil ? "globe" : "app")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .frame(width: commandListWidth, alignment: .leading)
        }
    }

    private func commitFolderName() {
        let name = folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let succeeded: Bool
        if let id = folderToRename {
            succeeded = profiles.renameCommandFolder(id, to: name)
        } else {
            succeeded = profiles.addCommandFolder(name: name,
                applicationBundleID: profiles.activeProfile?.applicationBundleID) != nil
        }
        folderToRename = nil
        if !succeeded { folderNameError = "Use a unique folder name between 1 and 80 characters." }
    }

    private func newCommand(kind: G13Command.Kind) -> G13Command {
        var command = G13Command(name: "New command", kind: kind, steps: [])
        command.applicationBundleID = profiles.activeProfile?.applicationBundleID
        return command
    }

    private func commandRow(_ command: G13Command) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 28)
                .contentShape(Rectangle())
                .onDrag { NSItemProvider(object: command.assignment as NSString) }
                .help("Drag to a G13 key")
            G13IconView(reference: command.iconReference, colorOverride: command.iconColor)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(command.name).fontWeight(.medium)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(command.actionDescription)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(6)
        .frame(width: commandRowWidth, alignment: .leading)
        .background(panelFill, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture { editingCommand = command }
        .contextMenu {
            Button("Assign to \(selectedKey)") { setAssignment(command.assignment) }
                .disabled(selectedControlIsReserved || (selectedIsJoystick && command.kind != .keystroke))
            Button("Edit") { editingCommand = command }
            Button("Delete", role: .destructive) { profiles.deleteCommand(command) }
        }
        .onDrag { NSItemProvider(object: command.assignment as NSString) }
    }

    private func moveCommandDrop(_ providers: [NSItemProvider], to folder: G13CommandFolder) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let assignment = object as? String else { return }
            DispatchQueue.main.async {
                if !profiles.moveCommand(assignment, toFolder: folder.id) {
                    folderMoveError = "Drag between folders in the same All Apps or application section. To change sections, edit the command's Available in setting."
                }
            }
        }
        return true
    }

    private func savePDF(_ orientation: G13PDFOrientation) {
        guard let profile = profiles.activeProfile else { return }
        do { try G13PDFExport.save(profile: profile,
                                   commands: profiles.commandsVisibleInActiveProfile(),
                                   orientation: orientation) }
        catch { pdfError = error.localizedDescription }
    }

    private func saveLibraryBackup() {
        do {
            let data = try G13ProfileBackup.create(from: profiles)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "G13 Studio Backup.json"
            panel.message = "Save profiles, commands, layer settings, and custom icons"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
        } catch { libraryError = error.localizedDescription }
    }

    private func restoreLibraryBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a G13 Studio backup"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true,
                  let size = values.fileSize,
                  size <= G13ProfileBackup.maximumFileSize else { throw G13BackupError.invalidFile }
            let backup = try G13ProfileBackup.read(Data(contentsOf: url))
            let confirmation = NSAlert()
            confirmation.messageText = "Replace the current G13 library?"
            confirmation.informativeText = "This restores \(backup.profiles.count) profiles and \(backup.commands.count) commands. Save a backup of the current library first if you want to keep it."
            confirmation.alertStyle = .warning
            confirmation.addButton(withTitle: "Restore")
            confirmation.addButton(withTitle: "Cancel")
            guard confirmation.runModal() == .alertFirstButtonReturn else { return }
            try backup.restore(into: profiles)
            selectedKey = "G1"
            selectedIsJoystick = false
            hasSelectedControl = false
        } catch { libraryError = error.localizedDescription }
    }

    private var profileBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PROFILES").font(.headline).foregroundStyle(accent)
                Spacer()
                Button {
                    newProfileName = ""
                    showNewProfile = true
                } label: {
                    Image(systemName: "plus").frame(width: 22, height: 22)
                }
                .help("Add profile")
                .accessibilityLabel("Add profile")
                Button {
                    _ = profiles.duplicateActiveProfile()
                } label: {
                    Image(systemName: "square.on.square").frame(width: 22, height: 22)
                }
                .help("Duplicate profile for another application")
                .accessibilityLabel("Duplicate profile")
                Button {
                    renameText = profiles.activeProfileName
                    showRename = true
                } label: {
                    Image(systemName: "pencil").frame(width: 22, height: 22)
                }
                .help("Rename profile")
                .accessibilityLabel("Rename profile")
                Button {
                    profiles.setStartupProfileToActive()
                } label: {
                    Image(systemName: profiles.activeIsStartupProfile ? "lock.fill" : "lock.open")
                        .frame(width: 22, height: 22)
                }
                .help("Use this profile at startup")
                .accessibilityLabel("Use this profile at startup")
                Button(role: .destructive) {
                    profileToDelete = profiles.activeProfile?.id
                } label: {
                    Image(systemName: "trash").frame(width: 22, height: 22)
                }
                .disabled(profiles.activeProfileIsUniversal)
                .help("Delete profile")
                .accessibilityLabel("Delete profile")
                Menu {
                    Button("Save backup…") { saveLibraryBackup() }
                    Button("Restore backup…") { restoreLibraryBackup() }
                } label: {
                    Image(systemName: "archivebox").frame(width: 22, height: 22)
                }
                .help("Backup or restore profiles")
                .accessibilityLabel("Backup or restore profiles")
            }
            .buttonStyle(.bordered)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(profiles.profiles.enumerated()), id: \.element.id) { index, profile in
                        let app = profile.applicationBundleID.map {
                            ApplicationPresentation.resolve(bundleID: $0, savedName: profile.applicationDisplayName)
                        }
                        Button {
                            profiles.switchToProfile(at: index)
                        } label: {
                            HStack(spacing: 8) {
                                if let icon = app?.icon {
                                    Image(nsImage: icon)
                                        .resizable().interpolation(.high)
                                        .frame(width: 27, height: 27)
                                } else {
                                    Image(systemName: profile.isUniversalDefault == true ? "globe" : "app.dashed")
                                        .frame(width: 27, height: 27)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 3) {
                                        Text(profile.name).fontWeight(.semibold).lineLimit(1)
                                        if profile.id == profiles.startupProfileID {
                                            Image(systemName: "lock.fill").font(.caption2)
                                        }
                                    }
                                    Text(profile.isUniversalDefault == true ? "All apps · default" :
                                         (app?.name ?? "Choose application"))
                                        .font(.caption).lineLimit(1)
                                }
                            }
                            .frame(width: 160, alignment: .leading)
                            .padding(6)
                            .background(index == profiles.activeProfileIndex ? accent.opacity(0.25) : panelFill)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Use at startup") {
                                profiles.switchToProfile(at: index)
                                profiles.setStartupProfileToActive()
                            }
                            Button("Duplicate for another app") {
                                profiles.switchToProfile(at: index)
                                _ = profiles.duplicateActiveProfile()
                            }
                            Button("Delete", role: .destructive) { profileToDelete = profile.id }
                                .disabled(profile.isUniversalDefault == true)
                        }
                    }
                }
            }
            applicationBindingRow
        }
    }

    private var applicationBindingRow: some View {
        HStack(spacing: 8) {
            Text("Application:")
                .frame(width: 82, alignment: .leading)
            Menu {
                if profiles.activeProfileIsUniversal {
                    Button("Duplicate for an application…") { _ = profiles.duplicateActiveProfile() }
                } else {
                    Button("Unassigned (manual only)") { profiles.bindActiveProfile(to: nil) }
                    Divider()
                    Button("Choose installed app…") {
                        if let choice = ApplicationPresentation.chooseInstalledApplication() {
                            profiles.bindActiveProfile(to: choice.bundleID, displayName: choice.name)
                        }
                    }
                    Divider()
                    ForEach(runningApps, id: \.bundleID) { app in
                        Button {
                            profiles.bindActiveProfile(to: app.bundleID, displayName: app.name)
                        } label: {
                            HStack {
                                if let icon = app.icon {
                                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                                }
                                Text(app.name)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if profiles.activeProfileIsUniversal {
                        Image(systemName: "globe").frame(width: 18, height: 18)
                        Text("All applications")
                    } else if let bundleID = profiles.activeProfile?.applicationBundleID {
                        let app = ApplicationPresentation.resolve(
                            bundleID: bundleID,
                            savedName: profiles.activeProfile?.applicationDisplayName)
                        if let icon = app.icon {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "app.dashed").frame(width: 18, height: 18)
                        }
                        Text(app.name).lineLimit(1)
                    } else {
                        Image(systemName: "app.dashed").frame(width: 18, height: 18)
                        Text("Choose application")
                    }
                }
                .frame(width: 190, height: 22, alignment: .leading)
            }
            .frame(width: 210, height: 28)
            Text(profiles.activeProfileIsUniversal ? "Universal · select any time" :
                 "Switches when the app becomes frontmost")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("Auto-switch", isOn: Binding(
                get: { profiles.autoSwitchEnabled },
                set: { profiles.setAutoSwitchEnabled($0) }
            ))
            .toggleStyle(.checkbox)
            .frame(width: 110, alignment: .leading)
            .opacity(profiles.activeProfileIsUniversal ? 0 : 1)
            .disabled(profiles.activeProfileIsUniversal)
            .help("Activate this profile when its application becomes frontmost")
        }
        .frame(height: 30)
    }

    private var runningApps: [(name: String, bundleID: String, icon: NSImage?)] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                  app.activationPolicy == .regular, seen.insert(id).inserted else { return nil }
            return (app.localizedName ?? id, id, app.icon)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var layerBar: some View {
        HStack(spacing: 7) {
            Text("LAYERS").font(.caption.bold()).foregroundStyle(accent)
            ForEach(1...3, id: \.self) { layer in
                let color = profiles.backlightColor(for: layer)
                Button {
                    profiles.switchLayer(layer)
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(red: Double(color.red) / 255,
                                        green: Double(color.green) / 255,
                                        blue: Double(color.blue) / 255))
                            .frame(width: 10, height: 10)
                        Text("M\(layer)")
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .tint(profiles.activeLayer == layer ? accent : .gray)
            }
            Spacer(minLength: 4)
            Text("COLOR").font(.caption.bold()).foregroundStyle(accent)
            ForEach(palette, id: \.0) { item in
                Button {
                    profiles.setBacklightColor(G13BacklightColor(
                        red: Int(item.1), green: Int(item.2), blue: Int(item.3)))
                    runtime.applyActiveProfile()
                } label: {
                    Circle().fill(Color(red: Double(item.1)/255,
                                        green: Double(item.2)/255,
                                        blue: Double(item.3)/255))
                        .frame(width: 17, height: 17)
                }
                .buttonStyle(.plain)
                .help(item.0 + " on M\(profiles.activeLayer)")
            }
            Button("RGB…") { showRGB = true }
                .popover(isPresented: $showRGB) {
                    colorPanel.frame(width: 300).padding(8)
                }
        }
    }

    private var keypad: some View {
        VStack(spacing: 4) {
            HStack {
                Text("G13 KEYS").font(.caption.bold()).foregroundStyle(accent)
                Spacer()
                Toggle("Use default display controls", isOn: Binding(
                    get: { runtime.displayButtonsControlLCD },
                    set: { runtime.setDisplayButtonsControlLCD($0) }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
                .help("Reserve BD and L1–L4 for the G13 screen; uncheck to edit and use their saved shortcuts")
                Menu {
                    ForEach(G13DisplayPage.allCases, id: \.rawValue) { page in
                        Button(page.title) { runtime.showDisplayPage(page) }
                    }
                } label: {
                    Label(runtime.displayPage.title, systemImage: "display")
                        .font(.caption)
                }
                .disabled(!runtime.displayButtonsControlLCD)
                .help("Select the page shown on the G13 screen")
            }
            HStack(spacing: 6) {
                keyButton("BD", width: 68)
                ForEach(1...4, id: \.self) { number in
                    keyButton("L\(number)", width: 68)
                }
            }
            GeometryReader { geometry in
                let width = min(CGFloat(85), max(CGFloat(42), (geometry.size.width - 30) / 7))
                VStack(spacing: 5) {
                    HStack(spacing: 5) {
                        ForEach(1...7, id: \.self) { number in
                            keyButton("G\(number)", width: width, height: 53)
                        }
                    }
                    HStack(spacing: 5) {
                        ForEach(8...14, id: \.self) { number in
                            keyButton("G\(number)", width: width, height: 53)
                        }
                    }
                    HStack(spacing: 5) {
                        keyButton("G15", width: width * 1.2, height: 53)
                        ForEach(16...19, id: \.self) { number in
                            keyButton("G\(number)", width: width, height: 53)
                        }
                    }
                    HStack(spacing: 5) {
                        keyButton("G20", width: width * 1.2, height: 53)
                        keyButton("G21", width: width * 1.1, height: 53)
                        keyButton("G22", width: width * 1.7, height: 53)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 227)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("THUMB BUTTONS").font(.caption.bold()).foregroundStyle(.secondary)
                    keyButton("LEFT", width: 86, displayLabel: "Left")
                    keyButton("RIGHT", width: 86, displayLabel: "Bottom")
                }
                VStack(spacing: 5) {
                    Text("JOYSTICK").font(.caption.bold()).foregroundStyle(.secondary)
                    joystickDirectionButton("UP", label: "Up")
                    HStack(spacing: 4) {
                        joystickDirectionButton("LEFT", label: "Left")
                        keyButton("STICK", width: 60, displayLabel: "Click")
                        joystickDirectionButton("RIGHT", label: "Right")
                    }
                    joystickDirectionButton("DOWN", label: "Down")
                }
                joystickLiveInfo
            }
            .frame(maxWidth: .infinity)
            HStack(alignment: .top, spacing: 8) {
                Picker("Joystick", selection: Binding(
                    get: { profiles.activeJoystickMode },
                    set: { profiles.activeJoystickMode = $0 }
                )) {
                    ForEach(G13JoystickMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 250)
                if profiles.activeJoystickMode != .keys {
                    VStack(alignment: .leading, spacing: 4) {
                        if profiles.activeJoystickMode != .horizontalScroll {
                            scrollSpeedRow("Vertical", value: Binding(
                                get: { profiles.activeJoystickScrollSpeed },
                                set: { profiles.activeJoystickScrollSpeed = $0 }
                            ))
                        }
                        if profiles.activeJoystickMode != .verticalScroll {
                            scrollSpeedRow("Horizontal", value: Binding(
                                get: { profiles.activeJoystickHorizontalScrollSpeed },
                                set: { profiles.activeJoystickHorizontalScrollSpeed = $0 }
                            ))
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(panelFill, in: RoundedRectangle(cornerRadius: 12))
    }

    private func scrollSpeedRow(_ axis: String, value: Binding<Int>) -> some View {
        HStack(spacing: 5) {
            Text(axis).font(.caption).frame(width: 62, alignment: .leading)
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0) }
            ), in: 1...5, step: 1)
            .frame(width: 96)
            Text("\(value.wrappedValue)").font(.caption.monospacedDigit()).frame(width: 13)
        }
    }

    private func keyButton(_ name: String, width: CGFloat = 66, height: CGFloat = 36,
                           displayLabel: String? = nil) -> some View {
        let reserved = isReservedDisplayControl(name)
        let icon = effectiveIcon(for: name, isJoystick: false)
        let target = "key:\(name)"
        return Button {
            selectControl(name, isJoystick: false)
        } label: {
            controlFace(label: displayLabel ?? name, icon: icon,
                        iconColor: effectiveIconColor(for: name, isJoystick: false),
                        assignment: displayAssignmentName(for: name),
                        tileHeight: height)
            .frame(width: width, height: height)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .background(reserved ? Color.gray.opacity(0.12) :
                        dropTarget == target ? .green.opacity(0.28) :
                        hasSelectedControl && selectedKey == name && !selectedIsJoystick ? accent.opacity(0.25) :
                        device.pressedKeys.contains(name) ? .orange.opacity(0.25) : tileFill)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(dropTarget == target ? .green :
                     hasSelectedControl && selectedKey == name && !selectedIsJoystick ? accent : .gray.opacity(0.3),
                     lineWidth: dropTarget == target ? 2 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reserved ? "\(name), default display control, editing disabled" :
                            "\(name), \(assignmentName(for: name, isJoystick: false))")
        .help(keyHoverText(for: name))
        .contextMenu {
            if !reserved {
                Button("Record shortcut") {
                    selectControl(name, isJoystick: false, toggle: false)
                }
                Menu("Assign named command") {
                    ForEach(sortedCommands(profiles.commandsVisibleInActiveProfile())) { command in
                        Button(command.name) {
                            _ = profiles.assignVisibleCommand(command.assignment, to: name,
                                                              isJoystick: false)
                        }
                    }
                }
                Button("Clear assignment", role: .destructive) {
                    selectedKey = name
                    selectedIsJoystick = false
                    hasSelectedControl = true
                    profiles.clearKey(name)
                }
            }
        }
        .onDrop(of: [UTType.utf8PlainText.identifier], isTargeted: dropBinding(for: target)) { providers in
            !reserved && handleCommandDrop(providers, on: name, isJoystick: false)
        }
        .opacity(reserved ? 0.52 : 1)
        .disabled(reserved)
    }

    private func joystickDirectionButton(_ direction: String, label: String) -> some View {
        let scrolls = profiles.activeJoystickMode.scrolls(direction)
        let icon = effectiveIcon(for: direction, isJoystick: true)
        let target = "joy:\(direction)"
        let active: Bool = {
            switch direction {
            case "UP": return mapper.joyUp
            case "DOWN": return mapper.joyDown
            case "LEFT": return mapper.joyLeft
            default: return mapper.joyRight
            }
        }()
        return Button {
            selectControl(direction, isJoystick: true)
        } label: {
            controlFace(label: label, icon: icon,
                        iconColor: effectiveIconColor(for: direction, isJoystick: true),
                        assignment: scrolls ? joystickScrollLabel(direction) :
                            assignmentText(for: direction, isJoystick: true),
                        tileHeight: 36)
            .frame(width: 60, height: 36)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .background(scrolls ? Color.gray.opacity(0.12) :
                        dropTarget == target ? .green.opacity(0.28) :
                        hasSelectedControl && selectedKey == direction && selectedIsJoystick ? accent.opacity(0.25) :
                        active ? .orange.opacity(0.25) : tileFill)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(dropTarget == target ? .green :
                     hasSelectedControl && selectedKey == direction && selectedIsJoystick ? accent : .gray.opacity(0.3),
                     lineWidth: dropTarget == target ? 2 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(scrolls ? "Joystick \(label), scroll control, editing disabled" :
                            "Joystick \(label), \(assignmentName(for: direction, isJoystick: true))")
        .help(keyHoverText(for: direction, isJoystick: true))
        .contextMenu {
            if !scrolls {
                Button("Record shortcut") {
                    selectControl(direction, isJoystick: true, toggle: false)
                }
                Menu("Assign named command") {
                    ForEach(sortedCommands(profiles.commandsVisibleInActiveProfile().filter { $0.kind == .keystroke })) { command in
                        Button(command.name) {
                            _ = profiles.assignVisibleCommand(command.assignment, to: direction,
                                                              isJoystick: true)
                        }
                    }
                }
                Button("Clear assignment", role: .destructive) {
                    selectedKey = direction
                    selectedIsJoystick = true
                    hasSelectedControl = true
                    profiles.clearJoystickDirection(direction)
                }
            }
        }
        .onDrop(of: [UTType.utf8PlainText.identifier], isTargeted: dropBinding(for: target)) { providers in
            !scrolls && handleCommandDrop(providers, on: direction, isJoystick: true)
        }
        .opacity(scrolls ? 0.52 : 1)
        .disabled(scrolls)
    }

    @ViewBuilder
    private func controlFace(label: String, icon: String?, iconColor: String?, assignment: String,
                             tileHeight: CGFloat) -> some View {
        VStack(spacing: 2) {
            if showControlLabels && showIcons && icon != nil && !showAssignments {
                Text(label).font(tileHeight >= 50 ? .subheadline.bold() : .caption.bold())
                    .foregroundStyle(accent).lineLimit(1)
                G13IconView(reference: icon, colorOverride: iconColor)
                    .frame(width: tileHeight >= 50 ? 26 : 16,
                           height: tileHeight >= 50 ? 26 : 16)
            } else if showControlLabels || (showIcons && icon != nil) {
                HStack(spacing: 3) {
                    if showIcons, let icon {
                        G13IconView(reference: icon, colorOverride: iconColor)
                            .frame(width: showControlLabels ? (tileHeight >= 50 ? 20 : 16) : (tileHeight >= 50 ? 30 : 24),
                                   height: showControlLabels ? (tileHeight >= 50 ? 20 : 16) : (tileHeight >= 50 ? 30 : 24))
                    }
                    if showControlLabels {
                        Text(label).font(tileHeight >= 50 ? .subheadline.bold() : .caption.bold())
                            .foregroundStyle(accent).lineLimit(1)
                    }
                }
            }
            if showAssignments {
                Text(assignment).font(tileHeight >= 50 ? .caption : .caption2)
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else if showIcons && !showControlLabels && icon == nil {
                Text(assignment == "—" ? label : assignment)
                    .font(tileHeight >= 50 ? .caption.bold() : .caption2.bold())
                    .foregroundStyle(Color.primary.opacity(0.9))
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dropBinding(for target: String) -> Binding<Bool> {
        Binding(get: { dropTarget == target }, set: { isTargeted in
            if isTargeted { dropTarget = target }
            else if dropTarget == target { dropTarget = nil }
        })
    }

    private func handleCommandDrop(_ providers: [NSItemProvider], on key: String,
                                   isJoystick: Bool) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let assignment = object as? String else { return }
            DispatchQueue.main.async {
                _ = acceptDroppedCommand(assignment, on: key, isJoystick: isJoystick)
            }
        }
        return true
    }

    private func acceptDroppedCommand(_ assignment: String, on key: String,
                                      isJoystick: Bool) -> Bool {
        guard isJoystick ? !profiles.activeJoystickMode.scrolls(key) : !isReservedDisplayControl(key) else {
            return false
        }
        guard profiles.assignVisibleCommand(assignment, to: key,
                                            isJoystick: isJoystick) else { return false }
        selectedKey = key
        selectedIsJoystick = isJoystick
        hasSelectedControl = true
        return true
    }

    private func selectControl(_ key: String, isJoystick: Bool, toggle: Bool = true) {
        if toggle && hasSelectedControl && selectedKey == key && selectedIsJoystick == isJoystick {
            hasSelectedControl = false
            return
        }
        selectedKey = key
        selectedIsJoystick = isJoystick
        hasSelectedControl = true
        if !isJoystick || profiles.activeJoystickMode == .keys { shortcutFocusRequest += 1 }
    }

    private var joystickLiveInfo: some View {
        let size: CGFloat = 72
        let x = (CGFloat(device.joystickX) - 128) / 128 * size / 2
        let y = (CGFloat(device.joystickY) - 128) / 128 * size / 2
        return VStack(spacing: 4) {
            Text("POSITION").font(.caption.bold()).foregroundStyle(.secondary)
            ZStack {
                Circle().stroke(.gray.opacity(0.7))
                Circle().fill(.pink.opacity(0.36))
                    .overlay(Circle().stroke(.pink.opacity(0.8), lineWidth: 1))
                    .frame(width: size * CGFloat(profiles.joystickDeadzone) / 128)
                Circle().fill(cyan).frame(width: 5, height: 5).offset(x: x, y: y)
            }
            .frame(width: size, height: size)
            Text("Deadzone \(profiles.joystickDeadzone)")
                .font(.caption2).foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { Double(profiles.joystickDeadzone) },
                set: { profiles.joystickDeadzone = Int($0) }
            ), in: 5...80, step: 5)
            .frame(width: 90)
        }
    }

    private func assignmentName(for key: String, isJoystick: Bool) -> String {
        let raw = assignment(for: key, isJoystick: isJoystick)
        return profiles.command(for: raw)?.name ??
            (raw.hasPrefix("@") ? "Unavailable command" : raw.isEmpty ? "—" : raw)
    }

    private func assignmentText(for key: String, isJoystick: Bool) -> String {
        let raw = assignment(for: key, isJoystick: isJoystick)
        if showShortcutText, let command = profiles.command(for: raw) {
            return command.kind == .mouseFunction ? command.actionDescription :
                command.steps.joined(separator: " → ")
        }
        return assignmentName(for: key, isJoystick: isJoystick)
    }

    private func joystickScrollLabel(_ direction: String) -> String {
        switch direction {
        case "UP": return "Scroll ↑"
        case "DOWN": return "Scroll ↓"
        case "LEFT": return "Scroll ←"
        default: return "Scroll →"
        }
    }

    private func displayAssignmentName(for key: String) -> String {
        if runtime.displayButtonsControlLCD {
            switch key {
            case "BD": return "LCD pages"
            case "L1": return runtime.displayPage == .profiles ? "Profile up" : "No action"
            case "L2": return runtime.displayPage == .profiles ? "Profile down" : "No action"
            case "L3": return runtime.displayPage == .profiles ? "Save startup" : "No action"
            case "L4": return "No action"
            default: break
            }
        }
        return assignmentText(for: key, isJoystick: false)
    }

    private func controlHelp(for key: String) -> String {
        if runtime.displayButtonsControlLCD {
            switch key {
            case "BD": return "Cycle Overview, Profiles, and CPU/RAM on the G13 screen. Turn off LCD controls to use its saved shortcut."
            case "L1", "L2": return "Change profiles on the Profiles page; no LCD action on other pages. Turn off LCD controls to use its saved shortcut."
            case "L3": return "Save the active startup profile on the Profiles page; no LCD action elsewhere. Turn off LCD controls to use its saved shortcut."
            case "L4": return "No LCD action. Turn off LCD controls to use its saved shortcut."
            default: break
            }
        }
        if key == "BD" {
            return "Assign a shortcut or command, or enable screen controls in Settings."
        }
        if ["L1", "L2", "L3", "L4"].contains(key) {
            return "Assign a shortcut or command, or enable LCD controls beside G13 Keys."
        }
        return "Select to edit or drop a saved command here."
    }

    private func keyHoverText(for key: String, isJoystick: Bool = false) -> String {
        if isJoystick && profiles.activeJoystickMode.scrolls(key) {
            return "Joystick \(key.capitalized) · \(joystickScrollLabel(key))\nSaved key assignment: \(assignmentName(for: key, isJoystick: true))"
        }
        if !isJoystick && runtime.displayButtonsControlLCD &&
            (["BD", "L1", "L2", "L3", "L4"].contains(key)) {
            return "\(key) · \(displayAssignmentName(for: key))\n\(controlHelp(for: key))"
        }
        let raw = assignment(for: key, isJoystick: isJoystick)
        if let command = profiles.command(for: raw) {
            return "\(key) · \(command.name)\n\(command.kind == .mouseFunction ? command.actionDescription : command.steps.joined(separator: " → "))"
        }
        return "\(key) · \(assignmentName(for: key, isJoystick: isJoystick))"
    }

    private func effectiveIcon(for key: String, isJoystick: Bool) -> String? {
        if isJoystick && profiles.activeJoystickMode.scrolls(key) {
            switch key {
            case "UP": return "sf:arrow.up"
            case "DOWN": return "sf:arrow.down"
            case "LEFT": return "sf:arrow.left"
            default: return "sf:arrow.right"
            }
        }
        if !isJoystick && isReservedDisplayControl(key) {
            switch key {
            case "BD": return "sf:display"
            case "L1" where runtime.displayPage == .profiles: return "sf:arrow.up"
            case "L2" where runtime.displayPage == .profiles: return "sf:arrow.down"
            case "L3" where runtime.displayPage == .profiles: return "sf:lock.fill"
            default: return nil
            }
        }
        if let override = profiles.iconReference(for: key, isJoystick: isJoystick) {
            return override == "none" ||
                (override.hasPrefix("custom:") && G13IconStore.image(for: override) == nil) ? nil : override
        }
        guard let reference = profiles.command(for: assignment(for: key, isJoystick: isJoystick))?.iconReference else {
            return nil
        }
        return reference.hasPrefix("custom:") && G13IconStore.image(for: reference) == nil ? nil : reference
    }

    private func effectiveIconColor(for key: String, isJoystick: Bool) -> String? {
        profiles.iconColor(for: key, isJoystick: isJoystick) ??
            profiles.command(for: assignment(for: key, isJoystick: isJoystick))?.iconColor
    }

    private func assignment(for key: String, isJoystick: Bool) -> String {
        if isJoystick {
            switch profiles.activeLayer {
            case 2: return profiles.activeProfile?.m2JoystickMapping?[key] ?? ""
            case 3: return profiles.activeProfile?.m3JoystickMapping?[key] ?? ""
            default: return profiles.activeProfile?.joystickMapping[key] ?? ""
            }
        }
        return profiles.activeRawKeyMapping[key] ?? ""
    }

    private func isReservedDisplayControl(_ key: String) -> Bool {
        runtime.displayButtonsControlLCD && ["BD", "L1", "L2", "L3", "L4"].contains(key)
    }

    private var selectedControlIsReserved: Bool {
        !hasSelectedControl || (selectedIsJoystick ? profiles.activeJoystickMode.scrolls(selectedKey) :
            isReservedDisplayControl(selectedKey)
        )
    }

    private var namedCommandPicker: some View {
        let query = namedCommandSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = profiles.commandsVisibleInActiveProfile()
            .filter { !selectedIsJoystick || $0.kind == .keystroke }
            .filter { command in
                query.isEmpty || command.name.localizedCaseInsensitiveContains(query) ||
                    command.actionDescription.localizedCaseInsensitiveContains(query) ||
                    (command.applicationBundleID == nil ? "All Apps" : profiles.activeProfileName)
                        .localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Assign named command").font(.headline)
            TextField("Type a name or shortcut", text: $namedCommandSearch)
                .textFieldStyle(.roundedBorder)
                .focused($namedCommandSearchFocused)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(candidates) { command in
                        Button {
                            setAssignment(command.assignment)
                            showNamedCommandPicker = false
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(command.name).fontWeight(.medium)
                                Text("\(command.actionDescription) · \(command.applicationBundleID == nil ? "All Apps" : profiles.activeProfileName)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(5)
                        }
                        .buttonStyle(.plain)
                    }
                    if candidates.isEmpty {
                        Text("No matching commands")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 230)
        }
        .frame(width: 310)
        .padding(12)
        .onAppear { namedCommandSearchFocused = true }
    }

    private var assignmentPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SELECTED CONTROL").font(.caption.bold()).foregroundStyle(accent)
                Spacer()
                if hasSelectedControl {
                    Button { hasSelectedControl = false } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help("Deselect control")
                    .accessibilityLabel("Deselect control")
                }
            }
            if hasSelectedControl {
            Text(selectedIsJoystick ? "Joystick \(selectedKey.capitalized)" :
                 (selectedKey == "LEFT" ? "Thumb Left" : selectedKey == "RIGHT" ? "Thumb Bottom" : selectedKey))
                .font(.title3.bold())
            Text(assignmentText(for: selectedKey, isJoystick: selectedIsJoystick))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if !selectedIsJoystick && runtime.displayButtonsControlLCD &&
                ["BD", "L1", "L2", "L3", "L4"].contains(selectedKey) {
                Text("Default display controls are on. Uncheck the box beside G13 Keys to edit this button's saved assignment.")
                    .font(.caption2).foregroundStyle(.orange)
            }
            if selectedIsJoystick && profiles.activeJoystickMode.scrolls(selectedKey) {
                Text("This direction scrolls in the current mode. Its saved key assignment returns when the direction is used for keys.")
                    .font(.caption2).foregroundStyle(.orange)
            }
            if !selectedIsJoystick && (["BD", "L1", "L2", "L3", "L4"].contains(selectedKey)) {
                Text(controlHelp(for: selectedKey))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            Text("Assign named command").font(.subheadline.bold())
            Button("Choose command…") {
                namedCommandSearch = ""
                showNamedCommandPicker = true
            }
            .popover(isPresented: $showNamedCommandPicker) { namedCommandPicker }
            .disabled(profiles.commands.isEmpty || selectedControlIsReserved)
            Text("Click a control or this field, then press a shortcut. Esc cancels.")
                .font(.caption).foregroundStyle(.secondary)
            ShortcutField(value: directShortcutForSelectedControl,
                          focusRequest: shortcutFocusRequest) { setAssignment($0) }
                .id("\(selectedKey):\(selectedIsJoystick)")
                .disabled(selectedControlIsReserved)
            if !selectedIsJoystick, KeyAction.parse(directShortcutForSelectedControl) != nil {
                Button("Make timed hold command…") {
                    var new = G13Command(name: "Hold \(directShortcutForSelectedControl)",
                                         kind: .keystroke, steps: [directShortcutForSelectedControl])
                    new.holdMilliseconds = 1300
                    new.applicationBundleID = profiles.activeProfile?.applicationBundleID
                    assignEditedCommandToSelectedControl = true
                    editingCommand = new
                }
                .disabled(selectedControlIsReserved)
            }
            Button("Clear assignment") { setAssignment("") }
                .disabled(selectedControlIsReserved)
            Divider()
            Text("Key image").font(.subheadline.bold())
            G13IconPicker(
                selectedReference: profiles.iconReference(for: selectedKey, isJoystick: selectedIsJoystick),
                inheritedReference: profiles.command(for: assignment(for: selectedKey,
                                                                       isJoystick: selectedIsJoystick))?.iconReference,
                allowInherit: true
            ) { reference in
                if !selectedControlIsReserved {
                    profiles.setIconReference(reference, for: selectedKey, isJoystick: selectedIsJoystick)
                }
            }
            .disabled(selectedControlIsReserved)
            G13IconColorPicker(selection: Binding(
                get: { profiles.iconColor(for: selectedKey, isJoystick: selectedIsJoystick) },
                set: { profiles.setIconColor($0, for: selectedKey, isJoystick: selectedIsJoystick) }
            ))
            .disabled(selectedControlIsReserved)
            } else {
                Text("No control selected")
                    .font(.title3.bold())
                Text("Select a G13 key or joystick direction to view and edit its assignment. Click it again to deselect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if runtime.isSafeTestMode {
                Divider()
                Text("SAFE TEST · NO OUTPUT SENT")
                    .font(.caption.bold()).foregroundStyle(.green)
                ForEach(Array(runtime.testEvents.prefix(4).enumerated()), id: \.offset) { _, event in
                    Text(event).font(.caption2).lineLimit(2)
                }
                if runtime.testEvents.isEmpty {
                    Text("Press a G13 key or move the joystick to preview its action.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            }
            .frame(width: 198, alignment: .leading)
            .padding(10)
        }
        .frame(width: 220, height: 360)
        .background(panelFill, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .fixedSize(horizontal: true, vertical: true)
    }

    private func setAssignment(_ value: String) {
        guard hasSelectedControl, !selectedControlIsReserved else { return }
        if selectedIsJoystick {
            if value.isEmpty { profiles.clearJoystickDirection(selectedKey) }
            else { profiles.setJoystickDirection(selectedKey, to: value) }
        } else {
            if value.isEmpty { profiles.clearKey(selectedKey) }
            else { profiles.setKey(selectedKey, to: value) }
        }
    }

    private var directShortcutForSelectedControl: String {
        let raw = assignment(for: selectedKey, isJoystick: selectedIsJoystick)
        return raw.hasPrefix("@") ? "" : raw
    }

    private var colorPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BACKLIGHT COLOR · M\(profiles.activeLayer)").font(.headline).foregroundStyle(accent)
            HStack(spacing: 7) {
                ForEach(palette, id: \.0) { item in
                    Button {
                        profiles.setBacklightColor(G13BacklightColor(
                            red: Int(item.1), green: Int(item.2), blue: Int(item.3)))
                        runtime.applyActiveProfile()
                    } label: {
                        Circle().fill(Color(red: Double(item.1)/255, green: Double(item.2)/255, blue: Double(item.3)/255))
                            .frame(width: 25, height: 25)
                    }
                    .buttonStyle(.plain)
                    .help(item.0)
                }
            }
            colorSlider("Red", value: Binding(get: { Double(profiles.backlightR) }, set: { profiles.backlightR = UInt8($0); runtime.applyActiveProfile() }))
            colorSlider("Green", value: Binding(get: { Double(profiles.backlightG) }, set: { profiles.backlightG = UInt8($0); runtime.applyActiveProfile() }))
            colorSlider("Blue", value: Binding(get: { Double(profiles.backlightB) }, set: { profiles.backlightB = UInt8($0); runtime.applyActiveProfile() }))
        }
        .padding(16)
        .background(panelFill, in: RoundedRectangle(cornerRadius: 12))
    }

    private func colorSlider(_ name: String, value: Binding<Double>) -> some View {
        HStack {
            Text(name).frame(width: 45, alignment: .leading)
            Slider(value: value, in: 0...255, step: 1)
            Text("\(Int(value.wrappedValue))").monospacedDigit().frame(width: 30)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Label(device.isConnected ? "G13 connected" : "G13 disconnected",
                  systemImage: device.isConnected ? "checkmark.circle.fill" : "circle.dotted")
                .foregroundStyle(device.isConnected ? .green : .orange)
                .frame(width: 125, alignment: .leading)
            Text(runtime.isSafeTestMode ? "Safe Test · no output sent" :
                 profiles.editorIsFrontmost ? "Editor active · output paused" :
                 !mapper.hasAccessibility ? "Accessibility needed · open Settings" :
                 "Output: \(profiles.outputProfileName) · M\(profiles.activeLayer)")
                .foregroundStyle(profiles.editorIsFrontmost ? Color.orange : Color.secondary)
                .lineLimit(1).minimumScaleFactor(0.85)
                .frame(width: 360, alignment: .leading)
            Spacer(minLength: 0)
            Button {
                showWarnings = true
            } label: {
                Label("\(profiles.activeWarnings.unassignedKeys.count) unassigned · \(profiles.activeWarnings.destructiveAssignments.count) caution",
                      systemImage: "exclamationmark.triangle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(profiles.activeWarnings.destructiveAssignments.isEmpty ? Color.secondary : Color.orange)
            .frame(width: 190, alignment: .trailing)
            .popover(isPresented: $showWarnings) {
                warningsPopover
            }
        }
        .font(.caption)
        .frame(height: 26)
    }

    private var warningsPopover: some View {
        let warnings = profiles.activeWarnings
        return VStack(alignment: .leading, spacing: 10) {
            Text("Review M\(profiles.activeLayer) · \(profiles.activeProfileName)")
                .font(.headline)
            Text("\(warnings.unassignedKeys.count) G keys are unassigned")
                .fontWeight(.medium)
            Text(warnings.unassignedKeys.isEmpty ? "Every G key has an assignment." : warnings.unassignedKeys.joined(separator: ", "))
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Commands to check before use")
                .fontWeight(.medium)
            if warnings.destructiveAssignments.isEmpty {
                Text("None on this layer")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(warnings.destructiveAssignments, id: \.self) { warning in
                    Text(warning).font(.caption).foregroundStyle(.orange)
                }
            }
            Text("Warnings are guidance for the selected layer. They do not prevent output.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(width: 310, alignment: .leading)
        .padding(14)
    }
}

private struct ShortcutField: View {
    let value: String
    let focusRequest: Int
    let onCommit: (String) -> Void
    @State private var showManualEntry = false
    @State private var manualText = ""

    var body: some View {
        HStack(spacing: 6) {
            ShortcutCaptureField(value: value, focusRequest: focusRequest, onCapture: onCommit)
                .frame(width: 132, height: 26)
            Button("Type…") {
                manualText = value
                showManualEntry = true
            }
            .frame(width: 58)
            .popover(isPresented: $showManualEntry) {
                HStack {
                    TextField("CMD+S", text: $manualText)
                        .frame(width: 170)
                        .onSubmit(commitManual)
                    Button("Set", action: commitManual)
                }
                .padding(12)
            }
        }
        .frame(width: 196, height: 28, alignment: .leading)
    }

    private func commitManual() {
        let candidate = manualText.trimmingCharacters(in: .whitespaces).uppercased()
        if candidate.isEmpty || KeyAction.parse(candidate) != nil {
            onCommit(candidate)
            showManualEntry = false
        }
    }
}

private struct CommandEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var profiles: ProfileManager
    let onSave: (G13Command) -> Void
    let appBundleID: String?
    let appName: String
    @State private var command: G13Command
    @State private var newStep = ""
    @State private var recording = false
    @State private var recordingMessage = ""
    @State private var showKeySearch = false
    @State private var keySearch = ""
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var folderCreationError: String?

    init(command: G13Command, profiles: ProfileManager, appBundleID: String?, appName: String,
         onSave: @escaping (G13Command) -> Void) {
        _command = State(initialValue: command)
        self.profiles = profiles
        self.appBundleID = appBundleID
        self.appName = appName
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Command editor").font(.title2.bold())
                Spacer()
                Picker("Type", selection: $command.kind) {
                    Text("Keystroke").tag(G13Command.Kind.keystroke)
                    Text("Multi Key").tag(G13Command.Kind.multiKey)
                    Text("Mouse").tag(G13Command.Kind.mouseFunction)
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                .onChange(of: command.kind) { _, kind in
                    recording = false
                    if kind != .keystroke { command.holdMilliseconds = nil }
                    if kind == .keystroke { command.steps = Array(command.steps.prefix(1)) }
                    if kind == .mouseFunction {
                        command.steps = []
                        command.mouseAction = command.mouseAction ?? .leftClick
                    }
                }
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Command name", text: $command.name)
                    Picker("Available in", selection: $command.applicationBundleID) {
                        Text("All Apps").tag(String?.none)
                        if let appBundleID {
                            Text(appName).tag(Optional(appBundleID))
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: command.applicationBundleID) { _, _ in command.folderID = nil }
                    HStack {
                        Picker("Folder", selection: $command.folderID) {
                            Text("Unfiled").tag(UUID?.none)
                            ForEach(profiles.folders(for: command.applicationBundleID)) { folder in
                                Text(folder.name).tag(Optional(folder.id))
                            }
                        }
                        .pickerStyle(.menu)
                        Button("New folder…") {
                            newFolderName = ""
                            showNewFolder = true
                        }
                    }
                    .alert("New command folder", isPresented: $showNewFolder) {
                        TextField("Folder name", text: $newFolderName)
                        Button("Create") {
                            if let folder = profiles.addCommandFolder(name: newFolderName,
                                                   applicationBundleID: command.applicationBundleID) {
                                command.folderID = folder.id
                            } else {
                                folderCreationError = "Use a unique folder name between 1 and 80 characters."
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This folder will belong to \(command.applicationBundleID == nil ? "All Apps" : appName).")
                    }
                    .alert("Folder name", isPresented: Binding(
                        get: { folderCreationError != nil }, set: { if !$0 { folderCreationError = nil } }
                    )) {
                        Button("OK") { folderCreationError = nil }
                    } message: {
                        Text(folderCreationError ?? "")
                    }
                    HStack {
                        Text("Command image")
                        G13IconPicker(selectedReference: command.iconReference,
                                      inheritedReference: nil, allowInherit: false) { reference in
                            command.iconReference = reference
                        }
                    }
                    G13IconColorPicker(selection: $command.iconColor)
                    if command.kind == .mouseFunction {
                        Picker("Mouse action", selection: $command.mouseAction) {
                            ForEach(G13MouseAction.allCases, id: \.self) { action in
                                Text(action.label).tag(Optional(action))
                            }
                        }
                        .pickerStyle(.menu)
                        Text("Modifiers for this click")
                            .font(.subheadline.bold())
                        HStack(spacing: 12) {
                            ForEach(G13MouseModifier.allCases, id: \.self) { modifier in
                                Toggle(modifier.label, isOn: Binding(
                                    get: { command.mouseModifiers?.contains(modifier) == true },
                                    set: { enabled in
                                        var selected = command.mouseModifiers ?? []
                                        if enabled && !selected.contains(modifier) { selected.append(modifier) }
                                        if !enabled { selected.removeAll { $0 == modifier } }
                                        command.mouseModifiers = selected
                                    }
                                ))
                                .toggleStyle(.checkbox)
                            }
                        }
                        Text("Clicks at the pointer’s current position with these modifiers, plus any G13 modifiers already held.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                    HStack {
                        TextField("Key or chord (for example CMD+S)", text: $newStep)
                            .onSubmit(addStep)
                            .frame(width: 315)
                        Button("Find key…") {
                            keySearch = ""
                            showKeySearch = true
                        }
                        .popover(isPresented: $showKeySearch) {
                            keySearchPopover
                        }
                        Button("Add") { addStep() }
                            .disabled(!canAdd)
                    }
                    Button(recording ? "Stop recording" : "Record keys in this window") {
                        recording.toggle()
                        recordingMessage = recording ? "Hold modifiers, then press a key…" : ""
                    }
                    .buttonStyle(.borderedProminent)
                    Text(recording ? recordingMessage :
                         "Record complete shortcuts here. Keystroke stops after one; Multi Key continues until Stop.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(height: 28, alignment: .topLeading)
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(command.steps.enumerated()), id: \.offset) { index, step in
                                HStack {
                                    Text("\(index + 1). \(step)")
                                    Spacer()
                                    Button("Remove") { command.steps.remove(at: index) }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(height: 96)
                    if command.kind == .keystroke {
                        Toggle("Hold key for a set time", isOn: Binding(
                            get: { command.holdMilliseconds != nil },
                            set: { command.holdMilliseconds = $0 ? (command.holdMilliseconds ?? 1300) : nil }
                        ))
                        if command.holdMilliseconds != nil {
                            Stepper(value: Binding(
                                get: { Double(command.holdMilliseconds ?? 1300) / 1000 },
                                set: { command.holdMilliseconds = Int(($0 * 1000).rounded()) }
                            ), in: 0.1...30, step: 0.1) {
                                Text("Duration: \(Double(command.holdMilliseconds ?? 1300) / 1000, specifier: "%.1f") seconds")
                            }
                            Text("The G13 key starts the hold. It releases after this time, or immediately on profile change or disconnect.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Delay between keys (ms)")
                        TextField("50", value: $command.delayMilliseconds, format: .number)
                            .frame(width: 70)
                        Text("25–1000").foregroundStyle(.secondary)
                    }
                    .frame(height: 26)
                    .opacity(command.kind == .multiKey ? 1 : 0)
                    .disabled(command.kind != .multiKey)
                    .accessibilityHidden(command.kind != .multiKey)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    command.delayMilliseconds = min(max(command.delayMilliseconds, 25), 1000)
                    onSave(command)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(command.name.trimmingCharacters(in: .whitespaces).isEmpty || !command.isValidAction)
            }
        }
        .padding(24)
        .frame(width: 540, height: 500, alignment: .topLeading)
        .background(CommandShortcutRecorder(isRecording: recording) { step in
            if command.kind == .keystroke {
                command.steps = [step]
                recording = false
                recordingMessage = "Captured \(step)"
            } else if command.kind == .multiKey && command.steps.count < 16 {
                command.steps.append(step)
                recordingMessage = "Captured \(step) · \(command.steps.count) of 16 steps"
            } else {
                recording = false
                recordingMessage = "16-step limit reached"
            }
        })
    }

    private var canAdd: Bool {
        command.kind != .mouseFunction &&
        KeyAction.parse(newStep.trimmingCharacters(in: .whitespaces).uppercased()) != nil &&
        (command.kind == .keystroke || command.steps.count < 16)
    }

    private var keySearchPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Find a key").font(.headline)
            TextField("Search, e.g. numpad or return", text: $keySearch)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(matchingKeyNames, id: \.self) { key in
                        Button(key) {
                            newStep = key
                            showKeySearch = false
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(height: 220)
            Text("Choose a key, then add modifiers in the text field (for example CMD+S).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 260)
        .padding(12)
    }

    private var matchingKeyNames: [String] {
        let names = KeyMapper.macKeycodes.keys.filter { KeyAction.parse($0) != nil }.sorted()
        let query = keySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return Array((query.isEmpty ? names : names.filter { $0.localizedCaseInsensitiveContains(query) }).prefix(60))
    }

    private func addStep() {
        guard canAdd else { return }
        let step = newStep.trimmingCharacters(in: .whitespaces).uppercased()
        if command.kind == .keystroke { command.steps = [step] }
        else { command.steps.append(step) }
        newStep = ""
    }
}
